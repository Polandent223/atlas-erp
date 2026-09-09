-- ATLAS Fase 44 — Endurecimiento de seguridad y tablas operativas faltantes
-- Aplicar DESPUÉS de ATLAS_PRODUCTION_PHASE32.sql en un proyecto nuevo de Supabase.
-- No contiene claves privadas ni service_role.

create extension if not exists pgcrypto;

-- Permisos: el navegador nunca decide la empresa ni el permiso efectivo.
create or replace function public.has_permission(p_permission text)
returns boolean
language sql stable security definer
set search_path=public
as $$
 select exists(
  select 1
  from public.user_roles ur
  join public.roles r on r.id=ur.role_id
  join public.profiles p on p.id=ur.user_id
  where ur.user_id=auth.uid()
    and p.status='ACTIVE'
    and p.company_id=r.company_id
    and (
      r.permissions ? '*'
      or r.permissions ? p_permission
    )
 );
$$;

revoke all on function public.has_permission(text) from public;
grant execute on function public.has_permission(text) to authenticated;

-- Sucursales: ya no interpretamos "sin asignaciones" como "todas".
create or replace function public.can_access_branch(p_branch uuid)
returns boolean
language sql stable security definer
set search_path=public
as $$
 select public.has_permission('branches.all')
 or exists(
   select 1 from public.user_branches ub
   where ub.user_id=auth.uid() and ub.branch_id=p_branch
 );
$$;

revoke all on function public.can_access_branch(uuid) from public;
grant execute on function public.can_access_branch(uuid) to authenticated;

-- La empresa autenticada puede leer únicamente su propia ficha.
drop policy if exists atlas_company_self on public.companies;
create policy atlas_company_self on public.companies
for select to authenticated
using(id=public.current_company_id());

-- Elimina las políticas genéricas de escritura amplia creadas por Fase 32.
do $$
declare t text;
begin
 foreach t in array array[
  'profiles','roles','branches','customers','suppliers','products','cash_accounts',
  'receivables','payables','cash_movements','journal_entries','audit_log'
 ] loop
  execute format('drop policy if exists atlas_company_isolation on public.%I',t);
 end loop;
end $$;

-- Catálogos: lectura por empresa; modificación solo con permiso explícito.
drop policy if exists atlas_customers_read on public.customers;
create policy atlas_customers_read on public.customers for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_customers_write on public.customers;
create policy atlas_customers_write on public.customers for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('customers.manage'))
with check(company_id=public.current_company_id() and public.has_permission('customers.manage'));

drop policy if exists atlas_suppliers_read on public.suppliers;
create policy atlas_suppliers_read on public.suppliers for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_suppliers_write on public.suppliers;
create policy atlas_suppliers_write on public.suppliers for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('suppliers.manage'))
with check(company_id=public.current_company_id() and public.has_permission('suppliers.manage'));

drop policy if exists atlas_products_read on public.products;
create policy atlas_products_read on public.products for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_products_write on public.products;
create policy atlas_products_write on public.products for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('products.manage'))
with check(company_id=public.current_company_id() and public.has_permission('products.manage'));

-- Caja: lectura propia; escritura únicamente mediante permiso operativo.
drop policy if exists atlas_cash_read on public.cash_accounts;
create policy atlas_cash_read on public.cash_accounts for select to authenticated
using(company_id=public.current_company_id() and (branch_id is null or public.can_access_branch(branch_id)));
drop policy if exists atlas_cash_write on public.cash_accounts;
create policy atlas_cash_write on public.cash_accounts for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('cash.manage'))
with check(company_id=public.current_company_id() and public.has_permission('cash.manage'));

drop policy if exists atlas_cash_movements_read on public.cash_movements;
create policy atlas_cash_movements_read on public.cash_movements for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_cash_movements_insert on public.cash_movements;
create policy atlas_cash_movements_insert on public.cash_movements for insert to authenticated
with check(company_id=public.current_company_id() and public.has_permission('cash.operate'));
-- No UPDATE/DELETE directo de movimientos de caja.

-- CxC/CxP: edición directa restringida.
drop policy if exists atlas_receivables_read on public.receivables;
create policy atlas_receivables_read on public.receivables for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_receivables_write on public.receivables;
create policy atlas_receivables_write on public.receivables for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('ar.manage'))
with check(company_id=public.current_company_id() and public.has_permission('ar.manage'));

