-- =====================================================================
-- SEGURANÇA — fecha o banco pra quem não é membro do clube (SEC-01)
-- =====================================================================
-- APLICADO no banco do Cedros Digital em 14/11/2026 (migration
-- seguranca_rls_membros). Pode rodar de novo: refaz as mesmas políticas.
--
-- O problema: quase todas as tabelas têm a política
--   for all using (true) with check (true)
-- e a chave anon está no clube.js, que qualquer um lê. Então qualquer
-- pessoa na internet lê, altera e apaga tudo — inclusive dados de menores.
--
-- O que este script faz:
--   1. Cria eh_membro(): verdadeiro só pra quem fez login E tem ficha
--      aprovada e ativa em usuarios (o mesmo critério que o app já usa
--      pra deixar entrar). Conta criada pelo "Sou novo aqui" sem
--      aprovação NÃO é membro.
--   2. Troca toda política "aberta" (using true) das tabelas do schema
--      public por uma que exige eh_membro(). Faz isso varrendo o catálogo,
--      então pega também tabelas que existem no banco mas não neste repo.
--   3. Mantém abertas, só pra leitura, as poucas coisas que o app usa
--      sem login (lista abaixo).
--
-- Continua aberto sem login (só leitura):
--   - papeis ............................ tela de cadastro
--   - unidades .......................... clube.js carrega antes do login
--   - especialidade_detalhes/fotos/arquivos  página pública da especialidade
--   - comprovante (link/QR de requisito): progresso_requisitos,
--     comprovante_arquivos, requisito_subitens e, de desbravadores,
--     SÓ as colunas id, nome e classe
--   - usuarios: o cadastro "Sou novo aqui" pode INSERIR a própria ficha,
--     sempre como Desbravador e não aprovada
--
-- O que este script NÃO resolve (próximo passo):
--   - Dentro do clube, qualquer membro logado ainda pode alterar qualquer
--     tabela pela API (as permissões por papel só existem na tela). Fechar
--     isso exige políticas por papel, tabela a tabela.
--   - Buckets do Storage (ver storage.sql) não são tocados aqui.
--   - Quem troca o próprio e-mail em "Minha conta" perde o acesso até um
--     administrador atualizar o e-mail na ficha (o app já pede isso).
--
-- CUIDADO: o schema.sql recria as políticas abertas (drop policy if
-- exists + create policy ... using (true)). Rodar o schema.sql de novo
-- DEPOIS deste script desfaz a proteção — rode este script outra vez em
-- seguida, ou (melhor) atualize o schema.sql pra usar eh_membro().
-- Pelo mesmo motivo, rodar o schema.sql é o jeito de desfazer este script.
-- =====================================================================

begin;

-- 1. Quem é membro --------------------------------------------------------
-- security definer: precisa ler usuarios mesmo com a RLS de usuarios ativa
-- (senão a função consultaria a própria tabela que ela protege).
create or replace function public.eh_membro()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from usuarios u
    where lower(trim(u.email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
      and u.aprovado
      and u.ativo
  );
$$;

revoke all on function public.eh_membro() from public;
grant execute on function public.eh_membro() to anon, authenticated;

-- 2. Troca as políticas abertas ------------------------------------------
do $$
declare
  p record;
  t record;
begin
  for p in
    select schemaname, tablename, policyname, cmd
    from pg_policies
    where schemaname = 'public'
      and coalesce(qual, 'true') = 'true'
      and coalesce(with_check, 'true') = 'true'
      and tablename <> 'papeis'
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;

  -- Uma política de membro por tabela que ficou sem nenhuma política
  -- (ou seja, as que só tinham a aberta). Tabelas com políticas próprias
  -- e restritas, como event_confirmations (insert/delete da própria
  -- confirmação), ganham a de membro só pra leitura/escrita geral.
  for t in
    select c.relname as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and c.relname <> 'papeis'
  loop
    execute format('drop policy if exists %I on public.%I', t.tablename || ': membros', t.tablename);
    execute format(
      -- (select ...) faz o Postgres avaliar uma vez por consulta, não por linha.
      'create policy %I on public.%I for all to authenticated using ((select public.eh_membro())) with check ((select public.eh_membro()))',
      t.tablename || ': membros', t.tablename);
  end loop;

  -- Tabela sem RLS fica aberta pra anon independente de política. Não
  -- liga a RLS aqui (sem política, a tabela pararia de funcionar), só avisa.
  for t in
    select c.relname as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  loop
    raise notice 'ATENÇÃO: tabela public.% está sem RLS — continua aberta a qualquer um', t.tablename;
  end loop;
end $$;

-- 3. Exceções: o que o app usa sem login ----------------------------------

-- unidades: clube.js carrega a lista antes do login.
create policy "unidades: leitura publica" on unidades
  for select to anon, authenticated using (true);

-- Página pública da especialidade.
create policy "especialidade_detalhes: leitura publica" on especialidade_detalhes
  for select to anon using (true);
create policy "especialidade_fotos: leitura publica" on especialidade_fotos
  for select to anon using (true);
create policy "especialidade_arquivos: leitura publica" on especialidade_arquivos
  for select to anon using (true);

-- Comprovante público de requisito (link/QR).
create policy "progresso_requisitos: leitura publica" on progresso_requisitos
  for select to anon using (true);
create policy "comprovante_arquivos: leitura publica" on comprovante_arquivos
  for select to anon using (true);
create policy "requisito_subitens: leitura publica" on requisito_subitens
  for select to anon using (true);

-- desbravadores: o comprovante só mostra nome e classe. A RLS não filtra
-- colunas, então anon perde o select na tabela e ganha só nessas três.
create policy "desbravadores: leitura publica" on desbravadores
  for select to anon using (true);
revoke select on desbravadores from anon;
grant select (id, nome, classe) on desbravadores to anon;

-- usuarios ----------------------------------------------------------------
-- Cadastro "Sou novo aqui": a ficha nasce como Desbravador, não aprovada e
-- sem acesso customizado — ninguém se cadastra já como administrador.
-- (drop antes: estas duas não são "abertas", então o passo 2 não as apaga
-- e rodar o script de novo falharia com "policy already exists".)
drop policy if exists "usuarios: cadastro proprio" on usuarios;
drop policy if exists "usuarios: ler a propria ficha" on usuarios;
create policy "usuarios: cadastro proprio" on usuarios
  for insert to anon, authenticated
  with check (aprovado = false and papel = 'Desbravador' and acesso is null);

-- Quem acabou de entrar precisa ler a PRÓPRIA ficha pra o app saber se já
-- foi aprovado ("aguarde a liberação") — mesmo ainda não sendo membro.
create policy "usuarios: ler a propria ficha" on usuarios
  for select to authenticated
  using (lower(trim(email)) = lower(trim(coalesce(auth.jwt() ->> 'email', ''))));

commit;

-- Conferência depois de rodar: lista o que ficou.
-- select tablename, policyname, roles, cmd from pg_policies
-- where schemaname = 'public' order by tablename, policyname;
