-- Cedros Digital — Storage de arquivos (fotos, documentos)
-- Rode este script no SQL Editor do Supabase, depois de rodar o schema.sql.
--
-- Por que separado do banco: o Postgres (schema.sql) tem cota de 500MB no
-- plano free. Arquivos (fotos, PDFs) NUNCA devem ser guardados como base64
-- numa coluna de tabela — isso estoura o banco rapidíssimo. O Supabase
-- Storage tem cota própria de 1GB, separada do banco, feita exatamente
-- pra isso. O banco só guarda o caminho (texto) de cada arquivo.

-- ---------------------------------------------------------------------
-- bucket público 'arquivos' — mesma política de acesso aberto (anon) já
-- usada nas outras tabelas, já que ainda não há login real (ver
-- disclaimer em schema.sql). Revisar para bucket privado quando houver
-- auth de verdade, especialmente por causa de fotos de menores de idade.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('arquivos', 'arquivos', true, 5242880) -- limite de 5MB por arquivo
on conflict (id) do nothing;

drop policy if exists "arquivos: leitura publica" on storage.objects;
create policy "arquivos: leitura publica" on storage.objects
  for select using (bucket_id = 'arquivos');

drop policy if exists "arquivos: upload publico" on storage.objects;
create policy "arquivos: upload publico" on storage.objects
  for insert with check (bucket_id = 'arquivos');

drop policy if exists "arquivos: remocao publica" on storage.objects;
create policy "arquivos: remocao publica" on storage.objects
  for delete using (bucket_id = 'arquivos');

-- ---------------------------------------------------------------------
-- arquivos: metadados de cada upload (o arquivo em si vive no Storage,
-- aqui só o caminho). `contexto` identifica de onde veio o upload:
-- 'classe_foto', 'unidade_foto', 'evento_doc'.
-- ---------------------------------------------------------------------
create table if not exists arquivos (
  id uuid primary key default gen_random_uuid(),
  contexto text not null,
  referencia text not null, -- ex.: nome do desbravador, da unidade, do evento
  nome_original text not null,
  caminho text not null, -- caminho no bucket 'arquivos'
  tipo text not null, -- mime type
  tamanho int not null, -- bytes
  created_at timestamptz not null default now()
);

alter table arquivos enable row level security;

drop policy if exists "arquivos: acesso publico" on arquivos;
create policy "arquivos: acesso publico" on arquivos
  for all using (true) with check (true);
