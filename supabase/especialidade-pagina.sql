-- ---------------------------------------------------------------------
-- Coordenação de Classes: número da página do registro de especialidades
-- (livro/caderno do clube) em que a especialidade foi anotada.
-- Rode no SQL Editor do Supabase; é seguro rodar de novo.
-- ---------------------------------------------------------------------
alter table especialidades_concluidas add column if not exists pagina_registro text;
