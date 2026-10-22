// Avisa no celular da tesoureira e do administrador os lembretes de doação
// que venceram (data de hoje ou anterior) e ainda não foram marcados como feitos.
//
// QUEM CHAMA
// O agendamento do banco (pg_cron + pg_net), todo dia às 8h de Brasília — ver
// supabase/atualizacao-avisos-push.sql. Não é chamada pelo app: por isso exige
// o segredo CRON_SECRET no cabeçalho x-cron-secret.
//
// PRA QUEM VAI
// Todo celular que ativou os avisos em Tesouraria → ⚙ (tabela push_inscricoes).
// Só quem lança na Tesouraria vê esse botão, então só eles se inscrevem.
//
// TESTE
// POST com {"teste": true} manda uma notificação de teste a todos os inscritos,
// mesmo sem lembrete vencido.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const json = (corpo: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

const brl = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v || 0);
// Brasília = UTC-3 (sem horário de verão hoje).
const hojeBrasilia = () => new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10);
const primeiroNome = (n: string) => (n || '').trim().split(/\s+/)[0] || 'doador';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ erro: 'Use POST.' }, 405);

  const segredo = Deno.env.get('CRON_SECRET');
  if (!segredo || req.headers.get('x-cron-secret') !== segredo) return json({ erro: 'Não autorizado.' }, 401);

  const url = Deno.env.get('SUPABASE_URL');
  const servico = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const vapidPublica = Deno.env.get('VAPID_PUBLIC_KEY');
  const vapidPrivada = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!url || !servico || !vapidPublica || !vapidPrivada) return json({ erro: 'Função mal configurada: faltam variáveis de ambiente.' }, 500);

  let corpo: { teste?: boolean } = {};
  try { corpo = await req.json(); } catch { /* corpo vazio */ }

  const db = createClient(url, servico);

  // ---- lembretes vencidos e ainda não feitos ----
  const { data: lemb, error: erroLemb } = await db
    .from('tesouraria_lancamentos')
    .select('id, valor, solicitado_por, descricao, doador_id, lembrete_data')
    .eq('tipo', 'entrada')
    .not('lembrete_data', 'is', null)
    .is('lembrete_feito_em', null)
    .lte('lembrete_data', hojeBrasilia())
    .order('lembrete_data');
  if (erroLemb) return json({ erro: 'Não consegui ler os lembretes: ' + erroLemb.message }, 500);

  const pendentes = lemb || [];
  if (!pendentes.length && !corpo.teste) return json({ lembretes: 0, enviados: 0 });

  // ---- nomes dos doadores ----
  const ids = [...new Set(pendentes.map((l) => l.doador_id).filter(Boolean))];
  const nomes = new Map<string, string>();
  if (ids.length) {
    const { data: doadores } = await db.from('tesouraria_doadores').select('id, nome').in('id', ids);
    (doadores || []).forEach((d) => nomes.set(d.id, d.nome));
  }
  const nomeDe = (l: { doador_id: string | null; descricao: string | null }) =>
    (l.doador_id && nomes.get(l.doador_id)) || l.descricao || 'doador';

  // ---- texto da notificação ----
  let titulo = 'Lembrete de doação';
  let texto: string;
  if (!pendentes.length) {
    titulo = 'Cedros Digital';
    texto = 'Teste: os avisos de doação estão funcionando neste celular.';
  } else if (pendentes.length === 1) {
    const l = pendentes[0];
    texto = `Lembrar ${nomeDe(l)} da doação de ${brl(Number(l.valor))}` + (l.solicitado_por ? ` (pediu: ${l.solicitado_por})` : '');
  } else {
    const nm = pendentes.slice(0, 3).map((l) => primeiroNome(nomeDe(l)));
    const resto = pendentes.length - nm.length;
    texto = `${pendentes.length} doações para lembrar: ${nm.join(', ')}` + (resto > 0 ? ` e mais ${resto}` : '');
    titulo = `${pendentes.length} lembretes de doação`;
  }

  // ---- envio ----
  const { data: inscritos, error: erroIns } = await db.from('push_inscricoes').select('id, endpoint, p256dh, auth');
  if (erroIns) return json({ erro: 'Não consegui ler as inscrições: ' + erroIns.message }, 500);

  webpush.setVapidDetails('https://cedros-digital.adrodrigues-ahi.workers.dev', vapidPublica, vapidPrivada);
  const mensagem = JSON.stringify({ title: titulo, body: texto, tag: 'cedros-doacao', url: './' });
  let enviados = 0;
  const falhas: string[] = [];
  const expirados: string[] = [];
  await Promise.all((inscritos || []).map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, mensagem, { TTL: 60 * 60 * 12 });
      enviados++;
    } catch (e) {
      const status = (e as { statusCode?: number }).statusCode;
      if (status === 404 || status === 410) expirados.push(s.id); // celular desinstalou ou revogou
      else falhas.push(String(status || (e as Error).message));
    }
  }));
  if (expirados.length) await db.from('push_inscricoes').delete().in('id', expirados);

  return json({ lembretes: pendentes.length, inscritos: (inscritos || []).length, enviados, expirados: expirados.length, falhas });
});
