// Worker do Cedros Digital: serve o site estático (site sem build, ver
// wrangler.toml) e só desvia pra lógica própria a rota /api/suggest-missions,
// usada pelo botão "Sugerir com IA" na tela Missões (ver index.html). A chave
// da API da IA fica guardada como secret aqui (nunca no app, que é público) —
// configurar em Workers & Pages → cedros-digital → Settings → Variables and
// Secrets → adicionar ANTHROPIC_API_KEY.

const SUPABASE_URL = 'https://noqaveawzxipxnmufwfn.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_-w3hya9Qp73MAM1B1FhuFQ_v2DWv6lk';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/api/suggest-missions') {
      if (request.method !== 'POST') return jsonResponse({ error: 'Método não permitido.' }, 405);
      return handleSuggestMissions(request, env);
    }
    return env.ASSETS.fetch(request);
  }
};

async function handleSuggestMissions(request, env) {
  if (!env.ANTHROPIC_API_KEY) {
    return jsonResponse({ error: 'IA não configurada neste ambiente.' }, 500);
  }

  // Barreira mínima contra uso anônimo: exige um token de sessão Supabase
  // válido (qualquer usuário logado no app — a checagem de cargo/Diretoria
  // já acontece no app, igual ao resto do sistema). Não gasta a API da IA
  // sem alguém autenticado por trás.
  const authHeader = request.headers.get('authorization') || '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'Faça login pra usar a IA.' }, 401);

  const authCheck = await fetch(SUPABASE_URL + '/auth/v1/user', {
    headers: { apikey: SUPABASE_ANON_KEY, authorization: 'Bearer ' + token }
  });
  if (!authCheck.ok) return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);

  let body = {};
  try { body = await request.json(); } catch (e) { /* corpo vazio é aceitável */ }
  const existingTitles = Array.isArray(body.existingTitles) ? body.existingTitles.slice(0, 30).filter(t => typeof t === 'string') : [];

  const prompt =
    'Você ajuda a Diretoria de um clube de Desbravadores (Adventist Pathfinders, igreja adventista) a criar ' +
    '"missões" — tarefas simples e gamificadas que crianças e adolescentes do clube cumprem no dia a dia ' +
    '(ex.: levar um amigo pra reunião, ajudar na organização do salão, memorizar um texto bíblico, participar ' +
    'de uma atividade ao ar livre, ajudar um colega mais novo, contribuir numa ação comunitária).\n\n' +
    'Gere exatamente 5 sugestões de missões variadas e apropriadas pra crianças/adolescentes de um clube de ' +
    'igreja. Evite repetir estas já cadastradas: ' + (existingTitles.length ? existingTitles.join(', ') : '(nenhuma ainda)') + '.\n\n' +
    'Responda SOMENTE com um JSON array válido, sem nenhum texto antes ou depois, neste formato exato:\n' +
    '[{"titulo": "...", "descricao": "...", "pontos": 10}]\n\n' +
    'Regras: "titulo" curto (até 60 caracteres); "descricao" com 1-2 frases explicando a missão; "pontos" ' +
    'um número inteiro entre 5 e 30, proporcional ao esforço da missão.';

  let aiResp;
  try {
    aiResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-5',
        max_tokens: 1024,
        messages: [{ role: 'user', content: prompt }]
      })
    });
  } catch (e) {
    return jsonResponse({ error: 'Não foi possível falar com a IA agora.' }, 502);
  }

  if (!aiResp.ok) {
    const detail = await aiResp.text().catch(() => '');
    return jsonResponse({ error: 'A IA retornou um erro.', detail: detail.slice(0, 300) }, 502);
  }

  const data = await aiResp.json();
  const textBlock = Array.isArray(data.content) ? data.content.find(b => b.type === 'text') : null;
  if (!textBlock || !textBlock.text) return jsonResponse({ error: 'A IA não retornou texto.' }, 502);

  let suggestions;
  try {
    const match = textBlock.text.match(/\[[\s\S]*\]/);
    suggestions = JSON.parse(match ? match[0] : textBlock.text);
  } catch (e) {
    return jsonResponse({ error: 'Resposta da IA em formato inesperado.' }, 502);
  }
  if (!Array.isArray(suggestions)) return jsonResponse({ error: 'Resposta da IA em formato inesperado.' }, 502);

  suggestions = suggestions
    .filter(s => s && typeof s.titulo === 'string' && s.titulo.trim())
    .slice(0, 5)
    .map(s => ({
      titulo: s.titulo.trim().slice(0, 60),
      descricao: typeof s.descricao === 'string' ? s.descricao.trim().slice(0, 300) : '',
      pontos: Number.isFinite(s.pontos) ? Math.max(0, Math.round(s.pontos)) : 10
    }));

  return jsonResponse({ suggestions });
}

function jsonResponse(obj, status) {
  return new Response(JSON.stringify(obj), {
    status: status || 200,
    headers: { 'content-type': 'application/json' }
  });
}
