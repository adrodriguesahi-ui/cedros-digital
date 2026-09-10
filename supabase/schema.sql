-- Cedros Digital — schema do painel de Administração (Supabase / Postgres)
-- Rode este script inteiro uma vez no SQL Editor do seu projeto Supabase.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- papeis: funções (Administrador, Diretoria, ...) e suas permissões padrão
-- ---------------------------------------------------------------------
create table if not exists papeis (
  id uuid primary key default gen_random_uuid(),
  nome text unique not null,
  cor text not null,
  permissoes_padrao jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

insert into papeis (nome, cor, permissoes_padrao) values
  ('Administrador', 'red', '{
    "planning":true,"classes":true,"units":true,"devotional":true,
    "treasury":true,"secretary":true,"storage":true,"manuals":true,
    "birthdays":true,"specialties":true,"admin":true
  }'::jsonb),
  ('Diretoria Executiva', 'purple', '{
    "planning":true,"classes":true,"units":true,"devotional":true,
    "treasury":true,"secretary":true,"storage":true,"manuals":true,
    "birthdays":true,"specialties":true,"admin":false
  }'::jsonb),
  ('Diretoria', 'gold', '{
    "planning":true,"classes":true,"units":true,"devotional":true,
    "treasury":false,"secretary":false,"storage":true,"manuals":true,
    "birthdays":true,"specialties":true,"admin":false
  }'::jsonb),
  ('Conselheiros', 'green', '{
    "planning":true,"classes":true,"units":true,"devotional":true,
    "treasury":false,"secretary":false,"storage":false,"manuals":true,
    "birthdays":true,"specialties":true,"admin":false
  }'::jsonb),
  ('Instrutores', 'blue', '{
    "planning":true,"classes":true,"units":false,"devotional":true,
    "treasury":false,"secretary":false,"storage":false,"manuals":true,
    "birthdays":false,"specialties":true,"admin":false
  }'::jsonb),
  ('Coordenador de Classes', 'gray', '{
    "planning":true,"classes":true,"units":false,"devotional":false,
    "treasury":false,"secretary":false,"storage":false,"manuals":true,
    "birthdays":false,"specialties":true,"admin":false
  }'::jsonb),
  -- Membro do clube (a criança/adolescente em si) — diferente dos demais
  -- papéis acima, que são todos de liderança. Sem acesso a telas
  -- administrativas (tesouraria, secretaria, almoxarifado, unidades,
  -- admin); só o que é do próprio desbravador: agenda, progresso nas
  -- classes/especialidades, devocional e manuais.
  ('Desbravador', 'orange', '{
    "planning":true,"classes":true,"units":false,"devotional":true,
    "treasury":false,"secretary":false,"storage":false,"manuals":true,
    "birthdays":false,"specialties":true,"admin":false
  }'::jsonb)
on conflict (nome) do nothing;

-- ---------------------------------------------------------------------
-- usuarios: cadastro de usuários do painel de Administração
-- ---------------------------------------------------------------------
create table if not exists usuarios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  email text unique not null,
  unidade text not null,
  papel text not null references papeis(nome) on update cascade,
  acesso jsonb,
  aprovado boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Colunas adicionadas depois da criação inicial da tabela (rodar de novo é seguro)
alter table usuarios add column if not exists aprovado boolean not null default true;
-- Cargo específico da pessoa (ex.: "Diretor Associado"), diferente do papel/permissão.
-- Opcional: só quem tem um cargo definido mostra isso no painel em vez de presenças.
alter table usuarios add column if not exists cargo text;
-- Data de nascimento: alimenta a lista de Aniversariantes (mês atual) e o
-- destaque de "aniversário hoje" no dashboard. Coletada no cadastro, mas
-- editável em Administração → Usuários pra quem já tinha conta sem isso.
alter table usuarios add column if not exists data_nascimento date;
-- Permissão pra tela de Pontuação de Unidades — independente do cargo/papel,
-- porque uma pessoa pode acumular várias funções no clube (ex.: já é
-- Conselheira de uma unidade e também Coordenadora de Unidades) e o campo
-- cargo só guarda um valor por pessoa.
alter table usuarios add column if not exists pode_pontuar_unidades boolean not null default false;
-- Ativar/Desativar Membro (Administração → editar usuário): desliga o acesso
-- e some da contagem de membros das Unidades sem apagar o cadastro/histórico
-- da pessoa — mesma ideia do status "inativa" já usado em unidades.status.
alter table usuarios add column if not exists ativo boolean not null default true;
-- Cartão/classe regular da pessoa (Amigo, Companheiro, ... ver CLASS list em
-- Classes Regulares). Ao definir aqui em Administração, o app cria/atualiza
-- automaticamente a linha correspondente em `desbravadores` (ligada por
-- usuario_id) — assim a pessoa já aparece pronta em Classes Regulares pra
-- marcar requisitos, sem precisar cadastrar de novo lá.
alter table usuarios add column if not exists classe text;
-- Classe/cartão que este usuário, quando papel = "Coordenador de Classes",
-- está autorizado a gerenciar (cadastrar/renomear/excluir desbravadores) em
-- Classes Regulares — diferente da coluna "classe" acima, que é o cartão do
-- próprio usuário como desbravador. Nulo = nenhuma classe atribuída ainda
-- (o coordenador não gerencia nenhuma, até o Administrador definir aqui).
alter table usuarios add column if not exists classe_coordenada text;

insert into usuarios (nome, email, unidade, papel) values
  ('Adrodrigues Santos', 'adrodrigues@cedrosdigital.org', 'Ype', 'Administrador'),
  ('Camila Ferreira', 'camila.ferreira@cedrosdigital.org', 'Cedros', 'Diretoria'),
  ('Lucas Andrade', 'lucas.andrade@cedrosdigital.org', 'Pinheiro', 'Instrutores')
on conflict (email) do nothing;

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_usuarios_updated_at on usuarios;
create trigger trg_usuarios_updated_at
  before update on usuarios
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------
-- permissoes_padrao_papel: devolve as permissões padrão de um papel
-- usada pelo botão "Restaurar padrão da função" no painel de Administração
-- ---------------------------------------------------------------------
create or replace function permissoes_padrao_papel(papel_nome text)
returns jsonb language sql stable as $$
  select coalesce(
    (select permissoes_padrao from papeis where nome = papel_nome),
    '{}'::jsonb
  );
$$;

-- ---------------------------------------------------------------------
-- RLS — sem sistema de login real ainda (ver disclaimer no painel),
-- então liberamos leitura/escrita para a chave anon (pública, protegida
-- só por não ser divulgada fora do app). Revisar quando houver auth real.
-- ---------------------------------------------------------------------
alter table papeis enable row level security;
alter table usuarios enable row level security;

drop policy if exists "papeis: leitura publica" on papeis;
create policy "papeis: leitura publica" on papeis
  for select using (true);

drop policy if exists "usuarios: acesso publico" on usuarios;
create policy "usuarios: acesso publico" on usuarios
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- Classes Regulares: desbravadores cadastrados por classe e o progresso
-- de cada um nos requisitos (data-title dos cards, ex.: "GE-1. Idade mínima").
-- O catálogo de requisitos em si vive no HTML (index.html), não aqui —
-- esta tabela só guarda quem está em cada classe e o status de cada item.
-- ---------------------------------------------------------------------
create table if not exists desbravadores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  classe text not null,
  created_at timestamptz not null default now()
);

