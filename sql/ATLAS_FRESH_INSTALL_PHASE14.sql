-- ATLAS FASE 14 — INSTALACIÓN LIMPIA
-- Ejecutar en un proyecto Supabase NUEVO.
create extension if not exists pgcrypto;

create table companies(
 id uuid primary key default gen_random_uuid(),
 name text not null,
 tax_id text,
 country text default 'VE',
 base_currency text default 'VES',
 display_currency text default 'USD',
 active boolean not null default true,
 created_at timestamptz not null default now()
);

create table roles(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 name text not null,
 active boolean not null default true,
 unique(company_id,name)
);

create table permissions(
 key text primary key,
 label text not null
);

create table role_permissions(
 role_id uuid not null references roles(id) on delete cascade,
 permission_key text not null references permissions(key) on delete cascade,
 company_id uuid not null references companies(id) on delete cascade,
 primary key(role_id,permission_key)
);

create table profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 company_id uuid not null references companies(id) on delete cascade,
 role_id uuid references roles(id),
 name text not null,
 email text,
 status text not null default 'Activo',
 created_at timestamptz default now()
);

create table branches(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 name text not null,
 code text,
 active boolean not null default true,
 created_at timestamptz default now()
);
create unique index uq_branch_active_name on branches(company_id,lower(name)) where active;

create table user_branch_access(
 user_id uuid not null references auth.users(id) on delete cascade,
 branch_id uuid not null references branches(id) on delete cascade,
 company_id uuid not null references companies(id) on delete cascade,
 primary key(user_id,branch_id)
);

create table customers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 code text not null,
 name text not null,
 tax_id text, phone text, email text, address text,
 active boolean not null default true,
 created_at timestamptz default now()
);
create unique index uq_customer_active_code on customers(company_id,lower(code)) where active;

create table suppliers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 code text not null,
 name text not null,
 tax_id text, phone text, email text, address text,
 active boolean not null default true,
 created_at timestamptz default now()
);
create unique index uq_supplier_active_code on suppliers(company_id,lower(code)) where active;

create table products(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 sku text not null,
 name text not null,
 cost numeric(18,2) not null default 0 check(cost>=0),
 price numeric(18,2) not null default 0 check(price>=0),
 tax numeric(7,3) not null default 0 check(tax between 0 and 100),
 min_stock numeric(14,3) not null default 0,
 active boolean not null default true,
 created_at timestamptz default now()
);
create unique index uq_product_active_sku on products(company_id,lower(sku)) where active;

create table inventory(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid not null references branches(id),
 product_id uuid not null references products(id),
 stock numeric(14,3) not null default 0 check(stock>=0),
 reserved numeric(14,3) not null default 0 check(reserved>=0),
 unique(branch_id,product_id)
);

create table inventory_movements(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid not null references branches(id),
 product_id uuid not null references products(id),
 movement_type text not null,
 quantity numeric(14,3) not null,
 note text,
 created_by uuid references auth.users(id),
 created_at timestamptz default now()
);

create table exchange_rates(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 currency text not null,
 rate numeric(18,6) not null check(rate>0),
 source text default 'manual',
 effective_at timestamptz default now()
);

create table payment_methods(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 name text not null,
 active boolean not null default true
);

create table cash_accounts(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 name text not null,
 currency text not null default 'USD',
 balance numeric(18,2) not null default 0,
 active boolean not null default true
);

create table sales(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid not null references branches(id),
 customer_id uuid references customers(id),
 document_number text not null,
 subtotal numeric(18,2) not null default 0,
 tax numeric(18,2) not null default 0,
 total numeric(18,2) not null default 0,
 payment_condition text not null default 'cash',
 status text not null default 'Completada',
 created_at timestamptz default now(),
 unique(company_id,document_number)
);

create table sale_items(
 id uuid primary key default gen_random_uuid(),
 sale_id uuid not null references sales(id) on delete cascade,
 product_id uuid not null references products(id),
 quantity numeric(14,3) not null check(quantity>0),
 unit_price numeric(18,2) not null,
 unit_cost numeric(18,2) not null default 0,
 tax_rate numeric(7,3) not null default 0
);

