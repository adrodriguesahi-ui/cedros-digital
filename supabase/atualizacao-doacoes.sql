-- Doações da Tesouraria: cadastro do doador (com WhatsApp), quem pediu a
-- doação e lembrete da data. Só acrescenta; pode rodar mais de uma vez sem
-- problema. Rode no SQL Editor do Supabase.

-- Doadores: nome + WhatsApp (só dígitos, com DDD, sem o 55). Dado pessoal:
-- só a liderança que lança na Tesouraria mexe nele pelo app.
create table if not exists tesouraria_doadores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  whatsapp text,
  created_at timestamptz not null default now()
);
alter table tesouraria_doadores enable row level security;
drop policy if exists p_tesouraria_doadores on tesouraria_doadores;
create policy p_tesouraria_doadores on tesouraria_doadores for all using(true) with check(true);

-- No lançamento de "Doação": quem doou, quem pediu e o lembrete. O lembrete
-- fica pendente (lembrete_data preenchida e lembrete_feito_em vazio) até
-- alguém marcar como feito no card da Tesouraria ou no sino do Início.
alter table tesouraria_lancamentos add column if not exists doador_id uuid references tesouraria_doadores(id) on delete set null;
alter table tesouraria_lancamentos add column if not exists solicitado_por text;
alter table tesouraria_lancamentos add column if not exists lembrete_data date;
alter table tesouraria_lancamentos add column if not exists lembrete_feito_em timestamptz;
alter table tesouraria_lancamentos add column if not exists lembrete_feito_por text;
create index if not exists tesouraria_lancamentos_lembrete_idx
  on tesouraria_lancamentos(lembrete_data) where lembrete_data is not null and lembrete_feito_em is null;