drop policy if exists atlas_payables_read on public.payables;
create policy atlas_payables_read on public.payables for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_payables_write on public.payables;
create policy atlas_payables_write on public.payables for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('ap.manage'))
with check(company_id=public.current_company_id() and public.has_permission('ap.manage'));

-- Auditoría append-only: usuarios nunca actualizan ni eliminan auditoría.
drop policy if exists atlas_audit_read on public.audit_log;
create policy atlas_audit_read on public.audit_log for select to authenticated
using(company_id=public.current_company_id() and public.has_permission('audit.view'));
drop policy if exists atlas_audit_insert on public.audit_log;
create policy atlas_audit_insert on public.audit_log for insert to authenticated
with check(company_id=public.current_company_id() and user_id=auth.uid());
revoke update, delete on public.audit_log from authenticated;

-- Configuración: lectura por empresa, cambios solo con settings.manage.
drop policy if exists atlas_company_settings on public.company_settings;
drop policy if exists atlas_company_settings_read on public.company_settings;
create policy atlas_company_settings_read on public.company_settings for select to authenticated
using(company_id=public.current_company_id());
drop policy if exists atlas_company_settings_write on public.company_settings;
create policy atlas_company_settings_write on public.company_settings for all to authenticated
using(company_id=public.current_company_id() and public.has_permission('settings.manage'))
with check(company_id=public.current_company_id() and public.has_permission('settings.manage'));