create table purchases(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid not null references branches(id),
 supplier_id uuid references suppliers(id),
 document_number text not null,
 subtotal numeric(18,2) not null default 0,
 tax numeric(18,2) not null default 0,
 total numeric(18,2) not null default 0,
 payment_condition text not null default 'cash',
 status text not null default 'Recibida',
 created_at timestamptz default now(),
 unique(company_id,document_number)
);

create table purchase_items(
 id uuid primary key default gen_random_uuid(),
 purchase_id uuid not null references purchases(id) on delete cascade,
 product_id uuid not null references products(id),
 quantity numeric(14,3) not null check(quantity>0),
 unit_cost numeric(18,2) not null,
 tax_rate numeric(7,3) not null default 0
);

create table receivables(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 customer_id uuid references customers(id),
 reference text not null,
 issue_date date default current_date,
 due_date date,
 total numeric(18,2) not null,
 balance numeric(18,2) not null,
 status text not null default 'Pendiente'
);

create table payables(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 supplier_id uuid references suppliers(id),
 reference text not null,
 issue_date date default current_date,
 due_date date,
 total numeric(18,2) not null,
 balance numeric(18,2) not null,
 status text not null default 'Pendiente'
);

create table cash_movements(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 cash_account_id uuid not null references cash_accounts(id),
 movement_type text not null,
 amount numeric(18,2) not null check(amount>=0),
 reference text,
 note text,
 created_at timestamptz default now()
);

create table expenses(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 cash_account_id uuid not null references cash_accounts(id),
 category text,
 description text not null,
 amount numeric(18,2) not null check(amount>0),
 reference text,
 created_by uuid references auth.users(id),
 created_at timestamptz default now()
);

create table quotations(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 branch_id uuid references branches(id),
 customer_id uuid references customers(id),
 number text not null,
 total numeric(18,2) not null default 0,
 status text not null default 'Abierta',
 created_at timestamptz default now()
);

create table quotation_items(
 id uuid primary key default gen_random_uuid(),
 quotation_id uuid not null references quotations(id) on delete cascade,
 product_id uuid not null references products(id),
 quantity numeric(14,3) not null,
 unit_price numeric(18,2) not null
);

create table stock_transfers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 from_branch_id uuid not null references branches(id),
 to_branch_id uuid not null references branches(id),
 product_id uuid not null references products(id),
 quantity numeric(14,3) not null check(quantity>0),
 status text not null default 'Completada',
 created_at timestamptz default now()
);

create table sales_returns(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 sale_id uuid not null references sales(id),
 product_id uuid not null references products(id),
 quantity numeric(14,3) not null check(quantity>0),
 amount numeric(18,2) not null,
 status text not null default 'Completada',
 created_at timestamptz default now()
);

create table chart_of_accounts(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 code text not null,
 name text not null,
 account_type text not null,
 active boolean not null default true,
 unique(company_id,code),
 unique(company_id,name)
);

create table journal_entries(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 entry_date date not null default current_date,
 reference text,
 description text,
 status text not null default 'Contabilizado',
 created_at timestamptz default now()
);

create table journal_lines(
 id uuid primary key default gen_random_uuid(),
 journal_entry_id uuid not null references journal_entries(id) on delete cascade,
 account_id uuid not null references chart_of_accounts(id),
 debit numeric(18,2) not null default 0 check(debit>=0),
 credit numeric(18,2) not null default 0 check(credit>=0),
 description text,
 check(not (debit>0 and credit>0))
);

create table audit_log(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references companies(id) on delete cascade,
 user_id uuid references auth.users(id),
 action text not null,
 entity text,
 detail jsonb default '{}'::jsonb,
 created_at timestamptz default now()
);

create table app_settings(
 company_id uuid primary key references companies(id) on delete cascade,
 allow_negative_stock boolean not null default false,
 allow_negative_cash boolean not null default false
);

