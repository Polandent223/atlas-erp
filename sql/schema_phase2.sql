
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
