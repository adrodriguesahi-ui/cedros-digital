-- ---------------------------------------------------------------------
-- Robô do SGC: fila de pedidos feitos no Cedros Digital.
-- O Cedros grava o pedido; o robô (rodando num computador) lança no SGC e
-- devolve o resultado de cada item. Cada lançamento só é salvo no SGC depois
-- que alguém confirma no Cedros (coluna decisao).
-- Rode uma vez no SQL Editor do Supabase; é seguro rodar de novo.
-- ---------------------------------------------------------------------
create table if not exists pedidos_sgc (
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  criado_por text,
  simular boolean not null default false,
  status text not null default 'pendente' check (status in ('pendente', 'em_andamento', 'concluido', 'cancelado', 'erro')),
  robo text,
  mensagem text
);
create table if not exists pedidos_sgc_itens (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references pedidos_sgc(id) on delete cascade,
  ordem int not null default 0,
  nome text not null,
  especialidade text not null,
  data date not null,
  instrutor text,
  situacao text not null default 'pendente' check (situacao in ('pendente', 'preenchido', 'enviado', 'pulado', 'ja_existe', 'erro', 'simulado')),
  decisao text check (decisao in ('salvar', 'pular')),
  obs text,
  atualizado_em timestamptz not null default now()
);
create index if not exists pedidos_sgc_itens_pedido_idx on pedidos_sgc_itens(pedido_id);
create index if not exists pedidos_sgc_status_idx on pedidos_sgc(status);
-- Quais robôs estão ligados (batimento a cada ~15 s) e se a sessão do SGC está ativa.
create table if not exists robos_sgc (
  nome text primary key,
  visto_em timestamptz not null default now(),
  sessao_ok boolean not null default false,
  detalhe text
);

alter table pedidos_sgc enable row level security;
alter table pedidos_sgc_itens enable row level security;
alter table robos_sgc enable row level security;
drop policy if exists p_pedidos_sgc on pedidos_sgc;
create policy p_pedidos_sgc on pedidos_sgc for all using(true) with check(true);
drop policy if exists p_pedidos_sgc_itens on pedidos_sgc_itens;
create policy p_pedidos_sgc_itens on pedidos_sgc_itens for all using(true) with check(true);
drop policy if exists p_robos_sgc on robos_sgc;
create policy p_robos_sgc on robos_sgc for all using(true) with check(true);
