-- ---------------------------------------------------------------------
-- Coordenação de Classes: registro de classes concluídas por data.
-- Guarda a classe que o desbravador concluiu (Regular, Avançada ou Liderança)
-- e o ano/data, pra montar o histórico por ano e os relatórios, inclusive de
-- classes feitas antes de o app existir (sem requisitos marcados).
-- Quem tem conta no app liga por usuario_id; quem não tem, pelo nome.
-- Rode uma vez no SQL Editor do Supabase (é seguro rodar de novo).
-- ---------------------------------------------------------------------
create table if not exists classes_registradas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references usuarios(id) on delete cascade,
  nome_aluno text,
  classe text not null,
  nivel text not null default 'regular' check (nivel in ('regular', 'avancada', 'lideranca')),
  ano int not null,
  data_conclusao date,
  registrado_por text,
  created_at timestamptz not null default now(),
  check (usuario_id is not null or nome_aluno is not null)
);
create index if not exists classes_registradas_usuario_idx on classes_registradas(usuario_id);
create index if not exists classes_registradas_ano_idx on classes_registradas(ano);

alter table classes_registradas enable row level security;
drop policy if exists p_classes_registradas on classes_registradas;
create policy p_classes_registradas on classes_registradas for all using(true) with check(true);
