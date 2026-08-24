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
