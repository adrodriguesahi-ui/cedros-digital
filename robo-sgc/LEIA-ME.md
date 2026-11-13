# Robô SGC

Extensão do Microsoft Edge que trabalha dentro da aba em que você já entrou no SGC.
Ela não pede, não lê e não guarda a sua senha.

## Instalar (uma vez)

1. No Edge, abra `edge://extensions`.
2. Ligue **Modo de desenvolvedor** (canto inferior esquerdo).
3. Clique em **Carregar sem pacote** e escolha esta pasta `robo-sgc`.
4. Entre no SGC normalmente. Vai aparecer o botão 🤖 no canto inferior direito.

Depois de atualizar os arquivos desta pasta, volte em `edge://extensions` e clique em
**Recarregar** na extensão.

## Trazer os desbravadores do SGC para as Unidades

1. No SGC, abra a lista de membros do clube.
2. Toque em 🤖 e depois em **Trazer desbravadores desta tela**.
   - O robô acha sozinho as colunas Nome, Unidade e Matrícula/Código.
   - Se a lista tiver várias páginas, ele passa por todas.
   - Se a lista não tiver a coluna Unidade (por exemplo, quando é filtrada por unidade),
     ele pergunta de qual unidade são aqueles membros. Repita isso para cada unidade:
     o robô vai juntando tudo.
3. Toque em **Registrar no Cedros Digital**. O app abre numa aba nova.
4. Entre com sua conta de **administrador**. A tela **🤖 Importar do SGC** abre sozinha
   em Unidades (ou toque nela em Unidades) e mostra:
   - quem precisa ter a **matrícula oficial** marcada (com o número do SGC);
   - quem está no SGC mas **falta no app** (é cadastrado como Desbravador na unidade, com
     e-mail de fachada `matricula@sememail.local`, igual aos que vieram da planilha da Secretaria);
   - avisos que você confere à mão: unidade diferente, nome repetido no app, e quem está no
     app mas não apareceu no SGC.
5. Desmarque o que não quiser e toque em **Gravar selecionados**. Nada é gravado antes disso.

A lista lida fica guardada só dentro da extensão, até o app terminar de importar (aí é apagada).
Quem grava no banco é o próprio Cedros Digital, com o seu login: a extensão não tem chave do banco.
Para apagar a lista sem importar, use **Limpar o que já foi lido**.

Se o robô não achar a tabela, use **Mapear esta tela** na lista de membros e mande o arquivo
`mapa-sgc-....json` (ele leva só a estrutura da tela, sem nomes nem valores).

## Mapear telas (para as próximas tarefas)

Abra cada tela abaixo no SGC, toque em 🤖 e depois em **Mapear esta tela**.
O arquivo `mapa-sgc-....json` vai para a pasta Downloads.

- Lista de membros
- Ficha de um membro (classes e especialidades)
- Tela onde se marcam os requisitos de uma classe
- Tela onde se lança uma especialidade
- Tela de planejamento/agenda do clube

O mapa guarda só a estrutura da tela: nomes dos campos, botões, colunas e links.
Ele não copia senha, CPF, nomes nem valores digitados. Nas tabelas, o exemplo vai mascarado (por exemplo, "xxxxx xxxxx 99").
