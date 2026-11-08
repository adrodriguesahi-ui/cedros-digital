-- ---------------------------------------------------------------------
-- Coordenação de Classes: quem já assinou a especialidade concluída.
-- Guarda, numa lista separada por vírgula, as assinaturas já cumpridas:
-- instrutor, regional, associacao, missao (vazio = nenhuma ainda).
-- Ex.: 'instrutor,regional'. Rode no SQL Editor do Supabase; é seguro rodar
-- de novo (também atualiza quem já tinha a versão de uma assinatura só).
-- ---------------------------------------------------------------------
alter table especialidades_concluidas add column if not exists assinatura text;
alter table especialidades_concluidas drop constraint if exists especialidades_concluidas_assinatura_chk;
alter table especialidades_concluidas add constraint especialidades_concluidas_assinatura_chk
  check (assinatura is null or assinatura ~ '^(instrutor|regional|associacao|missao)(,(instrutor|regional|associacao|missao))*$');