-- Liga um desbravador ao usuário correspondente em Administração (opcional —
-- continua dando pra cadastrar alguém direto por Classes Regulares, sem
-- conta no app, como sempre foi). Preenchido quando o cartão é definido em
-- Administração → editar usuário (ver usuarios.classe abaixo); índice
-- parcial porque a maioria das linhas antigas não tem esse vínculo.
alter table desbravadores add column if not exists usuario_id uuid references usuarios(id) on delete set null;
create unique index if not exists desbravadores_usuario_id_key on desbravadores(usuario_id) where usuario_id is not null;

create table if not exists progresso_requisitos (
  id uuid primary key default gen_random_uuid(),
  desbravador_id uuid not null references desbravadores(id) on delete cascade,
  requisito_titulo text not null,
  status text not null default 'todo',
  updated_at timestamptz not null default now(),
  unique (desbravador_id, requisito_titulo)
);

-- Comprovação (uma ou mais fotos/arquivos, em base64) de que o desbravador
-- cumpriu um requisito, com QR Code de acesso público (ver isComprovanteRoute
-- no index.html) pra quem verifica a ficha (ex.: pastor, diretoria da
-- Associação/Missão) conferir sem precisar login no app. Tabela própria (em
-- vez de colunas em progresso_requisitos) porque um requisito pode ter
-- vários comprovantes anexados.
create table if not exists comprovante_arquivos (
  id uuid primary key default gen_random_uuid(),
  desbravador_id uuid not null references desbravadores(id) on delete cascade,
  requisito_titulo text not null,
  arquivo_data text not null,
  arquivo_nome text,
  created_at timestamptz not null default now()
);

-- Migração pra quem já tinha rodado a versão anterior (colunas comprovante_foto/
-- comprovante_nome direto em progresso_requisitos): copia o que já tinha sido
-- anexado pra tabela nova e remove as colunas antigas. Seguro rodar de novo —
-- na segunda vez as colunas já não existem mais e o bloco não faz nada.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'progresso_requisitos' and column_name = 'comprovante_foto'
  ) then
    insert into comprovante_arquivos (desbravador_id, requisito_titulo, arquivo_data, arquivo_nome)
    select desbravador_id, requisito_titulo, comprovante_foto, comprovante_nome
    from progresso_requisitos
    where comprovante_foto is not null;

    alter table progresso_requisitos drop column comprovante_foto;
    alter table progresso_requisitos drop column comprovante_nome;
  end if;
end $$;

create or replace function set_updated_at_progresso()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_progresso_requisitos_updated_at on progresso_requisitos;
create trigger trg_progresso_requisitos_updated_at
  before update on progresso_requisitos
  for each row execute function set_updated_at_progresso();

alter table desbravadores enable row level security;
alter table progresso_requisitos enable row level security;
alter table comprovante_arquivos enable row level security;

drop policy if exists "desbravadores: acesso publico" on desbravadores;
create policy "desbravadores: acesso publico" on desbravadores
  for all using (true) with check (true);

drop policy if exists "progresso_requisitos: acesso publico" on progresso_requisitos;
create policy "progresso_requisitos: acesso publico" on progresso_requisitos
  for all using (true) with check (true);

