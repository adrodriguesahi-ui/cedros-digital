// Robô SGC – ponte com o Cedros Digital.
// Roda na página do app e entrega a ele o que robo.js leu do SGC
// (guardado em chrome.storage.local). Quem grava no banco é o app, com o
// login de quem está usando; esta ponte não fala com o Supabase.
//
// Protocolo (window.postMessage, só na mesma origem):
//   app → ponte: { origem: 'cedros-app', tipo: 'pedir-membros-sgc' }
//   ponte → app: { origem: 'robo-sgc',   tipo: 'membros-sgc', dados }
//                { origem: 'robo-sgc',   tipo: 'especialidades-sgc', dados }
//   app → ponte: { origem: 'cedros-app', tipo: 'membros-sgc-importados' }         (apaga os membros)
//                { origem: 'cedros-app', tipo: 'especialidades-sgc-importadas' }  (apaga as especialidades)
(function(){
  const CHAVES = { roboSgcMembros: 'membros-sgc', roboSgcEspecialidades: 'especialidades-sgc' };

  function entregar(){
    chrome.storage.local.get(Object.keys(CHAVES), o => {
      Object.keys(CHAVES).forEach(chave => {
        const dados = o[chave];
        if(dados && dados.membros && dados.membros.length){
          window.postMessage({ origem: 'robo-sgc', tipo: CHAVES[chave], dados }, location.origin);
        }
      });
    });
  }

  window.addEventListener('message', e => {
    if(e.source !== window || e.origin !== location.origin) return;
    const m = e.data;
    if(!m || m.origem !== 'cedros-app') return;
    if(m.tipo === 'pedir-membros-sgc') entregar();
    else if(m.tipo === 'membros-sgc-importados') chrome.storage.local.remove('roboSgcMembros');
    else if(m.tipo === 'especialidades-sgc-importadas') chrome.storage.local.remove('roboSgcEspecialidades');
  });

  // Avisa que a extensão está instalada (o app mostra o botão de importar).
  window.postMessage({ origem: 'robo-sgc', tipo: 'presente' }, location.origin);
  entregar();
})();
