-- ---------------------------------------------------------------------
-- Coordenação de Classes: instrutores que assinam as especialidades
-- (usados no cadastro do SGC). Rode uma vez no SQL Editor do Supabase;
-- é seguro rodar de novo.
-- ---------------------------------------------------------------------
create table if not exists instrutores (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  created_at timestamptz not null default now()
);
alter table instrutores enable row level security;
drop policy if exists p_instrutores on instrutores;
create policy p_instrutores on instrutores for all using(true) with check(true);

-- Instrutor que assinou cada especialidade (enviado ao SGC pelo robô).
alter table especialidades_concluidas add column if not exists instrutor text;
