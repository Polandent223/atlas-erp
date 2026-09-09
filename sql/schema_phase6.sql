
-- ATLAS - Esquema base para Supabase/PostgreSQL
-- Fase 2. No contiene credenciales.

create extension if not exists pgcrypto;

create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tax_id text,
  phone text,
  email text,
  country text default 'Venezuela',
  base_currency text default 'VES',
  display_currency text default 'USD',
  created_at timestamptz default now()
);

create table if not exists branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  city text,
  status text default 'Activa',
  created_at timestamptz default now()
);

create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  description text,
  permissions jsonb not null default '[]'::jsonb
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  role_id uuid references roles(id) on delete set null,
  full_name text not null,
  status text default 'Activo'
);

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  code text,
  name text not null,
  tax_id text,
  phone text,
  email text,
  city text,
  credit_limit numeric(14,2) default 0,
  status text default 'Activo',
  created_at timestamptz default now()
);

create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  code text,
  name text not null,
  tax_id text,
  phone text,
  email text,
  city text,
  status text default 'Activo',
  created_at timestamptz default now()
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  sku text,
  name text not null,
  category text,
  cost numeric(14,2) default 0,
  price numeric(14,2) default 0,
  tax numeric(6,2) default 0,
  min_stock numeric(14,3) default 0,
  status text default 'Activo',
  created_at timestamptz default now()
);

create table if not exists inventory (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid not null references branches(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  stock numeric(14,3) default 0,
  reserved numeric(14,3) default 0,
  unique(branch_id,product_id)
);

create table if not exists inventory_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid not null references branches(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  movement_type text not null,
  quantity numeric(14,3) not null,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- RLS: todas las tablas de negocio deben filtrar por la empresa del usuario.
alter table companies enable row level security;
alter table branches enable row level security;
alter table roles enable row level security;
alter table profiles enable row level security;
alter table customers enable row level security;
alter table suppliers enable row level security;
alter table products enable row level security;
alter table inventory enable row level security;
alter table inventory_movements enable row level security;

-- Función segura para resolver la empresa del usuario.
create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id from profiles where id = auth.uid()
$$;

-- Ejemplos de políticas por empresa.
create policy "customers_same_company_select" on customers
for select using (company_id = public.current_company_id());

create policy "customers_same_company_write" on customers
for all using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

create policy "suppliers_same_company_select" on suppliers
for select using (company_id = public.current_company_id());

create policy "suppliers_same_company_write" on suppliers
for all using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

create policy "products_same_company_select" on products
for select using (company_id = public.current_company_id());

create policy "products_same_company_write" on products
for all using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

create policy "inventory_same_company_select" on inventory
for select using (company_id = public.current_company_id());

create policy "inventory_same_company_write" on inventory
for all using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

-- Nota:
-- Antes de producción, repetir políticas equivalentes para branches, roles,
-- profiles e inventory_movements y añadir validación por rol/sucursal.


-- ===== FASE 3 =====

create table if not exists exchange_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  rate_date date not null,
  currency text not null,
  rate numeric(18,6) not null,
  source text,
  created_at timestamptz default now()
);

create table if not exists cash_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  name text not null,
  account_type text not null,
  currency text not null,
  balance numeric(18,2) default 0,
  status text default 'Activa'
);

create table if not exists sales (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid not null references branches(id),
  customer_id uuid references customers(id),
  document_number text not null,
  document_date timestamptz default now(),
  subtotal numeric(18,2) not null default 0,
  tax numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  payment_condition text not null,
  status text default 'Completada'
);

create table if not exists sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(14,3) not null,
  unit_price numeric(18,2) not null,
  tax_rate numeric(6,2) default 0
);

create table if not exists purchases (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  branch_id uuid not null references branches(id),
  supplier_id uuid references suppliers(id),
  document_number text not null,
  document_date timestamptz default now(),
  total numeric(18,2) not null default 0,
  payment_condition text not null,
  status text default 'Recibida'
);

create table if not exists purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references purchases(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(14,3) not null,
  unit_cost numeric(18,2) not null
);

create table if not exists receivables (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  customer_id uuid not null references customers(id),
  reference text not null,
  issue_date date not null,
  due_date date not null,
  total numeric(18,2) not null,
  balance numeric(18,2) not null,
  status text default 'Pendiente'
);

create table if not exists payables (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  supplier_id uuid not null references suppliers(id),
  reference text not null,
  issue_date date not null,
  due_date date not null,
  total numeric(18,2) not null,
  balance numeric(18,2) not null,
  status text default 'Pendiente'
);

