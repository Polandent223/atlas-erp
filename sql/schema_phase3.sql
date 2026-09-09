
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
