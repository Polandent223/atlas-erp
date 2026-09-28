-- ATLAS Fase 56 — Guardas preventivas de integridad
-- Aplicada a producción antes de cargar operación real.
alter table public.inventory drop constraint if exists atlas_inventory_nonnegative,
 add constraint atlas_inventory_nonnegative check(stock>=0 and reserved>=0 and reserved<=stock);
alter table public.cash_accounts drop constraint if exists atlas_cash_balance_finite,
 add constraint atlas_cash_balance_finite check(balance is not null);
alter table public.receivables drop constraint if exists atlas_receivable_bounds,
 add constraint atlas_receivable_bounds check(total>=0 and balance>=0 and balance<=total);
alter table public.payables drop constraint if exists atlas_payable_bounds,
 add constraint atlas_payable_bounds check(total>=0 and balance>=0 and balance<=total);
alter table public.journal_lines drop constraint if exists atlas_journal_line_one_side,
 add constraint atlas_journal_line_one_side check((debit>0 and credit=0) or (credit>0 and debit=0));
create unique index if not exists atlas_accounting_accounts_company_code_uq on public.accounting_accounts(company_id,code);
create index if not exists atlas_receivables_open_idx on public.receivables(company_id,status) where balance>0;
create index if not exists atlas_payables_open_idx on public.payables(company_id,status) where balance>0;
create index if not exists atlas_inventory_lookup_idx on public.inventory(company_id,branch_id,product_id);