create table if not exists cash_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  cash_account_id uuid not null references cash_accounts(id),
  movement_date timestamptz default now(),
  movement_type text not null,
  amount numeric(18,2) not null,
  reference text,
  note text
);

alter table exchange_rates enable row level security;
alter table cash_accounts enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table purchases enable row level security;
alter table purchase_items enable row level security;
alter table receivables enable row level security;
alter table payables enable row level security;
alter table cash_movements enable row level security;

-- Antes de producción: aplicar políticas company_id = current_company_id()
-- a todas las tablas de Fase 3 y controlar además sucursal/rol.


-- ===== FASE 4: CONTABILIDAD, AUDITORÍA Y DOCUMENTOS =====
create table if not exists chart_of_accounts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 code text not null, name text not null, account_type text not null,
 active boolean default true, unique(company_id,code)
);
create table if not exists journal_entries (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 reference text, description text, entry_date timestamptz default now(),
 status text default 'Contabilizado', created_by uuid references auth.users(id)
);
create table if not exists journal_lines (
 id uuid primary key default gen_random_uuid(),
 journal_entry_id uuid not null references journal_entries(id) on delete cascade,
 account_id uuid not null references chart_of_accounts(id),
 debit numeric(18,2) default 0, credit numeric(18,2) default 0
);
create table if not exists audit_log (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 user_id uuid references auth.users(id), action text not null,
 entity text not null, entity_id uuid, detail jsonb,
 created_at timestamptz default now()
);
alter table chart_of_accounts enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;
alter table audit_log enable row level security;
-- Producción: políticas RLS por company_id y permisos por rol.


-- ===== FASE 5: OPERACIÓN AVANZADA =====
create table if not exists payment_methods (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 name text not null, method_type text not null, active boolean default true
);
create table if not exists expenses (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid references branches(id), cash_account_id uuid references cash_accounts(id),
 category text, description text, amount numeric(18,2) not null,
 reference text, expense_date timestamptz default now(), created_by uuid references auth.users(id)
);
create table if not exists quotations (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 customer_id uuid references customers(id), document_number text not null,
 quote_date timestamptz default now(), expires_at timestamptz,
 subtotal numeric(18,2) default 0, tax numeric(18,2) default 0,
 total numeric(18,2) default 0, status text default 'Pendiente'
);
create table if not exists quotation_items (
 id uuid primary key default gen_random_uuid(),
 quotation_id uuid not null references quotations(id) on delete cascade,
 product_id uuid not null references products(id), quantity numeric(14,3) not null,
 unit_price numeric(18,2) not null, tax_rate numeric(6,2) default 0
);
create table if not exists stock_transfers (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 product_id uuid not null references products(id),
 from_branch_id uuid not null references branches(id),
 to_branch_id uuid not null references branches(id),
 quantity numeric(14,3) not null, transfer_date timestamptz default now(),
 status text default 'Completada', created_by uuid references auth.users(id)
);
create table if not exists sales_returns (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 sale_id uuid not null references sales(id), product_id uuid not null references products(id),
 quantity numeric(14,3) not null, amount numeric(18,2) not null,
 return_date timestamptz default now(), status text default 'Completada'
);

alter table payment_methods enable row level security;
alter table expenses enable row level security;
alter table quotations enable row level security;
alter table quotation_items enable row level security;
alter table stock_transfers enable row level security;
alter table sales_returns enable row level security;

-- Producción: aplicar RLS por company_id, sucursal y permisos.


-- ===== FASE 6: AUTH, RLS, MULTIEMPRESA Y SUCURSALES =====