drop policy if exists "comprovante_arquivos: acesso publico" on comprovante_arquivos;
create policy "comprovante_arquivos: acesso publico" on comprovante_arquivos
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- Planejamento de Classes: o instrutor prepara a aula em si (separado do
-- progresso por desbravador acima, que só marca quem já cumpriu o quê).
-- requisito_titulo é texto livre (sugerido por um datalist no app, tirado
-- dos cards de requisito já existentes em Classes Regulares) — não há FK
-- porque o catálogo de requisitos vive só no HTML, não numa tabela.
-- ---------------------------------------------------------------------
create table if not exists planejamentos_aula (
  id uuid primary key default gen_random_uuid(),
  classe text not null,
  requisito_titulo text,
  data date,
  horario text,
  instrutor_responsavel text,
  quantidade_desbravadores int,
  local text,
  tema text,
  objetivo text,
  duracao text,
  materiais_necessarios text,
  texto_biblico text,
  introducao text,
  desenvolvimento text,
  atividade text,
  aplicacao_espiritual text,
  avaliacao_participou boolean not null default false,
  avaliacao_compreendeu boolean not null default false,
  avaliacao_cumpriu_requisito boolean not null default false,
  observacoes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function set_updated_at_planejamentos_aula()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_planejamentos_aula_updated_at on planejamentos_aula;
create trigger trg_planejamentos_aula_updated_at
  before update on planejamentos_aula
  for each row execute function set_updated_at_planejamentos_aula();

alter table planejamentos_aula enable row level security;

drop policy if exists "planejamentos_aula: acesso publico" on planejamentos_aula;
create policy "planejamentos_aula: acesso publico" on planejamentos_aula
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- Unidades: cadastro central (cor/status) + funções, atividades,
-- avaliações mensais e conquistas de cada unidade. `usuarios.unidade`
-- (texto livre) é o elo com os membros — não há FK ali para não quebrar
-- cadastros já existentes.
-- ---------------------------------------------------------------------
create table if not exists unidades (
  nome text primary key,
  cor text not null default 'gray',
  status text not null default 'ativa'
);

insert into unidades (nome, cor, status) values
  ('Ype', 'green', 'ativa'),
  ('Ype Roxo', 'purple', 'ativa'),
  ('Pinheiro', 'blue', 'ativa'),
  ('Cedros', 'gold', 'ativa'),
  ('Cedros Rosa', 'red', 'ativa'),
  ('Flanboyan', 'orange', 'ativa'),
  ('Jacarandá', 'gray', 'ativa')
on conflict (nome) do nothing;

create table if not exists unit_funcoes (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  funcao text not null,
  nome text not null default '',
  unique (unidade, funcao)
);

insert into unit_funcoes (unidade, funcao)
  select u.nome, f.funcao
  from unidades u
  cross join (values
    ('Capitão(a)'), ('Vice-capitão(a)'), ('Secretário(a)'),
    ('Tesoureiro(a)'), ('Instrutor(a)'), ('Conselheiro(a)')
  ) as f(funcao)
on conflict (unidade, funcao) do nothing;

create table if not exists unit_atividades (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  titulo text not null,
  descricao text,
  data date not null,
  hora text,
  created_at timestamptz not null default now()
);

create table if not exists unit_avaliacoes (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  mes_ref text not null,
  area text not null,
  percentual int not null default 0,
  unique (unidade, mes_ref, area)
);

create table if not exists unit_conquistas (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  titulo text not null,
  descricao text,
  conquistada boolean not null default false,
  data_conquista text,
  progresso_atual numeric not null default 0,
  progresso_meta numeric not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists unit_mes_resumo (
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  mes_ref text not null,
  especialidades int not null default 0,
  primary key (unidade, mes_ref)
);

-- Lançamentos de pontos da tela "Pontuação de Unidades" (Início → Unidades →
-- 🏆 Pontuação, restrito a quem tem usuarios.pode_pontuar_unidades). Cada linha
-- é um ajuste (positivo ou negativo) com motivo obrigatório; o total de uma
-- unidade é a soma de todos os lançamentos dela — alimenta tanto essa tela
-- quanto o "Rank das Unidades" do dashboard.
create table if not exists unidade_pontos (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  pontos int not null,
  motivo text not null,
  criado_por text,
  created_at timestamptz not null default now()
);

-- Cantinho da Unidade (Início → Unidades → aba "Cantinho"): descrição,
-- responsável pela decoração, pontuação por categoria (0-10 cada, até 60) e
-- fotos do cantinho. Era a última parte da tela de Unidades ainda guardada
-- só na memória do app — sumia ao recarregar a página; agora persiste aqui,
-- mesmo padrão de unit_avaliacoes (pontos por categoria) e especialidade_fotos
-- (fotos em base64, uma linha por foto).
create table if not exists unit_cantinho (
  unidade text primary key references unidades(nome) on update cascade on delete cascade,
  descricao text not null default '',
  responsavel text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists unit_cantinho_pontos (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  categoria text not null,
  pontos int not null default 0,
  unique (unidade, categoria)
);

create table if not exists unit_cantinho_fotos (
  id uuid primary key default gen_random_uuid(),
  unidade text not null references unidades(nome) on update cascade on delete cascade,
  foto text not null,
  created_at timestamptz not null default now()
);

-- Verificação assistida de matrícula oficial (Início → Unidades → Membros):
-- o app NÃO se conecta ao clubes.adventistas.org (não é uma API pública, é só
-- o portal de login manual "Unit Control" com código do clube + senha por
-- unidade — credenciais que não devem ficar guardadas aqui). Em vez disso,
-- o líder confere manualmente lá e marca aqui, por desbravador, se já está
-- matriculado no sistema oficial — vira uma lista de pendências por nome.
create table if not exists usuario_matricula_oficial (
  usuario_id uuid primary key references usuarios(id) on delete cascade,
  matriculado boolean not null default false,
  verificado_em timestamptz,
  verificado_por text,
  numero_matricula text
);

-- Coluna adicionada depois da criação inicial da tabela (rodar de novo é seguro)
alter table usuario_matricula_oficial add column if not exists numero_matricula text;

alter table unidades enable row level security;
alter table unit_funcoes enable row level security;
alter table unit_atividades enable row level security;
alter table unit_avaliacoes enable row level security;
alter table unit_conquistas enable row level security;
alter table unit_mes_resumo enable row level security;
alter table unidade_pontos enable row level security;
alter table unit_cantinho enable row level security;
alter table unit_cantinho_pontos enable row level security;
alter table unit_cantinho_fotos enable row level security;
alter table usuario_matricula_oficial enable row level security;

drop policy if exists "unidades: acesso publico" on unidades;
create policy "unidades: acesso publico" on unidades for all using (true) with check (true);

drop policy if exists "unit_funcoes: acesso publico" on unit_funcoes;
create policy "unit_funcoes: acesso publico" on unit_funcoes for all using (true) with check (true);

drop policy if exists "unit_atividades: acesso publico" on unit_atividades;
create policy "unit_atividades: acesso publico" on unit_atividades for all using (true) with check (true);

drop policy if exists "unit_avaliacoes: acesso publico" on unit_avaliacoes;
create policy "unit_avaliacoes: acesso publico" on unit_avaliacoes for all using (true) with check (true);

drop policy if exists "unit_conquistas: acesso publico" on unit_conquistas;
create policy "unit_conquistas: acesso publico" on unit_conquistas for all using (true) with check (true);

drop policy if exists "unit_mes_resumo: acesso publico" on unit_mes_resumo;
create policy "unit_mes_resumo: acesso publico" on unit_mes_resumo for all using (true) with check (true);

drop policy if exists "unidade_pontos: acesso publico" on unidade_pontos;
create policy "unidade_pontos: acesso publico" on unidade_pontos for all using (true) with check (true);

drop policy if exists "unit_cantinho: acesso publico" on unit_cantinho;
create policy "unit_cantinho: acesso publico" on unit_cantinho for all using (true) with check (true);

drop policy if exists "unit_cantinho_pontos: acesso publico" on unit_cantinho_pontos;
create policy "unit_cantinho_pontos: acesso publico" on unit_cantinho_pontos for all using (true) with check (true);

drop policy if exists "unit_cantinho_fotos: acesso publico" on unit_cantinho_fotos;
create policy "unit_cantinho_fotos: acesso publico" on unit_cantinho_fotos for all using (true) with check (true);

drop policy if exists "usuario_matricula_oficial: acesso publico" on usuario_matricula_oficial;
create policy "usuario_matricula_oficial: acesso publico" on usuario_matricula_oficial for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- eventos_agenda: eventos da Agenda Anual (Planejamento Anual). Antes
-- viviam só como HTML estático em index.html/login.html — qualquer
-- evento cadastrado ou editado pelo app se perdia ao recarregar a
-- página, porque nada era salvo aqui. A carga abaixo recria os 69
-- eventos da agenda oficial "AGENDA CEDROS DO LÍBANO 2026" que já
-- estavam fixos no HTML (mesmos dados do commit "Import the real 2026
-- club agenda...").
-- ---------------------------------------------------------------------
create table if not exists eventos_agenda (
  id uuid primary key default gen_random_uuid(),
  dia int not null,
  mes_indice int not null check (mes_indice between 1 and 12),
  titulo text not null,
  horario text not null default '09:00',
  horario_fim text,
  local text not null default 'Sede do Clube',
  responsavel text,
  tag text not null default 'gray',
  tag_label text not null default 'Outro',
  descricao text,
  observacao text,
  mostrar_galeria boolean not null default true,
  mostrar_galeria_a_partir_de date,
  foto text,
  lembrete_on boolean not null default false,
  lembrete_data date,
  lembrete_mensagem text,
  lembrete_confirmado boolean not null default false,
  lembrete_confirmado_vezes int not null default 0,
  lembrete_ultima_confirmacao date,
  lembrete_confirmado_por text,
  lembrete_repetir_on boolean not null default false,
  lembrete_repetir_dias int,
  lembrete_repetir_vezes int,
  oficiais_dia_ids uuid[] not null default '{}'::uuid[],
  oficiais_dia_nomes text[] not null default '{}'::text[],
  escala_oculta boolean not null default false,
  aviso_membros text,
  programacao_dia jsonb not null default '[]'::jsonb,
  checklist_atividades jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Coluna adicionada depois da criação inicial da tabela (rodar de novo é seguro) —
-- foto do evento (base64), mesmo padrão de Classes Regulares/Cantinho da Unidade.
alter table eventos_agenda add column if not exists foto text;

-- Coluna adicionada depois: controla se o evento entra no carrossel de destaque
-- do Início, além de aparecer na Agenda Anual (default true = comportamento
-- anterior, todo evento aparecia lá).
alter table eventos_agenda add column if not exists mostrar_galeria boolean not null default true;

-- Coluna adicionada depois: data a partir da qual o evento passa a concorrer a
-- uma vaga no carrossel (em branco = sem restrição, só a data do evento em si
-- já passar tira do carrossel, como sempre foi).
alter table eventos_agenda add column if not exists mostrar_galeria_a_partir_de date;

-- Colunas adicionadas depois: "Programação do Dia" de uma reunião — quem são os
-- oficiais de dia, a lista de horário+atividade, um aviso pros membros (pode
-- incluir um versículo) e um checklist de tarefas que qualquer pessoa pode marcar
-- como feito ao visualizar o evento (não exige permissão de edição).
-- oficiais_dia (texto livre) foi a primeira versão do campo — mantida aqui só
-- por compatibilidade com bancos que já rodaram essa migração antes; o app não
-- lê nem escreve mais nela, usa oficiais_dia_ids/oficiais_dia_nomes agora (liga
-- o oficial a um membro cadastrado de verdade, pra dar pra saber quem é a pessoa
-- logada e mostrar o card "Você é Oficial de Dia" só pra ela).
alter table eventos_agenda add column if not exists oficiais_dia text;
alter table eventos_agenda add column if not exists oficiais_dia_ids uuid[] not null default '{}'::uuid[];
alter table eventos_agenda add column if not exists oficiais_dia_nomes text[] not null default '{}'::text[];
alter table eventos_agenda add column if not exists aviso_membros text;
alter table eventos_agenda add column if not exists programacao_dia jsonb not null default '[]'::jsonb;
alter table eventos_agenda add column if not exists checklist_atividades jsonb not null default '[]'::jsonb;

-- Coluna adicionada depois: permite "remover" uma Reunião Regular da lista da
-- Escala de Oficiais (Secretaria) sem apagar o evento em si da Agenda Anual —
-- só deixa de aparecer nessa lista específica.
alter table eventos_agenda add column if not exists escala_oculta boolean not null default false;
-- Quem confirmou o lembrete pela última vez (clique no ✓ do sino/banner) —
-- registrado junto com lembrete_confirmado_vezes/lembrete_ultima_confirmacao,
-- que até então só existiam na tela (nunca eram salvos no Supabase): o
-- lembrete "esquecia" tudo a cada recarregamento e ignorava o limite de
-- repetições configurado (lembrete_repetir_vezes).
alter table eventos_agenda add column if not exists lembrete_confirmado_por text;

-- Colunas adicionadas depois: confirmação de que a Programação do Dia de uma
-- Reunião Regular foi realmente concluída (feita por qualquer Oficial de Dia
-- responsável, Diretor ou Dir. Associado(a), no banner "Reunião terminou" do
-- Início) — assim que confirmada, o banner some da tela inicial pra todo
-- mundo, não só de quem confirmou.
alter table eventos_agenda add column if not exists reuniao_concluida boolean not null default false;
alter table eventos_agenda add column if not exists reuniao_concluida_por text;
alter table eventos_agenda add column if not exists reuniao_concluida_em timestamptz;

-- Colunas adicionadas depois: aprovação da Programação do Dia preenchida pelo
-- Oficial de Dia. Só depois de aprovada por Diretor/Dir. Associado(a) ela conta
-- como publicada (chip "Reunião Regular" no Início, que só aparece a partir de
-- 2 dias antes do evento) — evita que uma programação incompleta ou errada
-- apareça pra Diretoria/membros antes de alguém responsável revisar. Volta a
-- false toda vez que o Oficial de Dia salva uma nova versão.
alter table eventos_agenda add column if not exists programacao_aprovada boolean not null default false;
alter table eventos_agenda add column if not exists programacao_aprovada_por text;
alter table eventos_agenda add column if not exists programacao_aprovada_em timestamptz;

create or replace function set_updated_at_eventos_agenda()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_eventos_agenda_updated_at on eventos_agenda;
create trigger trg_eventos_agenda_updated_at
  before update on eventos_agenda
  for each row execute function set_updated_at_eventos_agenda();

alter table eventos_agenda enable row level security;

drop policy if exists "eventos_agenda: acesso publico" on eventos_agenda;
create policy "eventos_agenda: acesso publico" on eventos_agenda
  for all using (true) with check (true);

-- Só roda se a tabela ainda estiver vazia, pra não duplicar em execuções futuras
-- deste arquivo (ex.: depois que a diretoria já tiver editado/adicionado eventos).
insert into eventos_agenda (dia, mes_indice, titulo, horario, local, tag, tag_label)
select * from (values
  (13, 1, 'Reunião Administrativa', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (17, 1, 'Reunião Diretoria', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (8, 2, 'Limpeza da Sala do Clube', '09:00', 'Só diretoria.', 'gray', 'Evento'),
  (14, 2, 'Feriado - Carnaval', '09:00', '14 a 17 de fevereiro (sábado a terça).', 'gray', 'Feriado'),
  (22, 2, 'Início do Clube + Abertura', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (1, 3, 'Reunião Regular + CTAD', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (8, 3, 'Reunião Regular + Reunião de Diretoria', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (14, 3, 'Encontro de Inclusão', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (15, 3, 'Reunião Regular + Início da Classe Bíblica', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (22, 3, 'Reunião Regular + Curso de Brigadista', '09:00', 'Sede do Clube', 'blue', 'Curso'),
  (28, 3, 'Impacto Esperança', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (29, 3, 'Semana Santa + Reunião Regular + Desbravador por 1 Dia', '09:00', 'Início da Semana Santa.', 'purple', 'Cerimônia'),
  (30, 3, 'Semana Santa (Recepção Companheiro)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (31, 3, 'Semana Santa (Recepção Guia)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (1, 4, 'Semana Santa (Recepção Excursionista)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (2, 4, 'Semana Santa (Recepção Pesquisador)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (3, 4, 'Semana Santa (Recepção Amigo)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (4, 4, 'Semana Santa (Recepção Pioneiro)', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (5, 4, 'Folga - Páscoa', '09:00', 'Sede do Clube', 'gray', 'Folga'),
  (11, 4, 'Evento - Pastel', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (12, 4, 'Reunião Regular + Curso de Capitães e Conselheiros', '09:00', 'Sede do Clube', 'blue', 'Curso'),
  (19, 4, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (26, 4, 'Reunião Regular + Prova de Líder', '09:00', 'Sede do Clube', 'red', 'Prova'),
  (2, 5, 'Olimpori + 24H', '09:00', '2 a 3 de maio (sábado e domingo).', 'gold', 'Acampamento'),
  (10, 5, 'Folga - Dia das Mães', '09:00', 'Sede do Clube', 'gray', 'Folga'),
  (17, 5, 'Reunião Regular + Festa Dia das Mães + Evento Feijoada', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (24, 5, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (31, 5, 'Reunião Regular + Preparativos para o Acampamento + Concursos BB e Música', '09:00', 'Sede do Clube', 'red', 'Concurso'),
  (4, 6, 'Acampamento de Instrução + Cedroflash', '09:00', '4 a 7 de junho (quinta a domingo).', 'gold', 'Acampamento'),
  (13, 6, 'Evento - Festa do Milho', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (14, 6, 'Reunião Regular + Prova de Líder', '09:00', 'Sede do Clube', 'red', 'Prova'),
  (21, 6, 'Fase Regional Concurso de Ordem Unida e Fanfarra', '09:00', 'Sede do Clube', 'red', 'Concurso'),
  (28, 6, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (1, 7, 'Calebe + Escola Cristã de Férias', '09:00', 'Durante todo o mês de julho.', 'gold', 'Acampamento'),
  (9, 7, 'Maranata SP', '09:00', '9 a 12 de julho (quinta a domingo).', 'gold', 'Acampamento'),
  (19, 7, 'Paulista Laranja', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (26, 7, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (31, 7, 'Mega Líder', '09:00', '31/07 a 02/08 (sexta a domingo).', 'gold', 'Acampamento'),
  (2, 8, 'Reunião Regular + Ensaio Dia Mundial', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (8, 8, 'Evento - Pizza', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (9, 8, 'Folga - Dia dos Pais', '09:00', 'Sede do Clube', 'gray', 'Folga'),
  (15, 8, 'Adolescer', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (16, 8, 'Reunião Regular + Festa do Dia dos Pais + Ensaio Dia Mundial', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (22, 8, 'Quebrando o Silêncio + Passeata na Paulista', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (23, 8, 'Reunião Regular + Ensaio Dia Mundial', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (30, 8, 'Reunião Regular + Ensaio Dia Mundial + CTAD', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (6, 9, 'Reunião Regular + Ensaio Dia Mundial + Prova de Líder', '09:00', 'Sede do Clube', 'red', 'Prova'),
  (7, 9, 'Desfile Cívico', '09:00', '7 de setembro (segunda-feira).', 'purple', 'Cerimônia'),
  (13, 9, 'Reunião Regular + Ensaio Dia Mundial', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (13, 9, 'Semana do Lenço', '09:00', '13 a 18 de setembro (domingo a sexta).', 'purple', 'Cerimônia'),
  (19, 9, 'Dia Mundial DBV', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (20, 9, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (27, 9, 'Concursos AP', '09:00', 'Sede do Clube', 'red', 'Concurso'),
  (3, 10, 'Evento - Açaí', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (4, 10, 'Reunião Regular', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (11, 10, 'Uniflash', '09:00', 'Sede do Clube', 'gold', 'Acampamento'),
  (18, 10, 'Reunião Regular - Finalização e Entrega do Cartão', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (25, 10, 'Reunião Regular + Prova de Líder', '09:00', 'Sede do Clube', 'red', 'Prova'),
  (1, 11, 'Folga', '09:00', 'Sede do Clube', 'gray', 'Folga'),
  (7, 11, 'Evento - Esportes', '09:00', 'Sede do Clube', 'gray', 'Evento'),
  (8, 11, 'Reunião Regular + Entrega de Apostilas', '09:00', 'Sede do Clube', 'green', 'Reunião'),
  (14, 11, 'Investidura', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (15, 11, 'Folga', '09:00', 'Sede do Clube', 'gray', 'Folga'),
  (21, 11, 'CEDRORI (Acampamento de Recreação + Oscar)', '09:00', '21 e 22 de novembro (sábado e domingo).', 'gold', 'Acampamento'),
  (29, 11, 'Preparativos para o Campori DSA', '09:00', 'Sede do Clube', 'gold', 'Acampamento'),
  (5, 12, 'Culto de Ações de Graças', '09:00', 'Sede do Clube', 'purple', 'Cerimônia'),
  (6, 12, 'Preparativos para o Campori DSA', '09:00', 'Sede do Clube', 'gold', 'Acampamento'),
  (13, 12, 'Preparativos para o Campori DSA', '09:00', 'Sede do Clube', 'gold', 'Acampamento'),
  (20, 12, 'Férias', '09:00', '20/12 a 03/01 (previsão).', 'gray', 'Folga')
) as seed(dia, mes_indice, titulo, horario, local, tag, tag_label)
where not exists (select 1 from eventos_agenda);

-- ---------------------------------------------------------------------
-- event_confirmations: "Confirmar presença" no evento em destaque do
-- dashboard. Referencia eventos_agenda(id) diretamente — editar o
-- título de um evento não derruba as confirmações dele. user_id é o
-- auth.uid() real (Supabase Auth), por isso as políticas usam
-- auth.uid() em vez do padrão "acesso público" do resto deste arquivo:
-- leitura é pública (pra mostrar quantos confirmaram), mas cada um só
-- grava/apaga a própria confirmação.
--
-- Recriada aqui (drop + create) porque a versão anterior desta tabela
-- guardava o evento por uma chave de texto (mês-dia-título em slug) em
-- vez de referenciar eventos_agenda — na época a tabela de eventos
-- ainda não existia. Seguro rodar de novo: a tabela antiga acabou de
-- ser criada e ainda não tem confirmações reais.
-- ---------------------------------------------------------------------
drop table if exists event_confirmations;
create table event_confirmations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references eventos_agenda(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

alter table event_confirmations enable row level security;

drop policy if exists "event_confirmations: leitura publica" on event_confirmations;
create policy "event_confirmations: leitura publica" on event_confirmations
  for select using (true);

drop policy if exists "event_confirmations: inserir a propria" on event_confirmations;
create policy "event_confirmations: inserir a propria" on event_confirmations
  for insert with check (auth.uid() = user_id);

drop policy if exists "event_confirmations: remover a propria" on event_confirmations;
create policy "event_confirmations: remover a propria" on event_confirmations
  for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- especialidades_concluidas: registro de quando cada usuário concluiu
-- cada especialidade. O ano fica explícito na própria linha (não é
-- calculado a partir de "hoje"), então a virada de ano não apaga nada —
-- o contador do ano atual simplesmente começa em zero até a primeira
-- conclusão daquele ano, e o histórico de anos anteriores continua
-- consultável para sempre.
-- ---------------------------------------------------------------------
create table if not exists especialidades_concluidas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references usuarios(id) on delete cascade,
  especialidade text not null,
  categoria text,
  ano int not null,
  data_conclusao date,
  created_at timestamptz not null default now()
);

create index if not exists especialidades_concluidas_usuario_ano_idx
  on especialidades_concluidas(usuario_id, ano);

alter table especialidades_concluidas enable row level security;

drop policy if exists "especialidades_concluidas: acesso publico" on especialidades_concluidas;
create policy "especialidades_concluidas: acesso publico" on especialidades_concluidas
  for all using (true) with check (true);

-- Insígnia de cada especialidade do Manual de Especialidades (catálogo local,
-- ver SPECIALTY_DB no index.html — não tem imagem nenhuma cadastrada por
-- padrão). Qualquer um pode tirar foto/enviar a imagem real da insígnia direto
-- no catálogo; fica salva aqui por nome da especialidade, uma linha por item.
create table if not exists especialidade_fotos (
  nome text primary key,
  foto text not null,
  updated_at timestamptz not null default now()
);

alter table especialidade_fotos enable row level security;

drop policy if exists "especialidade_fotos: acesso publico" on especialidade_fotos;
create policy "especialidade_fotos: acesso publico" on especialidade_fotos
  for all using (true) with check (true);

-- Tela de detalhe de uma especialidade (ver view-specialty-detail no index.html):
-- tabela de referência (código/nível/ano/instituição de origem) + o texto
-- completo dos requisitos numerados — tudo em branco por padrão, preenchido
-- aos poucos direto pelo app, igual a insígnia.
create table if not exists especialidade_detalhes (
  nome text primary key,
  codigo text,
  nivel text,
  ano text,
  instituicao text,
  requisitos text,
  updated_at timestamptz not null default now()
);

-- Arquivos de aula/avaliação anexados a uma especialidade (pode ter vários de
-- cada tipo) — mesmo padrão de comprovante_arquivos (Classes Regulares).
create table if not exists especialidade_arquivos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text not null check (tipo in ('aula', 'avaliacao')),
  arquivo_data text not null,
  arquivo_nome text,
  created_at timestamptz not null default now()
);

alter table especialidade_detalhes enable row level security;
alter table especialidade_arquivos enable row level security;

drop policy if exists "especialidade_detalhes: acesso publico" on especialidade_detalhes;
create policy "especialidade_detalhes: acesso publico" on especialidade_detalhes
  for all using (true) with check (true);

drop policy if exists "especialidade_arquivos: acesso publico" on especialidade_arquivos;
create policy "especialidade_arquivos: acesso publico" on especialidade_arquivos
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- Presença real: `chamadas` é o cabeçalho de cada chamada (data, evento
-- ligado à Agenda Anual quando aplicável, e se ela conta ou não pra
-- frequência anual — chamadas de acampamento/evento avulso normalmente
-- não devem contar). `chamada_presencas` é uma linha por desbravador
-- por chamada. O `ano` fica gravado na própria chamada (eventos_agenda
-- não tem ano — é um calendário recorrente por dia/mês), então a
-- frequência de anos passados nunca muda.
-- ---------------------------------------------------------------------
create table if not exists chamadas (
  id uuid primary key default gen_random_uuid(),
  data date not null,
  ano int not null,
  evento_agenda_id uuid references eventos_agenda(id) on delete set null,
  titulo text not null,
  conta_presenca boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists chamada_presencas (
  id uuid primary key default gen_random_uuid(),
  chamada_id uuid not null references chamadas(id) on delete cascade,
  usuario_id uuid not null references usuarios(id) on delete cascade,
  presente boolean not null default true,
  unique (chamada_id, usuario_id)
);

create index if not exists chamada_presencas_usuario_idx on chamada_presencas(usuario_id);

-- Coluna adicionada depois: antes a chamada era só presente/ausente (booleano),
-- o que não distinguia quem chegou atrasado. Agora cada pessoa tem um dos 3
-- estados: 'presente', 'atraso' ou 'falta'. A coluna `presente` continua sendo
-- gravada junto (true pra presente e atraso, false pra falta) — é ela que o
-- cálculo de frequência anual usa, então nada dessa conta mudou. Chamadas
-- antigas ficam com o default nas linhas marcadas como presentes; o app deriva
-- o estado do booleano quando `status` vem vazio.
-- ('pontual'/'atrasado' foram os nomes da primeira versão desses estados — o app
-- ainda lê esses dois valores, então um banco que já rodou a versão anterior
-- desta migração não precisa de conversão.)
alter table chamada_presencas add column if not exists status text not null default 'presente';

alter table chamadas enable row level security;
alter table chamada_presencas enable row level security;

drop policy if exists "chamadas: acesso publico" on chamadas;
create policy "chamadas: acesso publico" on chamadas
  for all using (true) with check (true);

drop policy if exists "chamada_presencas: acesso publico" on chamada_presencas;
create policy "chamada_presencas: acesso publico" on chamada_presencas
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- desafios_especialidades: desafio de especialidades lançado por Diretor(a)
-- ou Dir. Associado(a), com uma janela de datas. Enquanto a data de hoje cai
-- dentro de [data_inicio, data_fim], o banner "Ranking de Especialidades" do
-- Início mostra o TOP 10 de quem mais concluiu especialidades (tabela
-- especialidades_concluidas) nessa janela. Fora de uma janela ativa o banner
-- fica oculto — não existe um "desligado" explícito, encerrar antes da hora
-- só move data_fim pra ontem.
-- ---------------------------------------------------------------------
create table if not exists desafios_especialidades (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  data_inicio date not null,
  data_fim date not null,
  criado_por text,
  created_at timestamptz not null default now()
);

alter table desafios_especialidades enable row level security;

drop policy if exists "desafios_especialidades: acesso publico" on desafios_especialidades;
create policy "desafios_especialidades: acesso publico" on desafios_especialidades
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- missoes: sistema "Desafio Só Desbravador" — tarefas avulsas que a
-- Diretoria cadastra manualmente (título, descrição, pontos definidos
-- caso a caso, sem regra fixa por tipo). Cada desbravador marca as que
-- concluiu em missoes_concluidas (uma linha por pessoa por missão); a
-- soma de pontos das concluídas por usuário monta o ranking "Seja
-- Destaque" na tela de Missões. `ativa` controla se a missão ainda
-- aparece na lista pra ser concluída — encerrar uma missão não apaga
-- o histórico de quem já concluiu, só tira ela da lista de pendentes.
-- ---------------------------------------------------------------------
create table if not exists missoes (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descricao text,
  pontos int not null default 0,
  ativa boolean not null default true,
  criado_por text,
  created_at timestamptz not null default now()
);

create table if not exists missoes_concluidas (
  id uuid primary key default gen_random_uuid(),
  missao_id uuid not null references missoes(id) on delete cascade,
  usuario_id uuid not null references usuarios(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (missao_id, usuario_id)
);

create index if not exists missoes_concluidas_usuario_idx on missoes_concluidas(usuario_id);

alter table missoes enable row level security;
alter table missoes_concluidas enable row level security;

drop policy if exists "missoes: acesso publico" on missoes;
create policy "missoes: acesso publico" on missoes
  for all using (true) with check (true);

drop policy if exists "missoes_concluidas: acesso publico" on missoes_concluidas;
create policy "missoes_concluidas: acesso publico" on missoes_concluidas
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- atividades_extras: tarefas extras que o(a) Coordenador(a) de Unidades
-- cadastra na tela Pontuação de Unidades, além do ajuste manual de pontos
-- que já existia. `unidade` nula = "geral": qualquer unidade pode concluir,
-- cada uma na sua vez, de forma independente (por isso
-- atividades_extras_concluidas guarda uma linha por unidade que concluiu,
-- não uma só por atividade). `unidade` preenchida = restrita àquela
-- unidade. Marcar como concluída gera um lançamento de verdade em
-- unidade_pontos (unidade_ponto_id guarda o id desse lançamento, pra
-- conseguir desfazer os dois juntos se a unidade desmarcar) — o Rank das
-- Unidades reflete na hora, igual a qualquer outro ajuste de pontos.
-- ---------------------------------------------------------------------
create table if not exists atividades_extras (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descricao text,
  pontos int not null default 0,
  unidade text,
  ativa boolean not null default true,
  criado_por text,
  created_at timestamptz not null default now()
);

create table if not exists atividades_extras_concluidas (
  id uuid primary key default gen_random_uuid(),
  atividade_id uuid not null references atividades_extras(id) on delete cascade,
  unidade text not null,
  unidade_ponto_id uuid references unidade_pontos(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (atividade_id, unidade)
);

create index if not exists atividades_extras_concluidas_atividade_idx on atividades_extras_concluidas(atividade_id);

alter table atividades_extras enable row level security;
alter table atividades_extras_concluidas enable row level security;

drop policy if exists "atividades_extras: acesso publico" on atividades_extras;
create policy "atividades_extras: acesso publico" on atividades_extras
  for all using (true) with check (true);

drop policy if exists "atividades_extras_concluidas: acesso publico" on atividades_extras_concluidas;
create policy "atividades_extras_concluidas: acesso publico" on atividades_extras_concluidas
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- Cada requisito de Classes Regulares marcado como "Concluída" (status
-- 'done' em progresso_requisitos) por um desbravador com conta vinculada
-- (usuario_id) gera um lançamento de 3 pontos pra unidade dele em
-- unidade_pontos — o Rank das Unidades reflete na hora. Só vale daqui pra
-- frente (marcar/desmarcar 'done' a partir de agora); requisitos que já
-- estavam 'done' antes desta coluna existir não geram pontos retroativos.
-- unidade_ponto_id guarda o lançamento gerado, pra poder desfazer se a
-- pessoa desmarcar o requisito depois. Desbravador sem usuario_id
-- vinculado (cadastrado direto em Classes Regulares, sem conta no app)
-- não tem unidade conhecida, então não gera pontos.
-- ---------------------------------------------------------------------
alter table progresso_requisitos add column if not exists unidade_ponto_id uuid references unidade_pontos(id) on delete set null;

-- ---------------------------------------------------------------------
-- classes_rendimento_papeis_extra: quais papéis, além dos que já enxergam
-- por padrão (Administrador, Coordenador de Classes, Diretoria, Diretoria
-- Executiva), podem abrir a tela de Rendimento/Ranking de Classes Regulares.
-- Lista editável pelo próprio Coordenador de Classes (ou Administrador)
-- dentro da tela — ver botão de engrenagem no Ranking de Classes.
-- ---------------------------------------------------------------------
create table if not exists classes_rendimento_papeis_extra (
  papel text primary key references papeis(nome) on update cascade on delete cascade,
  created_at timestamptz not null default now()
);

alter table classes_rendimento_papeis_extra enable row level security;

drop policy if exists "classes_rendimento_papeis_extra: acesso publico" on classes_rendimento_papeis_extra;
create policy "classes_rendimento_papeis_extra: acesso publico" on classes_rendimento_papeis_extra
  for all using (true) with check (true);

-- ---------------------------------------------------------------------
-- notificacao_aniversario_reuniao: configuração única (linha 'default') do
-- aviso no sino "quem faz aniversário até a próxima Reunião Regular" (ver
-- tela Aniversariantes). confirmado_evento_id guarda o id da Reunião
-- (eventos_agenda) já confirmada, pra não repetir o aviso até a reunião
-- seguinte virar a "próxima" de verdade.
-- ---------------------------------------------------------------------
create table if not exists notificacao_aniversario_reuniao (
  id text primary key default 'default',
  ativo boolean not null default false,
  confirmado_evento_id uuid references eventos_agenda(id) on delete set null,
  confirmado_em timestamptz,
  updated_at timestamptz not null default now()
);

insert into notificacao_aniversario_reuniao (id) values ('default') on conflict (id) do nothing;

alter table notificacao_aniversario_reuniao enable row level security;

drop policy if exists "notificacao_aniversario_reuniao: acesso publico" on notificacao_aniversario_reuniao;
create policy "notificacao_aniversario_reuniao: acesso publico" on notificacao_aniversario_reuniao
  for all using (true) with check (true);