insert into permissions(key,label) values
('dashboard','Dashboard'),('company','Empresa'),('branches','Sucursales'),
('customers','Clientes'),('suppliers','Proveedores'),('products','Productos'),
('inventory','Inventario'),('stockTransfers','Transferencias'),
('sales','Ventas'),('quotations','Cotizaciones'),('purchases','Compras'),
('returns','Devoluciones'),('cash','Caja y bancos'),('expenses','Gastos'),
('receivables','Cuentas por cobrar'),('payables','Cuentas por pagar'),
('rates','Tasas'),('paymentMethods','Métodos de pago'),('users','Usuarios'),
('roles','Roles'),('accounting','Contabilidad'),('reports','Reportes'),
('audit','Auditoría'),('documents','Documentos'),('settings','Configuración'),
('backup','Respaldo'),('system','Sistema y nube')
on conflict(key) do update set label=excluded.label;

create or replace function current_company_id() returns uuid
language sql stable security definer set search_path=public as $$
 select company_id from profiles where id=auth.uid()
$$;

create or replace function has_permission(p_key text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(
  select 1 from profiles p
  join roles r on r.id=p.role_id
  where p.id=auth.uid() and p.status='Activo'
    and (
      lower(r.name)='administrador'
      or exists(select 1 from role_permissions rp where rp.role_id=r.id and rp.permission_key=p_key)
    )
 )
$$;

create or replace function can_access_branch(p_branch uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(
  select 1 from branches b
  where b.id=p_branch and b.company_id=current_company_id()
    and (
      not exists(select 1 from user_branch_access x where x.user_id=auth.uid())
      or exists(select 1 from user_branch_access x where x.user_id=auth.uid() and x.branch_id=p_branch)
    )
 )
$$;

create or replace function atlas_guard_permission(p_key text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not has_permission(p_key) then raise exception 'Permiso denegado: %',p_key; end if;
end $$;

create or replace function atlas_write_audit(p_action text,p_entity text,p_detail jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into audit_log(company_id,user_id,action,entity,detail)
 values(current_company_id(),auth.uid(),p_action,p_entity,coalesce(p_detail,'{}'::jsonb));
end $$;

create or replace function atlas_account_id(p_name text) returns uuid
language sql stable security definer set search_path=public as $$
 select id from chart_of_accounts where company_id=current_company_id() and name=p_name and active limit 1
$$;

create or replace function atlas_seed_chart_of_accounts() returns void
language plpgsql security definer set search_path=public as $$
declare c uuid:=current_company_id();
begin
 perform atlas_guard_permission('accounting');
 insert into chart_of_accounts(company_id,code,name,account_type) values
 (c,'1.1.01','Caja y bancos','Activo'),
 (c,'1.1.02','Cuentas por cobrar','Activo'),
 (c,'1.1.03','Inventario','Activo'),
 (c,'1.1.04','IVA crédito fiscal','Activo'),
 (c,'2.1.01','Cuentas por pagar','Pasivo'),
 (c,'2.1.02','IVA por pagar','Pasivo'),
 (c,'4.1.01','Ventas','Ingreso'),
 (c,'5.1.01','Costo de ventas','Costo'),
 (c,'6.1.01','Compras / Gastos','Gasto')
 on conflict(company_id,code) do update set name=excluded.name,account_type=excluded.account_type,active=true;
end $$;

create or replace function atlas_post_journal(p_reference text,p_description text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare c uuid:=current_company_id(); e uuid:=gen_random_uuid(); l jsonb; d numeric:=0; h numeric:=0;
begin
 if c is null then raise exception 'Empresa no disponible'; end if;
 for l in select * from jsonb_array_elements(p_lines) loop
  d:=d+coalesce((l->>'debit')::numeric,0); h:=h+coalesce((l->>'credit')::numeric,0);
 end loop;
 if round(d,2)<>round(h,2) then raise exception 'Asiento descuadrado'; end if;
 insert into journal_entries(id,company_id,reference,description) values(e,c,p_reference,p_description);
 for l in select * from jsonb_array_elements(p_lines) loop
  insert into journal_lines(journal_entry_id,account_id,debit,credit,description)
  values(e,(l->>'account_id')::uuid,coalesce((l->>'debit')::numeric,0),coalesce((l->>'credit')::numeric,0),coalesce(l->>'description',''));
 end loop;
 return e;
end $$;

-- RLS: lectura por empresa; operaciones críticas se escriben mediante RPC.
alter table companies enable row level security;
alter table roles enable row level security; alter table role_permissions enable row level security;
alter table profiles enable row level security; alter table branches enable row level security;
alter table user_branch_access enable row level security; alter table customers enable row level security;
alter table suppliers enable row level security; alter table products enable row level security;
alter table inventory enable row level security; alter table inventory_movements enable row level security;
alter table exchange_rates enable row level security; alter table payment_methods enable row level security;
alter table cash_accounts enable row level security; alter table sales enable row level security;
alter table sale_items enable row level security; alter table purchases enable row level security;
alter table purchase_items enable row level security; alter table receivables enable row level security;
alter table payables enable row level security; alter table cash_movements enable row level security;
alter table expenses enable row level security; alter table quotations enable row level security;
alter table quotation_items enable row level security; alter table stock_transfers enable row level security;
alter table sales_returns enable row level security; alter table chart_of_accounts enable row level security;
alter table journal_entries enable row level security; alter table journal_lines enable row level security;
alter table audit_log enable row level security; alter table app_settings enable row level security;

create policy company_self_read on companies for select using(id=current_company_id());
create policy branches_read on branches for select using(company_id=current_company_id() and can_access_branch(id));
create policy customers_read on customers for select using(company_id=current_company_id());
create policy suppliers_read on suppliers for select using(company_id=current_company_id());
create policy products_read on products for select using(company_id=current_company_id());
create policy inventory_read on inventory for select using(company_id=current_company_id() and can_access_branch(branch_id));
create policy rates_read on exchange_rates for select using(company_id=current_company_id());
create policy cash_accounts_read on cash_accounts for select using(company_id=current_company_id());
create policy sales_read on sales for select using(company_id=current_company_id() and can_access_branch(branch_id));
create policy purchases_read on purchases for select using(company_id=current_company_id() and can_access_branch(branch_id));
create policy receivables_read on receivables for select using(company_id=current_company_id());
create policy payables_read on payables for select using(company_id=current_company_id());
create policy expenses_read on expenses for select using(company_id=current_company_id());
create policy returns_read on sales_returns for select using(company_id=current_company_id());
create policy audit_read on audit_log for select using(company_id=current_company_id() and has_permission('audit'));
create policy accounts_read on chart_of_accounts for select using(company_id=current_company_id() and has_permission('accounting'));
create policy entries_read on journal_entries for select using(company_id=current_company_id() and has_permission('accounting'));
create policy lines_read on journal_lines for select using(has_permission('accounting') and exists(
 select 1 from journal_entries e where e.id=journal_entry_id and e.company_id=current_company_id()
));

-- Views contables con seguridad del usuario invocador.
create or replace view atlas_trial_balance with (security_invoker=true) as
select a.company_id,a.id account_id,a.code,a.name,a.account_type,
 coalesce(sum(l.debit),0) debit,coalesce(sum(l.credit),0) credit,
 coalesce(sum(l.debit-l.credit),0) balance
from chart_of_accounts a
left join journal_lines l on l.account_id=a.id
group by a.company_id,a.id,a.code,a.name,a.account_type;

create or replace view atlas_general_ledger with (security_invoker=true) as
select e.company_id,e.entry_date,e.reference,e.description entry_description,
 a.code,a.name,l.debit,l.credit,l.description line_description
from journal_entries e
join journal_lines l on l.journal_entry_id=e.id
join chart_of_accounts a on a.id=l.account_id;

revoke all on function atlas_post_journal(text,text,jsonb) from public;
revoke all on function atlas_write_audit(text,text,jsonb) from public;
grant execute on function current_company_id() to authenticated;
grant execute on function has_permission(text) to authenticated;
grant execute on function can_access_branch(uuid) to authenticated;
grant execute on function atlas_guard_permission(text) to authenticated;
grant execute on function atlas_seed_chart_of_accounts() to authenticated;


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


-- ===== FASE 11: CONTABILIDAD Y REPORTES FINANCIEROS =====

-- Cuentas base de ATLAS por empresa. Se pueden ejecutar varias veces.
create or replace function public.atlas_seed_chart_of_accounts()
returns void language plpgsql security definer set search_path=public as $$
declare v_company uuid:=public.current_company_id();
begin
 if v_company is null then raise exception 'Empresa no disponible'; end if;
 insert into chart_of_accounts(company_id,code,name,account_type) values
 (v_company,'1.1.01','Caja y bancos','Activo'),
 (v_company,'1.1.02','Cuentas por cobrar','Activo'),
 (v_company,'1.1.03','Inventario','Activo'),
 (v_company,'1.1.04','IVA crédito fiscal','Activo'),
 (v_company,'2.1.01','Cuentas por pagar','Pasivo'),
 (v_company,'2.1.02','IVA por pagar','Pasivo'),
 (v_company,'4.1.01','Ventas','Ingreso'),
 (v_company,'5.1.01','Costo de ventas','Costo'),
 (v_company,'5.2.01','Compras / Gastos','Gasto')
 on conflict(company_id,code) do update
 set name=excluded.name,account_type=excluded.account_type,active=true;
end $$;

grant execute on function public.atlas_seed_chart_of_accounts() to authenticated;

create or replace view public.atlas_trial_balance as
select
 a.company_id,a.id as account_id,a.code,a.name,a.account_type,
 coalesce(sum(l.debit),0)::numeric(18,2) as debit,
 coalesce(sum(l.credit),0)::numeric(18,2) as credit,
 case when a.account_type in ('Activo','Costo','Gasto')
      then coalesce(sum(l.debit-l.credit),0)
      else coalesce(sum(l.credit-l.debit),0)
 end::numeric(18,2) as balance
from chart_of_accounts a
left join journal_lines l on l.account_id=a.id
left join journal_entries e on e.id=l.journal_entry_id and e.status='Contabilizado'
where a.active=true
group by a.company_id,a.id,a.code,a.name,a.account_type;

create or replace view public.atlas_general_ledger as
select
 e.company_id,e.entry_date,e.reference,e.description,e.status,
 a.code,a.name as account_name,a.account_type,l.debit,l.credit
from journal_entries e
join journal_lines l on l.journal_entry_id=e.id
join chart_of_accounts a on a.id=l.account_id;

create or replace function public.atlas_financial_summary()
returns jsonb language sql stable security definer set search_path=public as $$
 with b as (
  select * from public.atlas_trial_balance where company_id=public.current_company_id()
 )
 select jsonb_build_object(
  'cash',coalesce((select balance from b where name='Caja y bancos'),0),
  'receivables',coalesce((select balance from b where name='Cuentas por cobrar'),0),
  'inventory',coalesce((select balance from b where name='Inventario'),0),
  'payables',coalesce((select balance from b where name='Cuentas por pagar'),0),
  'sales',coalesce((select balance from b where name='Ventas'),0),
  'cogs',coalesce((select balance from b where name='Costo de ventas'),0),
  'expenses',coalesce((select balance from b where name='Compras / Gastos'),0),
  'vat_payable',coalesce((select balance from b where name='IVA por pagar'),0),
  'vat_credit',coalesce((select balance from b where name='IVA crédito fiscal'),0),
  'profit',
    coalesce((select balance from b where name='Ventas'),0)
    -coalesce((select balance from b where name='Costo de ventas'),0)
    -coalesce((select balance from b where name='Compras / Gastos'),0)
 )
$$;

grant execute on function public.atlas_create_sale(uuid,uuid,text,uuid,jsonb) to authenticated;
grant execute on function public.atlas_create_purchase(uuid,uuid,text,uuid,uuid,numeric,numeric) to authenticated;
grant execute on function public.atlas_collect_receivable(uuid,numeric,uuid) to authenticated;
grant execute on function public.atlas_pay_payable(uuid,numeric,uuid) to authenticated;
grant execute on function public.atlas_transfer_stock(uuid,uuid,uuid,numeric) to authenticated;
grant execute on function public.atlas_create_expense(uuid,text,text,numeric,text) to authenticated;
grant execute on function public.atlas_return_sale(uuid,uuid,numeric) to authenticated;
