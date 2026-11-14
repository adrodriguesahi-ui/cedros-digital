// Robô SGC – roda dentro da aba em que você já entrou no SGC.
// Não lê nem guarda senha nem cookies.
//
// Duas tarefas:
//  1. "Mapear esta tela": baixa só a ESTRUTURA da tela (campos, botões,
//     colunas e links), com os exemplos mascarados — serve pra programar
//     as próximas tarefas.
//  2. "Trazer desbravadores": lê a lista de membros do SGC (nome, unidade,
//     matrícula, classe) e guarda no armazenamento local da extensão, só
//     até o Cedros Digital importar. Quem grava no banco é o próprio app,
//     com o login de quem está usando (ver ponte.js e Unidades → "Importar
//     do SGC" no index.html) — a extensão não tem chave do banco.
(function(){
  if(window.top !== window.self || document.getElementById('robo-sgc-btn')) return;

  const APP_URL = 'https://cedros-digital.adrodrigues-ahi.workers.dev/#importar-sgc';
  const CHAVE = 'roboSgcMembros';

  const btn = document.createElement('button');
  btn.id = 'robo-sgc-btn'; btn.type = 'button'; btn.title = 'Robô SGC'; btn.textContent = '🤖';
  const painel = document.createElement('div');
  painel.id = 'robo-sgc-painel';
  painel.innerHTML =
    '<h3>Robô SGC</h3>' +
    // Mensagens no topo: com muitos botões o painel rola, e embaixo ela sumia.
    '<div id="robo-sgc-status"></div>' +
    '<p class="robo-sgc-sub">Desbravadores por unidade</p>' +
    '<p>Abra a lista de membros do SGC e toque em "Trazer desbravadores". Se a lista vier separada por unidade, repita em cada uma: o robô vai juntando.</p>' +
    '<button type="button" data-acao="trazer">⬇️ Trazer desbravadores desta tela</button>' +
    '<button type="button" data-acao="enviar">📤 Registrar no Cedros Digital</button>' +
    '<button type="button" data-acao="limpar" class="robo-sgc-sec">🗑️ Limpar o que já foi lido</button>' +
    '<p class="robo-sgc-sub">Outras tarefas</p>' +
    '<button type="button" data-acao="mapear" class="robo-sgc-sec">📋 Mapear esta tela</button>' +
    '<button type="button" disabled>✅ Lançar requisitos de classe (em breve)</button>' +
    '<button type="button" disabled>🏅 Lançar especialidades (em breve)</button>' +
    '<button type="button" disabled>🗓️ Atualizar o planejamento (em breve)</button>';
  document.body.append(btn, painel);
  btn.addEventListener('click', () => { painel.classList.toggle('aberto'); if(painel.classList.contains('aberto')) mostrarResumo(); });
  const status = t => { document.getElementById('robo-sgc-status').textContent = t; };

  const limpo = t => String(t || '').replace(/\s+/g, ' ').trim().slice(0, 120);
  // Troca letras e números por x/9: mostra o formato do dado sem o dado.
  const mascarar = t => limpo(t).replace(/\d/g, '9').replace(/[A-Za-zÀ-ÿ]/g, 'x');
  const norm = t => limpo(t).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  const espera = ms => new Promise(r => setTimeout(r, ms));

  // ------------------------------------------------------------------
  // Armazenamento local da extensão (só até o app importar)
  // ------------------------------------------------------------------
  const ler = () => new Promise(r => chrome.storage.local.get(CHAVE, o => r(o[CHAVE] || null)));
  const gravar = v => new Promise(r => chrome.storage.local.set({ [CHAVE]: v }, r));
  const apagar = () => new Promise(r => chrome.storage.local.remove(CHAVE, r));

  async function mostrarResumo(){
    const d = await ler();
    if(!d || !d.membros.length){ status('Nada lido ainda.'); return; }
    const porUnidade = {};
    d.membros.forEach(m => { const u = m.unidade || '(sem unidade)'; porUnidade[u] = (porUnidade[u] || 0) + 1; });
    status(d.membros.length + ' lidos até agora: ' + Object.keys(porUnidade).sort().map(u => u + ' (' + porUnidade[u] + ')').join(', '));
  }

  // ------------------------------------------------------------------
  // Trazer desbravadores: acha a tabela de membros e as colunas pelo título
  // ------------------------------------------------------------------
  const COLUNAS = {
    nome:      [/^nome( completo)?$/, /\bnome\b/, /membro/, /desbravador/],
    unidade:   [/unidade/],
    matricula: [/matr[ií]cula/, /^c[oó]d(igo)?\b/, /^n[º°o]?\.?$/, /^id$/],
    classe:    [/classe/],
    cargo:     [/cargo|fun[cç][aã]o/],
    situacao:  [/situa[cç][aã]o|status|ativo/]
  };

  function colunasDe(tabela){
    let ths = Array.from(tabela.querySelectorAll('thead th'));
    if(!ths.length){ const tr = tabela.querySelector('tr'); ths = tr ? Array.from(tr.cells) : []; }
    const titulos = ths.map(th => norm(th.textContent));
    const idx = {};
    Object.keys(COLUNAS).forEach(campo => {
      for(const re of COLUNAS[campo]){
        const i = titulos.findIndex((t, j) => re.test(t) && !Object.values(idx).includes(j));
        if(i !== -1){ idx[campo] = i; break; }
      }
    });
    return { idx, titulos };
  }

  function acharTabela(){
    const tabelas = Array.from(document.querySelectorAll('table')).filter(t => !t.closest('#robo-sgc-painel'));
    let melhor = null;
    tabelas.forEach(t => {
      const c = colunasDe(t);
      if(c.idx.nome === undefined) return;
      const linhas = t.querySelectorAll('tbody tr').length;
      if(!melhor || linhas > melhor.linhas) melhor = { tabela: t, colunas: c, linhas };
    });
    return melhor;
  }

  function lerLinhas(tabela, idx){
    const linhas = Array.from(tabela.querySelectorAll('tbody tr')).filter(tr => tr.cells.length > 1);
    return linhas.map(tr => {
      const cel = i => (i === undefined || !tr.cells[i]) ? '' : limpo(tr.cells[i].textContent);
      const m = { nome: cel(idx.nome), unidade: cel(idx.unidade), matricula: cel(idx.matricula).replace(/[^\dA-Za-z-]/g, ''), classe: cel(idx.classe), cargo: cel(idx.cargo), situacao: cel(idx.situacao) };
      // Matrícula às vezes só existe no link da linha (ex.: .../membro/123).
      if(!m.matricula){
        const a = tr.querySelector('a[href*="membro"], a[href*="pessoa"], a[href*="Membro"]');
        const n = a && (a.getAttribute('href') || '').match(/(\d{3,})/);
        if(n) m.matricula = n[1];
      }
      return m;
    }).filter(m => m.nome && !/nenhum registro|no data|sem registros/i.test(m.nome));
  }

  // Botão "próxima página" das listas paginadas (DataTables e parecidos).
  function botaoProxima(){
    const cands = Array.from(document.querySelectorAll('a, button, li')).filter(el => !el.closest('#robo-sgc-painel'));
    return cands.find(el => {
      const t = norm(el.textContent);
      const cls = (el.className || '').toString();
      const ehProx = /\bnext\b/.test(cls) || t === 'proximo' || t === 'proxima' || t === 'next' || t === '»' || t === '›';
      const desab = /disabled/.test(cls) || el.hasAttribute('disabled') || (el.parentElement && /disabled/.test(el.parentElement.className || ''));
      return ehProx && !desab && el.offsetParent !== null;
    }) || null;
  }

  // Se a tabela tem o seletor "Mostrar N registros", escolhe o maior/"Todos".
  async function mostrarTodos(){
    const sel = Array.from(document.querySelectorAll('select')).find(s => /length|registros|por pagina/i.test((s.name || '') + ' ' + (s.closest('label') ? s.closest('label').textContent : '')));
    if(!sel) return;
    const opcoes = Array.from(sel.options);
    const maior = opcoes.find(o => Number(o.value) === -1) ||
      opcoes.reduce((a, o) => Number(o.value) > Number(a.value) ? o : a, opcoes[0]);
    if(maior && sel.value !== maior.value){
      sel.value = maior.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      await espera(1200);
    }
  }

  async function trazer(){
    status('Lendo a lista...');
    await mostrarTodos();
    let achado = acharTabela();
    if(!achado){ status('Não achei nesta tela uma tabela com a coluna "Nome". Abra a lista de membros do SGC e tente de novo (ou use "Mapear esta tela" e mande o arquivo).'); return; }
    const { idx } = achado.colunas;

    // Lista sem coluna Unidade: normalmente é a lista filtrada de uma unidade.
    let unidadeFixa = '';
    if(idx.unidade === undefined){
      const sel = Array.from(document.querySelectorAll('select')).find(s => /unidade/i.test((s.name || '') + ' ' + (s.id || '') + ' ' + (s.closest('label, .form-group, div') ? s.closest('label, .form-group, div').textContent.slice(0, 60) : '')));
      const sugestao = sel && sel.selectedIndex > 0 ? limpo(sel.options[sel.selectedIndex].textContent) : '';
      unidadeFixa = limpo(prompt('Esta lista não mostra a unidade de cada um. De qual unidade são estes membros? (deixe em branco se forem de várias)', sugestao) || '');
    }

    const vistos = new Set();
    const lidos = [];
    const juntar = arr => arr.forEach(m => {
      if(unidadeFixa && !m.unidade) m.unidade = unidadeFixa;
      const k = m.matricula || norm(m.nome);
      if(vistos.has(k)) return;
      vistos.add(k); lidos.push(m);
    });
    juntar(lerLinhas(achado.tabela, idx));

    // Percorre as páginas seguintes, se houver.
    for(let pag = 2; pag <= 60; pag++){
      const prox = botaoProxima();
      if(!prox) break;
      const antes = achado.tabela.querySelector('tbody') ? achado.tabela.querySelector('tbody').textContent : '';
      (prox.tagName === 'LI' ? (prox.querySelector('a, button') || prox) : prox).click();
      let mudou = false;
      for(let t = 0; t < 25; t++){
        await espera(200);
        const nova = acharTabela();
        if(nova && nova.tabela.querySelector('tbody') && nova.tabela.querySelector('tbody').textContent !== antes){ achado = nova; mudou = true; break; }
      }
      if(!mudou) break;
      status('Lendo a página ' + pag + '...');
      juntar(lerLinhas(achado.tabela, idx));
    }

    if(!lidos.length){ status('A tabela está vazia nesta tela.'); return; }

    const atual = (await ler()) || { membros: [] };
    const porChave = new Map(atual.membros.map(m => [m.matricula || norm(m.nome), m]));
    lidos.forEach(m => porChave.set(m.matricula || norm(m.nome), m));
    await gravar({ lidoEm: new Date().toISOString(), membros: Array.from(porChave.values()) });

    const semUnidade = lidos.filter(m => !m.unidade).length;
    await mostrarResumo();
    const st = document.getElementById('robo-sgc-status');
    st.textContent = lidos.length + ' lidos nesta tela' + (semUnidade ? ' (' + semUnidade + ' sem unidade)' : '') + '. ' + st.textContent +
      '. Quando terminar, toque em "Registrar no Cedros Digital".';
  }

  async function enviar(){
    const d = await ler();
    if(!d || !d.membros.length){ status('Nada lido ainda. Primeiro toque em "Trazer desbravadores".'); return; }
    window.open(APP_URL, '_blank');
    status('Abri o Cedros Digital. Entre com sua conta de administrador; a tela de importação vai mostrar as diferenças antes de gravar.');
  }

  // ------------------------------------------------------------------
  // Mapear esta tela (só estrutura, com exemplos mascarados)
  // ------------------------------------------------------------------
  function rotuloDe(el){
    if(el.id){
      const l = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
      if(l) return limpo(l.textContent);
    }
    const pai = el.closest('label, .form-group, td, div');
    const l = pai && pai.querySelector('label');
    return limpo((l && l.textContent) || el.getAttribute('placeholder') || el.getAttribute('aria-label') || '');
  }

  function seletor(el){
    if(el.id) return '#' + el.id;
    if(el.name) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';
    const classes = Array.from(el.classList).slice(0, 3).join('.');
    return el.tagName.toLowerCase() + (classes ? '.' + classes : '');
  }

  function campo(el){
    const tipo = (el.getAttribute('type') || el.tagName).toLowerCase();
    const c = { seletor: seletor(el), tag: el.tagName.toLowerCase(), tipo, nome: el.name || null, rotulo: rotuloDe(el) };
    // Senha e campos escondidos (tokens) nunca têm o valor copiado.
    if(el.tagName === 'SELECT'){
      c.opcoes = Array.from(el.options).slice(0, 60).map(o => ({ valor: o.value, texto: limpo(o.textContent) }));
    }
    if(tipo === 'checkbox' || tipo === 'radio') c.valor = el.value;
    return c;
  }

  function mapear(){
    const mapa = {
      geradoEm: new Date().toISOString(),
      endereco: location.origin + location.pathname,
      parametros: Array.from(new URLSearchParams(location.search).keys()),
      titulo: limpo(document.title),
      cabecalhos: Array.from(document.querySelectorAll('h1, h2, h3, h4, .box-title, .content-header')).filter(h => !h.closest('#robo-sgc-painel')).map(h => limpo(h.textContent)).filter(Boolean).slice(0, 30),
      menu: Array.from(document.querySelectorAll('aside a, nav a, .sidebar-menu a')).map(a => ({ texto: limpo(a.textContent), link: (a.getAttribute('href') || '').replace(/[?#].*$/, '') })).filter(a => a.texto).slice(0, 150),
      formularios: Array.from(document.forms).map(f => ({
        seletor: seletor(f), acao: (f.getAttribute('action') || '').replace(/[?#].*$/, ''), metodo: (f.getAttribute('method') || 'get').toLowerCase(),
        campos: Array.from(f.elements).filter(e => e.tagName !== 'FIELDSET' && e.tagName !== 'BUTTON').map(campo).slice(0, 200)
      })),
      camposForaDeFormulario: Array.from(document.querySelectorAll('input, select, textarea')).filter(e => !e.form && !e.closest('#robo-sgc-painel')).map(campo).slice(0, 200),
      botoes: Array.from(document.querySelectorAll('button, input[type=submit], input[type=button], a.btn')).filter(b => !b.closest('#robo-sgc-painel') && b.id !== 'robo-sgc-btn')
        .map(b => ({ seletor: seletor(b), texto: limpo(b.textContent || b.value), onclick: b.getAttribute('onclick') ? limpo(b.getAttribute('onclick')).replace(/\d+/g, '9') : null })).slice(0, 120),
      tabelas: Array.from(document.querySelectorAll('table')).map(t => {
        const linhas = t.querySelectorAll('tbody tr');
        const exemplo = linhas[0] ? Array.from(linhas[0].cells).map(td => ({
          formato: mascarar(td.textContent),
          temLink: !!td.querySelector('a'), temCheckbox: !!td.querySelector('input[type=checkbox]'), temBotao: !!td.querySelector('button, a.btn'),
          link: td.querySelector('a') ? (td.querySelector('a').getAttribute('href') || '').replace(/[?#].*$/, '').replace(/\d+/g, '9') : null
        })) : [];
        return { seletor: seletor(t), colunas: Array.from(t.querySelectorAll('thead th, tr:first-child th')).map(th => limpo(th.textContent)), linhas: linhas.length, exemploMascarado: exemplo };
      }),
      scriptsDaPagina: Array.from(document.scripts).map(s => s.src).filter(Boolean).map(s => s.replace(/[?#].*$/, ''))
    };
    const nome = 'mapa-sgc-' + (location.pathname.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '') || 'inicio') + '.json';
    const blob = new Blob([JSON.stringify(mapa, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = nome;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    status('Mapa salvo em Downloads: ' + nome);
  }

  painel.addEventListener('click', async e => {
    const b = e.target.closest('button[data-acao]');
    if(!b) return;
    const acao = b.dataset.acao;
    try{
      if(acao === 'mapear') mapear();
      else if(acao === 'trazer') await trazer();
      else if(acao === 'enviar') await enviar();
      else if(acao === 'limpar'){ if(confirm('Apagar a lista lida do SGC (só da extensão; nada muda no SGC nem no app)?')){ await apagar(); status('Lista apagada.'); } }
    } catch(err){
      status('Deu erro: ' + (err && err.message ? err.message : err));
    }
  });
})();