create table if not exists user_branch_access (
  user_id uuid not null references auth.users(id) on delete cascade,
  branch_id uuid not null references branches(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  primary key(user_id, branch_id)
);

create index if not exists idx_profiles_company on profiles(company_id);
create index if not exists idx_branches_company on branches(company_id);
create index if not exists idx_customers_company on customers(company_id);
create index if not exists idx_products_company on products(company_id);
create index if not exists idx_sales_company_branch on sales(company_id,branch_id);
create index if not exists idx_purchases_company_branch on purchases(company_id,branch_id);
create index if not exists idx_inventory_company_branch on inventory(company_id,branch_id);
create index if not exists idx_audit_company on audit_log(company_id,created_at desc);

alter table user_branch_access enable row level security;

create or replace function public.current_company_id()
returns uuid language sql stable security definer set search_path=public as $$
  select company_id from profiles where id=auth.uid() and status='Activo'
$$;

create or replace function public.current_role_id()
returns uuid language sql stable security definer set search_path=public as $$
  select role_id from profiles where id=auth.uid() and status='Activo'
$$;

create or replace function public.can_access_branch(p_branch uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from profiles p
    where p.id=auth.uid() and p.status='Activo' and
      (p.branch_id is null or p.branch_id=p_branch or exists(
        select 1 from user_branch_access uba
        where uba.user_id=auth.uid() and uba.branch_id=p_branch and uba.company_id=p.company_id
      ))
  )
$$;

create or replace function public.atlas_healthcheck()
returns text language sql stable security definer set search_path=public as $$
  select case when auth.uid() is null then 'ATLAS conectado; sesión no iniciada'
              else 'ATLAS conectado y autenticado' end
$$;

create or replace function public.atlas_write_audit(
  p_action text, p_entity text, p_detail jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  insert into audit_log(company_id,user_id,action,entity,detail)
  values(public.current_company_id(),auth.uid(),p_action,p_entity,p_detail);
end $$;

-- Snapshot mínimo de diagnóstico/arranque del espacio de trabajo.
create or replace function public.atlas_workspace_snapshot()
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'company',(select to_jsonb(c) from companies c where c.id=public.current_company_id()),
    'profile',(select to_jsonb(p) from profiles p where p.id=auth.uid()),
    'branches',(select coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) from branches b where b.company_id=public.current_company_id() and public.can_access_branch(b.id))
  )
$$;

-- Helper policies. PostgreSQL no permite parametrizar CREATE POLICY dinámicamente,
-- por eso se declaran explícitamente para las tablas principales.

drop policy if exists companies_select_self on companies;
create policy companies_select_self on companies
for select using (id=public.current_company_id());

drop policy if exists profiles_self_company on profiles;
create policy profiles_self_company on profiles
for select using (company_id=public.current_company_id());

drop policy if exists branches_company_select on branches;
create policy branches_company_select on branches
for select using (company_id=public.current_company_id() and public.can_access_branch(id));

drop policy if exists customers_company_all on customers;
create policy customers_company_all on customers
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists suppliers_company_all on suppliers;
create policy suppliers_company_all on suppliers
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists products_company_all on products;
create policy products_company_all on products
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists inventory_company_branch_all on inventory;
create policy inventory_company_branch_all on inventory
for all using (company_id=public.current_company_id() and public.can_access_branch(branch_id))
with check (company_id=public.current_company_id() and public.can_access_branch(branch_id));

drop policy if exists sales_company_branch_all on sales;
create policy sales_company_branch_all on sales
for all using (company_id=public.current_company_id() and public.can_access_branch(branch_id))
with check (company_id=public.current_company_id() and public.can_access_branch(branch_id));

drop policy if exists purchases_company_branch_all on purchases;
create policy purchases_company_branch_all on purchases
for all using (company_id=public.current_company_id() and public.can_access_branch(branch_id))
with check (company_id=public.current_company_id() and public.can_access_branch(branch_id));

drop policy if exists cash_accounts_company_all on cash_accounts;
create policy cash_accounts_company_all on cash_accounts
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists receivables_company_all on receivables;
create policy receivables_company_all on receivables
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists payables_company_all on payables;
create policy payables_company_all on payables
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists exchange_rates_company_all on exchange_rates;
create policy exchange_rates_company_all on exchange_rates
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists expenses_company_all on expenses;
create policy expenses_company_all on expenses
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists quotations_company_all on quotations;
create policy quotations_company_all on quotations
for all using (company_id=public.current_company_id())
with check (company_id=public.current_company_id());

drop policy if exists stock_transfers_company_all on stock_transfers;
create policy stock_transfers_company_all on stock_transfers
for all using (
  company_id=public.current_company_id()
  and public.can_access_branch(from_branch_id)
  and public.can_access_branch(to_branch_id)
)
with check (
  company_id=public.current_company_id()
  and public.can_access_branch(from_branch_id)
  and public.can_access_branch(to_branch_id)
);

drop policy if exists audit_company_select on audit_log;
create policy audit_company_select on audit_log
for select using (company_id=public.current_company_id());

drop policy if exists user_branch_access_self_company on user_branch_access;
create policy user_branch_access_self_company on user_branch_access
for select using (company_id=public.current_company_id() and user_id=auth.uid());

-- IMPORTANTE:
-- El navegador usa únicamente la clave anon pública.
-- Nunca colocar service_role, SMTP passwords ni secretos privados en config.js.