-- Tablas que faltaban en la base inicial.
create table if not exists public.payment_methods(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 name text not null, kind text not null default 'OTHER', active boolean not null default true,
 unique(company_id,name)
);
create table if not exists public.expenses(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid references public.branches(id) on delete restrict,
 cash_account_id uuid references public.cash_accounts(id) on delete restrict,
 reference text not null, description text, currency text not null default 'USD',
 amount numeric(18,4) not null check(amount>=0), created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), unique(company_id,reference)
);
create table if not exists public.quotations(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete restrict,
 customer_id uuid references public.customers(id) on delete set null,
 number text not null, status text not null default 'OPEN', currency text not null default 'USD',
 total numeric(18,4) not null default 0, payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(company_id,number)
);
create table if not exists public.sale_returns(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 sale_id uuid not null references public.sales(id) on delete restrict, number text not null,
 total numeric(18,4) not null default 0, payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(company_id,number)
);
create table if not exists public.purchase_returns(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 purchase_id uuid not null references public.purchases(id) on delete restrict, number text not null,
 total numeric(18,4) not null default 0, payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(company_id,number)
);
create table if not exists public.stock_transfers(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 from_branch_id uuid not null references public.branches(id), to_branch_id uuid not null references public.branches(id),
 number text not null, status text not null default 'DONE', payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(company_id,number),
 check(from_branch_id<>to_branch_id)
);
create table if not exists public.customer_credits(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 customer_id uuid not null references public.customers(id), balance numeric(18,4) not null check(balance>=0),
 currency text not null default 'USD', reference text, created_at timestamptz not null default now()
);
create table if not exists public.supplier_credits(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 supplier_id uuid not null references public.suppliers(id), balance numeric(18,4) not null check(balance>=0),
 currency text not null default 'USD', reference text, created_at timestamptz not null default now()
);
create table if not exists public.cash_closings(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid references public.branches(id), cash_account_id uuid references public.cash_accounts(id),
 expected numeric(18,4) not null default 0, counted numeric(18,4) not null default 0,
 difference numeric(18,4) not null default 0, created_by uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create table if not exists public.exchange_rates(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 currency text not null, rate numeric(18,6) not null check(rate>0), source text,
 effective_at timestamptz not null default now(), unique(company_id,currency,effective_at)
);
create table if not exists public.accounting_accounts(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 code text not null, name text not null, type text not null, active boolean not null default true,
 unique(company_id,code)
);
create table if not exists public.document_counters(
 company_id uuid not null references public.companies(id) on delete cascade,
 document_type text not null, prefix text not null default '', current_value bigint not null default 0,
 primary key(company_id,document_type)
);

-- RLS para nuevas tablas.
do $$
declare t text;
begin
 foreach t in array array[
  'payment_methods','expenses','quotations','sale_returns','purchase_returns',
  'stock_transfers','customer_credits','supplier_credits','cash_closings',
  'exchange_rates','accounting_accounts','document_counters'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists atlas_read on public.%I',t);
  execute format('create policy atlas_read on public.%I for select to authenticated using (company_id=public.current_company_id())',t);
 end loop;
end $$;

-- Escritura de configuración/catálogos auxiliares.
do $$
declare t text;
begin
 foreach t in array array['payment_methods','exchange_rates','accounting_accounts'] loop
  execute format('drop policy if exists atlas_manage on public.%I',t);
  execute format('create policy atlas_manage on public.%I for all to authenticated using (company_id=public.current_company_id() and public.has_permission(''settings.manage'')) with check (company_id=public.current_company_id() and public.has_permission(''settings.manage''))',t);
 end loop;
end $$;

-- Escritura operativa.
do $$
declare t text;
begin
 foreach t in array array['expenses','quotations','sale_returns','purchase_returns','stock_transfers','customer_credits','supplier_credits','cash_closings'] loop
  execute format('drop policy if exists atlas_operate on public.%I',t);
  execute format('create policy atlas_operate on public.%I for all to authenticated using (company_id=public.current_company_id() and public.has_permission(''operations.manage'')) with check (company_id=public.current_company_id() and public.has_permission(''operations.manage''))',t);
 end loop;
end $$;

-- Contador atómico de documentos. Evita números repetidos por dos usuarios simultáneos.
create or replace function public.next_document_number(p_type text, p_prefix text default '')
returns text
language plpgsql security definer
set search_path=public
as $$
declare cid uuid; n bigint;
begin
 cid:=public.current_company_id();
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('sales.operate') or public.has_permission('purchases.operate') or public.has_permission('operations.manage'))
 then raise exception 'Permiso insuficiente'; end if;

 insert into public.document_counters(company_id,document_type,prefix,current_value)
 values(cid,p_type,coalesce(p_prefix,''),1)
 on conflict(company_id,document_type)
 do update set current_value=public.document_counters.current_value+1,
               prefix=excluded.prefix
 returning current_value into n;
 return coalesce(p_prefix,'')||lpad(n::text,6,'0');
end $$;

revoke all on function public.next_document_number(text,text) from public;
grant execute on function public.next_document_number(text,text) to authenticated;

-- Índices de operación.
create index if not exists idx_profiles_company on public.profiles(company_id);
create index if not exists idx_branches_company on public.branches(company_id);
create index if not exists idx_products_company on public.products(company_id);
create index if not exists idx_inventory_company_branch on public.inventory(company_id,branch_id);
create index if not exists idx_sales_company_created on public.sales(company_id,created_at desc);
create index if not exists idx_sales_customer on public.sales(customer_id);
create index if not exists idx_purchases_company_created on public.purchases(company_id,created_at desc);
create index if not exists idx_purchases_supplier on public.purchases(supplier_id);
create index if not exists idx_receivables_company_status on public.receivables(company_id,status);
create index if not exists idx_payables_company_status on public.payables(company_id,status);
create index if not exists idx_cash_movements_company_created on public.cash_movements(company_id,created_at desc);
create index if not exists idx_audit_company_created on public.audit_log(company_id,created_at desc);

-- updated_at consistente en configuración.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;
drop trigger if exists trg_company_settings_updated on public.company_settings;
create trigger trg_company_settings_updated before update on public.company_settings
for each row execute function public.set_updated_at();

-- Endurece el RPC de IDs de migración: sólo entidades conocidas.
create or replace function public.migration_entity_allowed(p_entity text)
returns boolean language sql immutable as $$
 select p_entity=any(array[
 'branches','customers','suppliers','products','payment_methods','cash_accounts',
 'sales','purchases','receivables','payables','journal_entries'
 ]);
$$;

-- Nota de diseño:
-- Ventas, compras, devoluciones, cobros y pagos deben terminar moviéndose mediante RPC transaccionales.
-- Esta fase reduce escritura directa peligrosa, pero no habilita aún la migración real desde el navegador.
