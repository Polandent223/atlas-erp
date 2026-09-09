-- ATLAS Fase 32 — Base PostgreSQL/Supabase de producción
-- Ejecutar en un proyecto NUEVO de Supabase.
create extension if not exists pgcrypto;

create table if not exists public.companies(
 id uuid primary key default gen_random_uuid(),
 name text not null,
 tax_id text,
 country text not null default 'VE',
 base_currency text not null default 'USD',
 created_at timestamptz not null default now()
);
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 company_id uuid not null references public.companies(id) on delete cascade,
 full_name text not null,
 status text not null default 'ACTIVE',
 created_at timestamptz not null default now()
);
create table if not exists public.roles(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 name text not null,
 permissions jsonb not null default '[]'::jsonb,
 unique(company_id,name)
);
create table if not exists public.user_roles(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 role_id uuid not null references public.roles(id) on delete restrict
);
create table if not exists public.branches(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 name text not null,
 code text not null,
 active boolean not null default true,
 unique(company_id,code)
);
create table if not exists public.user_branches(
 user_id uuid not null references public.profiles(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade,
 primary key(user_id,branch_id)
);
create table if not exists public.customers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 name text not null, tax_id text, phone text, email text, address text,
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.suppliers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 name text not null, tax_id text, phone text, email text, address text,
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.products(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 sku text not null, name text not null, cost numeric(18,4) not null default 0,
 price numeric(18,4) not null default 0, min_stock numeric(18,4) not null default 0,
 active boolean not null default true, unique(company_id,sku)
);
create table if not exists public.inventory(
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 stock numeric(18,4) not null default 0, reserved numeric(18,4) not null default 0,
 primary key(branch_id,product_id)
);
create table if not exists public.cash_accounts(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid references public.branches(id) on delete set null,
 name text not null, currency text not null default 'USD', balance numeric(18,4) not null default 0,
 active boolean not null default true
);
create table if not exists public.sales(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete restrict,
 customer_id uuid references public.customers(id) on delete set null,
 number text not null, status text not null default 'ACTIVE',
 document_currency text not null default 'USD', exchange_rate numeric(18,6) not null default 1,
 subtotal numeric(18,4) not null default 0, tax numeric(18,4) not null default 0,
 total numeric(18,4) not null default 0, base_total_usd numeric(18,4) not null default 0,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now(),
 unique(company_id,number)
);
create table if not exists public.sale_items(
 id uuid primary key default gen_random_uuid(), sale_id uuid not null references public.sales(id) on delete cascade,
 product_id uuid not null references public.products(id), qty numeric(18,4) not null check(qty>0),
 unit_price numeric(18,4) not null, unit_cost numeric(18,4) not null default 0
);
create table if not exists public.purchases(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete restrict,
 supplier_id uuid references public.suppliers(id) on delete set null,
 number text not null, status text not null default 'ACTIVE',
 document_currency text not null default 'USD', exchange_rate numeric(18,6) not null default 1,
 subtotal numeric(18,4) not null default 0, tax numeric(18,4) not null default 0,
 total numeric(18,4) not null default 0, base_total_usd numeric(18,4) not null default 0,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now(),
 unique(company_id,number)
);
create table if not exists public.purchase_items(
 id uuid primary key default gen_random_uuid(), purchase_id uuid not null references public.purchases(id) on delete cascade,
 product_id uuid not null references public.products(id), qty numeric(18,4) not null check(qty>0),
 unit_cost numeric(18,4) not null
);
create table if not exists public.receivables(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 customer_id uuid references public.customers(id), sale_id uuid references public.sales(id),
 reference text not null, total numeric(18,4) not null, balance numeric(18,4) not null check(balance>=0),
 due_date date, status text not null default 'OPEN'
);
create table if not exists public.payables(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 supplier_id uuid references public.suppliers(id), purchase_id uuid references public.purchases(id),
 reference text not null, total numeric(18,4) not null, balance numeric(18,4) not null check(balance>=0),
 due_date date, status text not null default 'OPEN'
);
create table if not exists public.cash_movements(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 account_id uuid not null references public.cash_accounts(id), direction text not null check(direction in ('IN','OUT')),
 amount numeric(18,4) not null check(amount>0), currency text not null, reference text, description text,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.journal_entries(
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id) on delete cascade,
 reference text not null, description text, created_at timestamptz not null default now()
);
create table if not exists public.journal_lines(
 id uuid primary key default gen_random_uuid(), entry_id uuid not null references public.journal_entries(id) on delete cascade,
 account_code text not null, description text, debit numeric(18,4) not null default 0,
 credit numeric(18,4) not null default 0, check(debit>=0 and credit>=0)
);
create table if not exists public.audit_log(
 id bigint generated always as identity primary key,
 company_id uuid not null references public.companies(id) on delete cascade,
 user_id uuid references public.profiles(id), action text not null, entity text, entity_id text,
 detail jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table if not exists public.company_settings(
 company_id uuid primary key references public.companies(id) on delete cascade,
 fiscal jsonb not null default '{}'::jsonb, document_counters jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now()
);

-- Security helpers: company isolation comes from authenticated profile, never browser company_id.
create or replace function public.current_company_id() returns uuid language sql stable security definer
set search_path=public as $$ select company_id from public.profiles where id=auth.uid() and status='ACTIVE' $$;

create or replace function public.can_access_branch(p_branch uuid) returns boolean language sql stable security definer
set search_path=public as $$
 select exists(select 1 from public.user_branches ub where ub.user_id=auth.uid() and ub.branch_id=p_branch)
 or not exists(select 1 from public.user_branches ub where ub.user_id=auth.uid());
$$;

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;
alter table public.branches enable row level security;
alter table public.user_branches enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.cash_accounts enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.receivables enable row level security;
alter table public.payables enable row level security;
alter table public.cash_movements enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.audit_log enable row level security;
alter table public.company_settings enable row level security;

-- Generic company policies.
do $$
declare t text;
begin
 foreach t in array array['profiles','roles','branches','customers','suppliers','products','cash_accounts','sales','purchases','receivables','payables','cash_movements','journal_entries','audit_log'] loop
  execute format('drop policy if exists atlas_company_isolation on public.%I',t);
  execute format('create policy atlas_company_isolation on public.%I for all to authenticated using (company_id=public.current_company_id()) with check (company_id=public.current_company_id())',t);
 end loop;
end $$;

drop policy if exists atlas_company_settings on public.company_settings;
create policy atlas_company_settings on public.company_settings for all to authenticated
 using(company_id=public.current_company_id()) with check(company_id=public.current_company_id());

drop policy if exists atlas_inventory on public.inventory;
create policy atlas_inventory on public.inventory for all to authenticated
 using(company_id=public.current_company_id() and public.can_access_branch(branch_id))
 with check(company_id=public.current_company_id() and public.can_access_branch(branch_id));

drop policy if exists atlas_user_roles on public.user_roles;
create policy atlas_user_roles on public.user_roles for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=user_roles.user_id and p.company_id=public.current_company_id()));

