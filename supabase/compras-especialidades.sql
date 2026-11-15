-- ---------------------------------------------------------------------
-- Coordenação de Classes: pedidos de compra de insígnias de especialidades.
-- Cada pedido guarda a lista de especialidades (itens) e os nomes de quem
-- assina o documento de autorização (diretor, solicitante e regional).
-- itens: [{ "nome": "Nós e Amarras", "area": "...", "quantidade": 3, "valor": 6.5,
--           "para": ["Fulano", ...], "ids": [<id em especialidades_concluidas>, ...] }]
-- Rode no SQL Editor do Supabase; é seguro rodar de novo.
-- ---------------------------------------------------------------------
create table if not exists compras_especialidades (
  id uuid primary key default gen_random_uuid(),
  data date not null default current_date,
  status text not null default 'rascunho'
    check (status in ('rascunho', 'emitido', 'autorizado', 'comprado')),
  regional text,
  regiao text,
  diretor text,
  solicitante text,
  observacao text,
  itens jsonb not null default '[]'::jsonb,
  feito_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_compras_especialidades_updated_at on compras_especialidades;
create trigger trg_compras_especialidades_updated_at
  before update on compras_especialidades
  for each row execute function set_updated_at();

-- Só membros logados (mesma regra de supabase/seguranca-rls.sql).
alter table compras_especialidades enable row level security;
drop policy if exists p_compras_especialidades on compras_especialidades;
drop policy if exists "compras_especialidades: membros" on compras_especialidades;
create policy "compras_especialidades: membros" on compras_especialidades
  for all to authenticated
  using ((select public.eh_membro()))
  with check ((select public.eh_membro()));

-- Valor da compra: cada item de "itens" pode ter "valor" (preço por insígnia).
-- O total vai para a Tesouraria como saída; lancamento_id liga o pedido a ela.
alter table compras_especialidades
  add column if not exists lancamento_id uuid references tesouraria_lancamentos(id) on delete set null;

-- Como o diretor aparece nos documentos: 'diretor' ou 'diretora' (vazio = Diretor(a)).
alter table compras_especialidades
  add column if not exists diretor_titulo text
  check (diretor_titulo is null or diretor_titulo in ('diretor', 'diretora'));
