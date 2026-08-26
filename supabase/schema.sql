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

create table if not exists progresso_requisitos (
  id uuid primary key default gen_random_uuid(),
  desbravador_id uuid not null references desbravadores(id) on delete cascade,
  requisito_titulo text not null,
  status text not null default 'todo',
  updated_at timestamptz not null default now(),
  unique (desbravador_id, requisito_titulo)
);

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

drop policy if exists "desbravadores: acesso publico" on desbravadores;
create policy "desbravadores: acesso publico" on desbravadores
  for all using (true) with check (true);

drop policy if exists "progresso_requisitos: acesso publico" on progresso_requisitos;
create policy "progresso_requisitos: acesso publico" on progresso_requisitos
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

alter table unidades enable row level security;
alter table unit_funcoes enable row level security;
alter table unit_atividades enable row level security;
alter table unit_avaliacoes enable row level security;
alter table unit_conquistas enable row level security;
alter table unit_mes_resumo enable row level security;

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