drop policy if exists atlas_user_branches on public.user_branches;
create policy atlas_user_branches on public.user_branches for select to authenticated
 using(exists(select 1 from public.profiles p where p.id=user_branches.user_id and p.company_id=public.current_company_id()));

drop policy if exists atlas_sale_items on public.sale_items;
create policy atlas_sale_items on public.sale_items for all to authenticated
 using(exists(select 1 from public.sales s where s.id=sale_items.sale_id and s.company_id=public.current_company_id() and public.can_access_branch(s.branch_id)))
 with check(exists(select 1 from public.sales s where s.id=sale_items.sale_id and s.company_id=public.current_company_id() and public.can_access_branch(s.branch_id)));

drop policy if exists atlas_purchase_items on public.purchase_items;
create policy atlas_purchase_items on public.purchase_items for all to authenticated
 using(exists(select 1 from public.purchases p where p.id=purchase_items.purchase_id and p.company_id=public.current_company_id() and public.can_access_branch(p.branch_id)))
 with check(exists(select 1 from public.purchases p where p.id=purchase_items.purchase_id and p.company_id=public.current_company_id() and public.can_access_branch(p.branch_id)));

drop policy if exists atlas_journal_lines on public.journal_lines;
create policy atlas_journal_lines on public.journal_lines for select to authenticated
 using(exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and e.company_id=public.current_company_id()));

-- Sales and purchases get branch-aware read policies replacing generic broad policy.
drop policy if exists atlas_company_isolation on public.sales;
create policy atlas_sales on public.sales for all to authenticated
 using(company_id=public.current_company_id() and public.can_access_branch(branch_id))
 with check(company_id=public.current_company_id() and public.can_access_branch(branch_id));

drop policy if exists atlas_company_isolation on public.purchases;
create policy atlas_purchases on public.purchases for all to authenticated
 using(company_id=public.current_company_id() and public.can_access_branch(branch_id))
 with check(company_id=public.current_company_id() and public.can_access_branch(branch_id));

-- No service_role key is needed in the browser.
