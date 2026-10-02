-- Atualiza o banco do Cedros Digital com o que foi feito no Controle de Classes
-- (26/09 a 02/10/2026). Só acrescenta: colunas novas e as tabelas da
-- Tesouraria. Pode rodar mais de uma vez sem problema.

alter table desbravadores add column if not exists data_nascimento date;
alter table unidades add column if not exists ordem int not null default 0;
alter table unidades add column if not exists emblema text;
alter table requisitos_personalizados add column if not exists criado boolean default false;
alter table requisitos_personalizados add column if not exists oculto boolean default false;
alter table requisitos_personalizados add column if not exists ordem int;
create table if not exists tesouraria_eventos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  data_inicio date,
  data_fim date,
  evento_agenda_id uuid references eventos_agenda(id) on delete set null,
  status text not null default 'aberto' check (status in ('aberto', 'encerrado')),
  observacao text,
  created_at timestamptz not null default now()
);
create table if not exists tesouraria_orcamento (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references tesouraria_eventos(id) on delete cascade,
  tipo text not null check (tipo in ('entrada', 'saida')),
  descricao text not null,
  categoria text,
  valor numeric(12,2) not null default 0 check (valor >= 0),
  created_at timestamptz not null default now()
);
create table if not exists tesouraria_lancamentos (
  id uuid primary key default gen_random_uuid(),
  data date not null,
  descricao text not null,
  tipo text not null check (tipo in ('entrada', 'saida')),
  valor numeric(12,2) not null check (valor >= 0),
  categoria text,
  forma_pagamento text,
  evento_id uuid references tesouraria_eventos(id) on delete restrict,
  orcamento_item_id uuid references tesouraria_orcamento(id) on delete set null,
  observacao text,
  registrado_por text,
  created_at timestamptz not null default now()
);
create index if not exists tesouraria_lancamentos_data_idx on tesouraria_lancamentos(data);
create index if not exists tesouraria_lancamentos_evento_idx on tesouraria_lancamentos(evento_id);
alter table tesouraria_eventos enable row level security;
alter table tesouraria_orcamento enable row level security;
alter table tesouraria_lancamentos enable row level security;
drop policy if exists p_tesouraria_eventos on tesouraria_eventos;
create policy p_tesouraria_eventos on tesouraria_eventos for all using(true) with check(true);
drop policy if exists p_tesouraria_orcamento on tesouraria_orcamento;
create policy p_tesouraria_orcamento on tesouraria_orcamento for all using(true) with check(true);
drop policy if exists p_tesouraria_lancamentos on tesouraria_lancamentos;
create policy p_tesouraria_lancamentos on tesouraria_lancamentos for all using(true) with check(true);
create table if not exists tesouraria_cobrancas (
  id uuid primary key default gen_random_uuid(),
  descricao text not null,
  tipo text not null check (tipo in ('mensalidade', 'taxa', 'parcelada', 'inscricao')),
  valor numeric(12,2) not null check (valor >= 0),
  parcelas int not null default 1 check (parcelas between 1 and 24),
  primeiro_vencimento date not null,
  categoria text,
  evento_id uuid references tesouraria_eventos(id) on delete restrict,
  orcamento_item_id uuid references tesouraria_orcamento(id) on delete set null,
  status text not null default 'aberta' check (status in ('aberta', 'encerrada')),
  created_at timestamptz not null default now()
);
create table if not exists tesouraria_parcelas (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references tesouraria_cobrancas(id) on delete cascade,
  desbravador_id uuid references desbravadores(id) on delete set null,
  pessoa_nome text not null,
  numero int not null default 1,
  total_parcelas int not null default 1,
  valor numeric(12,2) not null check (valor >= 0),
  vencimento date not null,
  pago_em date,
  forma_pagamento text,
  lancamento_id uuid references tesouraria_lancamentos(id) on delete set null,
  observacao text,
  created_at timestamptz not null default now()
);
create index if not exists tesouraria_parcelas_cobranca_idx on tesouraria_parcelas(cobranca_id);
create index if not exists tesouraria_parcelas_vencimento_idx on tesouraria_parcelas(vencimento);
alter table tesouraria_cobrancas enable row level security;
alter table tesouraria_parcelas enable row level security;
drop policy if exists p_tesouraria_cobrancas on tesouraria_cobrancas;
create policy p_tesouraria_cobrancas on tesouraria_cobrancas for all using(true) with check(true);
drop policy if exists p_tesouraria_parcelas on tesouraria_parcelas;
create policy p_tesouraria_parcelas on tesouraria_parcelas for all using(true) with check(true);
