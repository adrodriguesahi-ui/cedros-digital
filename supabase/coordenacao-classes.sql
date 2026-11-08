-- ---------------------------------------------------------------------
-- Coordenação de Classes: tudo que o app precisa no banco, num arquivo só.
-- Rode uma vez no SQL Editor do Supabase (é seguro rodar de novo; só cria o
-- que falta e não altera nem apaga dados existentes).
--
--  1) classes_registradas: classe concluída por data (Regular, Avançada ou
--     Liderança), com a data da investidura e um único comprovante (foto do
--     cartão da classe ou arquivo digitalizado, guardado no bucket
--     "comprovantes" do Storage; aqui só o caminho).
--  2) especialidades_concluidas.assinatura: assinaturas já cumpridas
--     (instrutor, regional, associacao, missao), em lista.
--  3) especialidades_concluidas.data_entrega: data de entrega da condecoração.
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
alter table classes_registradas add column if not exists data_investidura date;
alter table classes_registradas add column if not exists comprovante_path text;
alter table classes_registradas add column if not exists comprovante_nome text;
create index if not exists classes_registradas_usuario_idx on classes_registradas(usuario_id);
create index if not exists classes_registradas_ano_idx on classes_registradas(ano);

alter table classes_registradas enable row level security;
drop policy if exists p_classes_registradas on classes_registradas;
create policy p_classes_registradas on classes_registradas for all using(true) with check(true);

alter table especialidades_concluidas add column if not exists assinatura text;
alter table especialidades_concluidas drop constraint if exists especialidades_concluidas_assinatura_chk;
alter table especialidades_concluidas add constraint especialidades_concluidas_assinatura_chk
  check (assinatura is null or assinatura ~ '^(instrutor|regional|associacao|missao)(,(instrutor|regional|associacao|missao))*$');

alter table especialidades_concluidas add column if not exists data_entrega date;
