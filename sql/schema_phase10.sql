
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


-- ===== FASE 7: RPC TRANSACCIONALES PARA OPERACIONES CRÍTICAS =====

create or replace function public.atlas_create_sale(
  p_branch_id uuid,
  p_customer_id uuid,
  p_payment_condition text,
  p_cash_account_id uuid,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid := public.current_company_id();
  v_sale_id uuid := gen_random_uuid();
  v_number text;
  v_subtotal numeric(18,2) := 0;
  v_tax numeric(18,2) := 0;
  v_total numeric(18,2) := 0;
  v_item jsonb;
  v_product products%rowtype;
  v_qty numeric(14,3);
  v_stock numeric(14,3);
begin
  if v_company is null then raise exception 'Usuario sin empresa activa'; end if;
  if not public.can_access_branch(p_branch_id) then raise exception 'Sucursal no autorizada'; end if;

  select 'V-'||lpad((count(*)+1)::text,5,'0') into v_number
  from sales where company_id=v_company;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select * into v_product from products
    where id=(v_item->>'product_id')::uuid and company_id=v_company;

    if v_product.id is null then raise exception 'Producto inválido'; end if;
    v_qty := (v_item->>'qty')::numeric;

    select stock into v_stock from inventory
    where company_id=v_company and branch_id=p_branch_id and product_id=v_product.id
    for update;

    if coalesce(v_stock,0) < v_qty then
      raise exception 'Stock insuficiente para %', v_product.name;
    end if;

    v_subtotal := v_subtotal + (v_qty * v_product.price);
    v_tax := v_tax + (v_qty * v_product.price * v_product.tax / 100);
  end loop;

  v_total := v_subtotal + v_tax;

  insert into sales(id,company_id,branch_id,customer_id,document_number,subtotal,tax,total,payment_condition,status)
  values(v_sale_id,v_company,p_branch_id,p_customer_id,v_number,v_subtotal,v_tax,v_total,p_payment_condition,'Completada');

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select * into v_product from products where id=(v_item->>'product_id')::uuid;
    v_qty := (v_item->>'qty')::numeric;

    insert into sale_items(sale_id,product_id,quantity,unit_price,tax_rate)
    values(v_sale_id,v_product.id,v_qty,v_product.price,v_product.tax);

    update inventory set stock=stock-v_qty
    where company_id=v_company and branch_id=p_branch_id and product_id=v_product.id;

    insert into inventory_movements(company_id,branch_id,product_id,movement_type,quantity,note,created_by)
    values(v_company,p_branch_id,v_product.id,'VENTA',-v_qty,v_number,auth.uid());
  end loop;

  if p_payment_condition='cash' then
    update cash_accounts set balance=balance+v_total
    where id=p_cash_account_id and company_id=v_company;
    insert into cash_movements(company_id,cash_account_id,movement_type,amount,reference,note)
    values(v_company,p_cash_account_id,'IN',v_total,v_number,'Venta de contado');
  else
    insert into receivables(company_id,customer_id,reference,issue_date,due_date,total,balance,status)
    values(v_company,p_customer_id,v_number,current_date,current_date+30,v_total,v_total,'Pendiente');
  end if;

  perform public.atlas_write_audit('CREATE','sale',jsonb_build_object('sale_id',v_sale_id,'number',v_number,'total',v_total));

  return jsonb_build_object('id',v_sale_id,'number',v_number,'subtotal',v_subtotal,'tax',v_tax,'total',v_total);
end $$;

create or replace function public.atlas_create_purchase(
  p_branch_id uuid,
  p_supplier_id uuid,
  p_payment_condition text,
  p_cash_account_id uuid,
  p_product_id uuid,
  p_qty numeric,
  p_cost numeric
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid := public.current_company_id();
  v_purchase_id uuid := gen_random_uuid();
  v_number text;
  v_total numeric(18,2) := p_qty*p_cost;
begin
  if v_company is null then raise exception 'Usuario sin empresa activa'; end if;
  if not public.can_access_branch(p_branch_id) then raise exception 'Sucursal no autorizada'; end if;

  select 'C-'||lpad((count(*)+1)::text,5,'0') into v_number
  from purchases where company_id=v_company;

  insert into purchases(id,company_id,branch_id,supplier_id,document_number,total,payment_condition,status)
  values(v_purchase_id,v_company,p_branch_id,p_supplier_id,v_number,v_total,p_payment_condition,'Recibida');

  insert into purchase_items(purchase_id,product_id,quantity,unit_cost)
  values(v_purchase_id,p_product_id,p_qty,p_cost);

  insert into inventory(company_id,branch_id,product_id,stock,reserved)
  values(v_company,p_branch_id,p_product_id,p_qty,0)
  on conflict(branch_id,product_id)
  do update set stock=inventory.stock+excluded.stock;

  update products set cost=p_cost where id=p_product_id and company_id=v_company;

  insert into inventory_movements(company_id,branch_id,product_id,movement_type,quantity,note,created_by)
  values(v_company,p_branch_id,p_product_id,'COMPRA',p_qty,v_number,auth.uid());

  if p_payment_condition='cash' then
    update cash_accounts set balance=balance-v_total
    where id=p_cash_account_id and company_id=v_company;
    insert into cash_movements(company_id,cash_account_id,movement_type,amount,reference,note)
    values(v_company,p_cash_account_id,'OUT',v_total,v_number,'Compra de contado');
  else
    insert into payables(company_id,supplier_id,reference,issue_date,due_date,total,balance,status)
    values(v_company,p_supplier_id,v_number,current_date,current_date+30,v_total,v_total,'Pendiente');
  end if;

  perform public.atlas_write_audit('CREATE','purchase',jsonb_build_object('purchase_id',v_purchase_id,'number',v_number,'total',v_total));

  return jsonb_build_object('id',v_purchase_id,'number',v_number,'total',v_total);
end $$;

grant execute on function public.atlas_create_sale(uuid,uuid,text,uuid,jsonb) to authenticated;
grant execute on function public.atlas_create_purchase(uuid,uuid,text,uuid,uuid,numeric,numeric) to authenticated;


-- ===== FASE 8: CAJA, CXC, CXP, TRANSFERENCIAS, DEVOLUCIONES Y GASTOS =====

create or replace function public.atlas_collect_receivable(
 p_receivable_id uuid, p_amount numeric, p_cash_account_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id(); v_r receivables%rowtype; v_apply numeric;
begin
 select * into v_r from receivables where id=p_receivable_id and company_id=v_company for update;
 if v_r.id is null then raise exception 'Cuenta por cobrar no encontrada'; end if;
 v_apply:=least(p_amount,v_r.balance);
 if v_apply<=0 then raise exception 'Monto inválido'; end if;
 update receivables set balance=balance-v_apply,status=case when balance-v_apply<=0 then 'Pagada' else 'Parcial' end where id=v_r.id;
 update cash_accounts set balance=balance+v_apply where id=p_cash_account_id and company_id=v_company;
 insert into cash_movements(company_id,cash_account_id,movement_type,amount,reference,note)
 values(v_company,p_cash_account_id,'IN',v_apply,v_r.reference,'Cobro CxC');
 perform public.atlas_write_audit('CREATE','receivable_payment',jsonb_build_object('receivable_id',v_r.id,'amount',v_apply));
 return jsonb_build_object('applied',v_apply,'remaining',v_r.balance-v_apply);
end $$;

create or replace function public.atlas_pay_payable(
 p_payable_id uuid, p_amount numeric, p_cash_account_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id(); v_r payables%rowtype; v_apply numeric;
begin
 select * into v_r from payables where id=p_payable_id and company_id=v_company for update;
 if v_r.id is null then raise exception 'Cuenta por pagar no encontrada'; end if;
 v_apply:=least(p_amount,v_r.balance);
 if v_apply<=0 then raise exception 'Monto inválido'; end if;
 update payables set balance=balance-v_apply,status=case when balance-v_apply<=0 then 'Pagada' else 'Parcial' end where id=v_r.id;
 update cash_accounts set balance=balance-v_apply where id=p_cash_account_id and company_id=v_company;
 insert into cash_movements(company_id,cash_account_id,movement_type,amount,reference,note)
 values(v_company,p_cash_account_id,'OUT',v_apply,v_r.reference,'Pago CxP');
 perform public.atlas_write_audit('CREATE','payable_payment',jsonb_build_object('payable_id',v_r.id,'amount',v_apply));
 return jsonb_build_object('applied',v_apply,'remaining',v_r.balance-v_apply);
end $$;

create or replace function public.atlas_transfer_stock(
 p_product_id uuid,p_from_branch uuid,p_to_branch uuid,p_qty numeric
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id(); v_stock numeric; v_number text;
begin
 if p_from_branch=p_to_branch then raise exception 'Origen y destino deben ser distintos'; end if;
 if not public.can_access_branch(p_from_branch) or not public.can_access_branch(p_to_branch) then raise exception 'Sucursal no autorizada'; end if;
 select stock into v_stock from inventory where company_id=v_company and branch_id=p_from_branch and product_id=p_product_id for update;
 if coalesce(v_stock,0)<p_qty then raise exception 'Stock insuficiente'; end if;
 v_number:='TR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 update inventory set stock=stock-p_qty where company_id=v_company and branch_id=p_from_branch and product_id=p_product_id;
 insert into inventory(company_id,branch_id,product_id,stock,reserved) values(v_company,p_to_branch,p_product_id,p_qty,0)
 on conflict(branch_id,product_id) do update set stock=inventory.stock+excluded.stock;
 insert into stock_transfers(company_id,product_id,from_branch_id,to_branch_id,quantity,status) values(v_company,p_product_id,p_from_branch,p_to_branch,p_qty,'Completada');
 insert into inventory_movements(company_id,branch_id,product_id,movement_type,quantity,note,created_by) values
 (v_company,p_from_branch,p_product_id,'TRANSFERENCIA SALIDA',-p_qty,v_number,auth.uid()),
 (v_company,p_to_branch,p_product_id,'TRANSFERENCIA ENTRADA',p_qty,v_number,auth.uid());
 perform public.atlas_write_audit('CREATE','stock_transfer',jsonb_build_object('number',v_number,'qty',p_qty));
 return jsonb_build_object('number',v_number,'qty',p_qty);
end $$;

create or replace function public.atlas_create_expense(
 p_cash_account_id uuid,p_category text,p_description text,p_amount numeric,p_reference text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id(); v_id uuid:=gen_random_uuid(); v_ref text:=coalesce(nullif(p_reference,''),'G-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'));
begin
 if p_amount<=0 then raise exception 'Monto inválido'; end if;
 insert into expenses(id,company_id,cash_account_id,category,description,amount,reference,created_by)
 values(v_id,v_company,p_cash_account_id,p_category,p_description,p_amount,v_ref,auth.uid());
 update cash_accounts set balance=balance-p_amount where id=p_cash_account_id and company_id=v_company;
 insert into cash_movements(company_id,cash_account_id,movement_type,amount,reference,note)
 values(v_company,p_cash_account_id,'OUT',p_amount,v_ref,p_description);
 perform public.atlas_write_audit('CREATE','expense',jsonb_build_object('expense_id',v_id,'amount',p_amount));
 return jsonb_build_object('id',v_id,'reference',v_ref,'amount',p_amount);
end $$;

grant execute on function public.atlas_collect_receivable(uuid,numeric,uuid) to authenticated;
grant execute on function public.atlas_pay_payable(uuid,numeric,uuid) to authenticated;
grant execute on function public.atlas_transfer_stock(uuid,uuid,uuid,numeric) to authenticated;
grant execute on function public.atlas_create_expense(uuid,text,text,numeric,text) to authenticated;


-- ===== FASE 9: DEVOLUCIONES REMOTAS Y PERMISOS FINOS =====

create table if not exists permissions (
  key text primary key,
  label text not null
);

create table if not exists role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  permission_key text not null references permissions(key) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  primary key(role_id,permission_key)
);

alter table role_permissions enable row level security;

insert into permissions(key,label) values
('dashboard','Dashboard'),('company','Empresa'),('branches','Sucursales'),
('customers','Clientes'),('suppliers','Proveedores'),('products','Productos'),
('inventory','Inventario'),('stockTransfers','Transferencias de stock'),
('sales','Ventas / POS'),('quotations','Cotizaciones'),('purchases','Compras'),
('returns','Devoluciones'),('cash','Caja y bancos'),('expenses','Gastos'),
('receivables','Cuentas por cobrar'),('payables','Cuentas por pagar'),
('rates','Tasas'),('paymentMethods','Métodos de pago'),('users','Usuarios'),
('roles','Roles'),('accounting','Contabilidad'),('reports','Reportes'),
('audit','Auditoría'),('documents','Documentos'),('settings','Configuración'),
('backup','Respaldo'),('system','Sistema y nube')
on conflict(key) do nothing;

create or replace function public.has_permission(p_key text)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
   select 1
   from profiles p
   join roles r on r.id=p.role_id
   where p.id=auth.uid()
     and p.status='Activo'
     and (
       exists(select 1 from role_permissions rp where rp.role_id=r.id and rp.company_id=p.company_id and rp.permission_key=p_key)
       or lower(r.name)='administrador'
     )
 )
$$;

drop policy if exists role_permissions_company_select on role_permissions;
create policy role_permissions_company_select on role_permissions
for select using(company_id=public.current_company_id());

create or replace function public.atlas_return_sale(
 p_sale_id uuid,p_product_id uuid,p_qty numeric
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_company uuid:=public.current_company_id();
 v_sale sales%rowtype;
 v_line sale_items%rowtype;
 v_returned numeric:=0;
 v_amount numeric:=0;
 v_number text;
begin
 if p_qty<=0 then raise exception 'Cantidad inválida'; end if;

 select * into v_sale from sales where id=p_sale_id and company_id=v_company for update;
 if v_sale.id is null then raise exception 'Venta no encontrada'; end if;
 if not public.can_access_branch(v_sale.branch_id) then raise exception 'Sucursal no autorizada'; end if;

 select * into v_line from sale_items where sale_id=v_sale.id and product_id=p_product_id;
 if v_line.id is null then raise exception 'Producto no pertenece a la venta'; end if;

 select coalesce(sum(quantity),0) into v_returned
 from sales_returns where company_id=v_company and sale_id=v_sale.id and product_id=p_product_id;

 if v_returned+p_qty>v_line.quantity then raise exception 'Cantidad devuelta supera la vendida'; end if;

 v_amount:=p_qty*v_line.unit_price*(1+coalesce(v_line.tax_rate,0)/100);
 v_number:='DV-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');

 insert into sales_returns(company_id,sale_id,product_id,quantity,amount,status)
 values(v_company,v_sale.id,p_product_id,p_qty,v_amount,'Completada');

 insert into inventory(company_id,branch_id,product_id,stock,reserved)
 values(v_company,v_sale.branch_id,p_product_id,p_qty,0)
 on conflict(branch_id,product_id)
 do update set stock=inventory.stock+excluded.stock;

 insert into inventory_movements(company_id,branch_id,product_id,movement_type,quantity,note,created_by)
 values(v_company,v_sale.branch_id,p_product_id,'DEVOLUCIÓN',p_qty,v_number,auth.uid());

 perform public.atlas_write_audit('CREATE','return',jsonb_build_object('number',v_number,'sale_id',v_sale.id,'amount',v_amount));

 return jsonb_build_object('number',v_number,'amount',v_amount,'qty',p_qty);
end $$;

grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.atlas_return_sale(uuid,uuid,numeric) to authenticated;


-- ===== FASE 10: INTEGRIDAD Y DESACTIVACIÓN SEGURA =====

alter table branches add column if not exists active boolean not null default true;
alter table customers add column if not exists active boolean not null default true;
alter table suppliers add column if not exists active boolean not null default true;
alter table products add column if not exists active boolean not null default true;

create unique index if not exists uq_branches_company_name_active
on branches(company_id,lower(name)) where active=true;

create unique index if not exists uq_customers_company_code_active
on customers(company_id,lower(code)) where active=true and code is not null;

create unique index if not exists uq_suppliers_company_code_active
on suppliers(company_id,lower(code)) where active=true and code is not null;

create unique index if not exists uq_products_company_sku_active
on products(company_id,lower(sku)) where active=true and sku is not null;

do $$
begin
 if not exists(select 1 from pg_constraint where conname='inventory_stock_nonnegative') then
  alter table inventory add constraint inventory_stock_nonnegative check(stock>=0);
 end if;
 if not exists(select 1 from pg_constraint where conname='inventory_reserved_nonnegative') then
  alter table inventory add constraint inventory_reserved_nonnegative check(reserved>=0);
 end if;
end $$;

create or replace function public.atlas_guard_permission(p_key text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Sesión requerida'; end if;
 if not public.has_permission(p_key) then raise exception 'Permiso denegado: %',p_key; end if;
end $$;

grant execute on function public.atlas_guard_permission(text) to authenticated;

create or replace function public.atlas_set_master_active(
 p_entity text,p_id uuid,p_active boolean
) returns boolean language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id(); v_permission text;
begin
 v_permission:=case
  when p_entity='branch' then 'branches'
  when p_entity='customer' then 'customers'
  when p_entity='supplier' then 'suppliers'
  when p_entity='product' then 'products'
  else null end;
 if v_permission is null then raise exception 'Entidad no permitida'; end if;
 perform public.atlas_guard_permission(v_permission);

 if p_entity='branch' then
  update branches set active=p_active where id=p_id and company_id=v_company;
 elsif p_entity='customer' then
  update customers set active=p_active where id=p_id and company_id=v_company;
 elsif p_entity='supplier' then
  update suppliers set active=p_active where id=p_id and company_id=v_company;
 elsif p_entity='product' then
  update products set active=p_active where id=p_id and company_id=v_company;
 end if;

 if not found then raise exception 'Registro no encontrado'; end if;
 perform public.atlas_write_audit('UPDATE',p_entity,jsonb_build_object('id',p_id,'active',p_active));
 return true;
end $$;

grant execute on function public.atlas_set_master_active(text,uuid,boolean) to authenticated;

-- Mantener las operaciones sensibles fuera de acceso anónimo.
revoke all on function public.atlas_create_sale(uuid,uuid,text,uuid,jsonb) from public;
revoke all on function public.atlas_create_purchase(uuid,uuid,text,uuid,uuid,numeric,numeric) from public;
revoke all on function public.atlas_collect_receivable(uuid,numeric,uuid) from public;
revoke all on function public.atlas_pay_payable(uuid,numeric,uuid) from public;
revoke all on function public.atlas_transfer_stock(uuid,uuid,uuid,numeric) from public;
revoke all on function public.atlas_create_expense(uuid,text,text,numeric,text) from public;
revoke all on function public.atlas_return_sale(uuid,uuid,numeric) from public;
