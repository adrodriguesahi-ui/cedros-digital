-- Avisos de doação no celular (notificação push pela web). Só acrescenta; pode
-- rodar mais de uma vez sem problema. Rode no SQL Editor do Supabase.

-- Um registro por celular/navegador que ativou os avisos (Tesouraria → ⚙).
-- O app só insere e apaga; a leitura é só da função lembretes-doacao (chave de
-- serviço), então ninguém consegue listar os endereços de push pelo app.
create table if not exists push_inscricoes (
  id uuid primary key default gen_random_uuid(),
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  usuario_id uuid,
  usuario_nome text,
  created_at timestamptz not null default now()
);
alter table push_inscricoes enable row level security;
drop policy if exists p_push_inscricoes_insert on push_inscricoes;
create policy p_push_inscricoes_insert on push_inscricoes for insert with check (true);
drop policy if exists p_push_inscricoes_delete on push_inscricoes;
create policy p_push_inscricoes_delete on push_inscricoes for delete using (true);

-- Agendamento diário, 8h de Brasília (11h UTC). Troque SEGREDO pelo valor da
-- variável CRON_SECRET da função (não guarde o segredo real no repositório).
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
-- select cron.schedule('lembretes-doacao-8h', '0 11 * * *', $$
--   select net.http_post(
--     url := 'https://noqaveawzxipxnmufwfn.supabase.co/functions/v1/lembretes-doacao',
--     headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', 'SEGREDO'),
--     body := '{}'::jsonb
--   )
-- $$);
