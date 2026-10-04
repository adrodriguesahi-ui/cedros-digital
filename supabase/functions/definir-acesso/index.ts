// Define a senha de acesso de um membro do clube.
//
// POR QUE ISTO VIVE NO SERVIDOR
// Criar conta ou trocar a senha de OUTRA pessoa exige a chave service_role do
// Supabase, que ignora todas as regras de acesso do banco. O app é um HTML
// servido publicamente — qualquer um lê o código-fonte. Se a chave estivesse
// lá, estaria entregue, e com ela o banco inteiro (inclusive dados de
// menores). Aqui ela fica numa variável de ambiente da função, que o navegador
// nunca vê.
//
// QUEM PODE CHAMAR
// Só administrador. E isso NÃO é perguntado ao app: a função lê o token de
// quem chamou, descobre quem é pelo próprio Supabase e confere na tabela
// usuarios. App mente; token assinado não.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SENHA_MINIMA = 8;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function resposta(corpo: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return resposta({ erro: 'Use POST.' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const servico = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !servico) {
    return resposta({ erro: 'Função mal configurada: faltam variáveis de ambiente.' }, 500);
  }

  // ---- 1) quem está chamando? ----
  const autorizacao = req.headers.get('Authorization') || '';
  if (!autorizacao.startsWith('Bearer ')) {
    return resposta({ erro: 'Faça login de novo e tente outra vez.' }, 401);
  }

  const comoUsuario = createClient(url, anon, {
    global: { headers: { Authorization: autorizacao } },
  });
  const { data: { user: quemChamou }, error: erroToken } = await comoUsuario.auth.getUser();
  if (erroToken || !quemChamou?.email) {
    return resposta({ erro: 'Sessão expirada. Faça login de novo.' }, 401);
  }

  const admin = createClient(url, servico);

  // ---- 2) é administrador mesmo? ----
  // Lido com a chave de serviço de propósito: se dependesse das regras de
  // acesso do banco, uma mudança de RLS poderia deixar isto passar sem querer.
  const { data: perfil, error: erroPerfil } = await admin
    .from('usuarios')
    .select('papel, acesso, ativo, aprovado')
    .eq('email', quemChamou.email)
    .maybeSingle();

  if (erroPerfil) return resposta({ erro: 'Não consegui conferir sua permissão.' }, 500);

  const ehAdmin = !!perfil
    && perfil.ativo !== false
    && perfil.aprovado !== false
    && (perfil.papel === 'Administrador' || perfil?.acesso?.admin === true);

  if (!ehAdmin) {
    return resposta({ erro: 'Só administrador pode definir senha de acesso.' }, 403);
  }

  // ---- 3) o pedido ----
  let corpo: { email?: string; senha?: string; provisoria?: boolean };
  try {
    corpo = await req.json();
  } catch {
    return resposta({ erro: 'Pedido inválido.' }, 400);
  }

  const email = (corpo.email || '').trim().toLowerCase();
  const senha = corpo.senha || '';
  // Provisória por padrão: senha que outra pessoa escolheu não deveria ficar
  // valendo pra sempre. Quem quiser o contrário manda false de propósito.
  const provisoria = corpo.provisoria !== false;

  if (!email) return resposta({ erro: 'Informe o e-mail da pessoa.' }, 400);
  if (senha.length < SENHA_MINIMA) {
    return resposta({ erro: `A senha precisa ter pelo menos ${SENHA_MINIMA} caracteres.` }, 400);
  }

  // A pessoa precisa ter ficha no clube. Sem isto, a função viraria uma porta
  // pra criar login de qualquer e-mail no projeto.
  const { data: fichaAlvo } = await admin
    .from('usuarios').select('id, nome').eq('email', email).maybeSingle();
  if (!fichaAlvo) {
    return resposta({ erro: 'Esse e-mail não está cadastrado no clube. Salve o usuário primeiro.' }, 404);
  }

  // ---- 4) criar ou atualizar a conta ----
  // listUsers não filtra por e-mail na versão atual, então procuro na página.
  // O clube tem dezenas de pessoas, não milhares; se um dia crescer, isto vira
  // uma consulta em auth.users pelo lado do banco.
  const { data: lista, error: erroLista } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (erroLista) return resposta({ erro: 'Não consegui consultar as contas: ' + erroLista.message }, 500);

  const existente = (lista?.users || []).find(
    (u) => (u.email || '').toLowerCase() === email,
  );

  // Marca (ou desmarca) a provisoriedade junto com a senha. Se a coluna ainda
  // não existir no banco, não derruba a operação: a senha é o que importa, e o
  // pedido de troca é um extra.
  async function marcarProvisoria() {
    const { error } = await admin
      .from('usuarios').update({ senha_provisoria: provisoria }).eq('id', fichaAlvo.id);
    if (error) console.warn('senha_provisoria não gravou:', error.message);
    return !error;
  }

  if (existente) {
    const { error } = await admin.auth.admin.updateUserById(existente.id, { password: senha });
    if (error) return resposta({ erro: 'Não consegui trocar a senha: ' + error.message }, 500);
    const marcou = await marcarProvisoria();
    return resposta({ ok: true, acao: 'senha_trocada', nome: fichaAlvo.nome, provisoria: provisoria && marcou });
  }

  const { error } = await admin.auth.admin.createUser({
    email,
    password: senha,
    // Confirmado na hora: boa parte do clube foi cadastrada com e-mail de
    // fachada (ex.: matricula@sememail.local), que nunca receberia o link de
    // confirmação. Sem isto, essas contas nasceriam travadas.
    email_confirm: true,
  });
  if (error) return resposta({ erro: 'Não consegui criar o acesso: ' + error.message }, 500);

  const marcou = await marcarProvisoria();
  return resposta({ ok: true, acao: 'acesso_criado', nome: fichaAlvo.nome, provisoria: provisoria && marcou });
});
