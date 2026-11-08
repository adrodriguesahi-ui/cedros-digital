-- ---------------------------------------------------------------------
-- Coordenação de Classes: quem assinou a especialidade concluída.
-- Guarda o nível da assinatura de cada especialidade registrada: Instrutor,
-- Regional, Associação ou Missão (vazio = ainda sem assinatura).
-- Rode uma vez no SQL Editor do Supabase (é seguro rodar de novo).
-- ---------------------------------------------------------------------
alter table especialidades_concluidas add column if not exists assinatura text;
alter table especialidades_concluidas drop constraint if exists especialidades_concluidas_assinatura_chk;
alter table especialidades_concluidas add constraint especialidades_concluidas_assinatura_chk
  check (assinatura is null or assinatura in ('instrutor', 'regional', 'associacao', 'missao'));
