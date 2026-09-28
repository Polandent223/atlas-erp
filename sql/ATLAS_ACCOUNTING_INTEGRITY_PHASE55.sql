-- ATLAS Fase 55 — Integridad contable transaccional
-- Ejecutar después de ATLAS_TRANSACTIONAL_RPCS_PHASE45.sql.
-- Objetivo: que venta, compra, cobro y pago creen su asiento contable dentro
-- de la misma transacción PostgreSQL. Si el asiento falla, toda la operación revierte.

create or replace function public.atlas_post_journal(
 p_reference text,
 p_description text,
 p_lines jsonb
) returns uuid
language plpgsql security definer
set search_path=public
as $$
declare
 cid uuid:=public.current_company_id();
 eid uuid:=gen_random_uuid();
 l jsonb; d numeric:=0; c numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then
   raise exception 'Asiento contable incompleto';
 end if;
 for l in select value from jsonb_array_elements(p_lines) loop
   if coalesce((l->>'debit')::numeric,0)<0 or coalesce((l->>'credit')::numeric,0)<0 then
     raise exception 'Importe contable inválido';
   end if;
   d:=d+coalesce((l->>'debit')::numeric,0);
   c:=c+coalesce((l->>'credit')::numeric,0);
 end loop;
 if abs(d-c)>0.0001 or d<=0 then raise exception 'Asiento contable desbalanceado'; end if;

 insert into public.journal_entries(id,company_id,reference,description)
 values(eid,cid,p_reference,p_description);

 for l in select value from jsonb_array_elements(p_lines) loop
   if coalesce((l->>'debit')::numeric,0)>0 or coalesce((l->>'credit')::numeric,0)>0 then
     insert into public.journal_lines(entry_id,account_code,description,debit,credit)
     values(eid,l->>'account_code',coalesce(l->>'description',p_description),
       coalesce((l->>'debit')::numeric,0),coalesce((l->>'credit')::numeric,0));
   end if;
 end loop;
 return eid;
end $$;

revoke all on function public.atlas_post_journal(text,text,jsonb) from public;
grant execute on function public.atlas_post_journal(text,text,jsonb) to authenticated;

-- Envolturas contables: se ejecutan en la misma transacción que el RPC operacional.
create or replace function public.atlas_post_sale_accounting(
 p_reference text,p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cost numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare lines jsonb:='[]'::jsonb; due numeric:=p_total-p_paid;
begin
 if p_total<=0 or p_paid<0 or due<0 or p_cost<0 then raise exception 'Valores contables de venta inválidos'; end if;
 if p_paid>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.01','debit',p_paid,'credit',0,'description','Cobro de venta')); end if;
 if due>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.02','debit',due,'credit',0,'description','Cuenta por cobrar')); end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_code','4.1.01','debit',0,'credit',p_subtotal,'description','Ingreso por venta'));
 if p_tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2.1.02','debit',0,'credit',p_tax,'description','IVA por pagar')); end if;
 if p_cost>0 then
   lines:=lines||jsonb_build_array(
    jsonb_build_object('account_code','5.1.01','debit',p_cost,'credit',0,'description','Costo de ventas'),
    jsonb_build_object('account_code','1.1.03','debit',0,'credit',p_cost,'description','Salida de inventario'));
 end if;
 return public.atlas_post_journal(p_reference,'Venta '||p_reference,lines);
end $$;

create or replace function public.atlas_post_purchase_accounting(
 p_reference text,p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare lines jsonb:='[]'::jsonb; due numeric:=p_total-p_paid;
begin
 if p_total<=0 or p_paid<0 or due<0 then raise exception 'Valores contables de compra inválidos'; end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.03','debit',p_subtotal,'credit',0,'description','Entrada de inventario'));
 if p_tax>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.04','debit',p_tax,'credit',0,'description','IVA crédito fiscal')); end if;
 if p_paid>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_paid,'description','Pago de compra')); end if;
 if due>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_code','2.1.01','debit',0,'credit',due,'description','Cuenta por pagar')); end if;
 return public.atlas_post_journal(p_reference,'Compra '||p_reference,lines);
end $$;

create or replace function public.atlas_post_collection_accounting(p_reference text,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if p_amount<=0 then raise exception 'Monto de cobro inválido'; end if;
 return public.atlas_post_journal(p_reference,'Cobro CxC '||p_reference,jsonb_build_array(
  jsonb_build_object('account_code','1.1.01','debit',p_amount,'credit',0,'description','Entrada a caja/banco'),
  jsonb_build_object('account_code','1.1.02','debit',0,'credit',p_amount,'description','Disminución CxC')));
end $$;

create or replace function public.atlas_post_payment_accounting(p_reference text,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
begin
 if p_amount<=0 then raise exception 'Monto de pago inválido'; end if;
 return public.atlas_post_journal(p_reference,'Pago CxP '||p_reference,jsonb_build_array(
  jsonb_build_object('account_code','2.1.01','debit',p_amount,'credit',0,'description','Disminución CxP'),
  jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_amount,'description','Salida de caja/banco')));
end $$;

revoke all on function public.atlas_post_sale_accounting(text,numeric,numeric,numeric,numeric,numeric) from public;
revoke all on function public.atlas_post_purchase_accounting(text,numeric,numeric,numeric,numeric) from public;
revoke all on function public.atlas_post_collection_accounting(text,numeric) from public;
revoke all on function public.atlas_post_payment_accounting(text,numeric) from public;

-- Estas funciones son auxiliares internas de los RPC SECURITY DEFINER.
-- No se concede EXECUTE directo a authenticated.


-- RPCs Fase 45 redefinidos para integrar la contabilidad Fase 55.
-- ATLAS Fase 45 — Operaciones transaccionales críticas
-- Ejecutar después de Fase 32 + Fase 44.
-- Las operaciones principales se procesan dentro de una sola transacción PostgreSQL.

create extension if not exists pgcrypto;

-- Venta atómica: número, validación de sucursal, stock, venta, líneas, caja/CxC y auditoría.
create or replace function public.atlas_create_sale(
 p_branch uuid,
 p_customer uuid,
 p_currency text,
 p_exchange_rate numeric,
 p_subtotal numeric,
 p_tax numeric,
 p_total numeric,
 p_paid numeric,
 p_cash_account uuid,
 p_items jsonb,
 p_prefix text default 'V-'
) returns jsonb
language plpgsql security definer
set search_path=public
as $$
declare
 cid uuid:=public.current_company_id();
 sid uuid:=gen_random_uuid();
 n text;
 item jsonb;
 pid uuid;
 q numeric;
 price numeric;
 cost numeric;
 available numeric;
 due numeric;
 total_cost numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('sales.operate') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_total<0 or p_paid<0 or p_paid>p_total then raise exception 'Totales inválidos'; end if;
 if p_exchange_rate<=0 then raise exception 'Tasa inválida'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Venta sin productos'; end if;
 if p_customer is not null and not exists(select 1 from public.customers where id=p_customer and company_id=cid) then raise exception 'Cliente inválido'; end if;
 if p_paid>0 and (p_cash_account is null or not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true)) then raise exception 'Cuenta de caja inválida'; end if;

 n:=public.next_document_number('SALE',p_prefix);

 -- Bloquea filas de inventario antes de descontar.
 for item in select value from jsonb_array_elements(p_items)
 loop
   pid:=(item->>'product_id')::uuid;
   q:=(item->>'qty')::numeric;
   price:=coalesce((item->>'unit_price')::numeric,0);
   if q<=0 or price<0 then raise exception 'Línea de venta inválida'; end if;
   if not exists(select 1 from public.products where id=pid and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
   select stock-reserved into available from public.inventory
    where company_id=cid and branch_id=p_branch and product_id=pid for update;
   if available is null or available<q then raise exception 'Stock insuficiente para producto %',pid; end if;
 end loop;

 insert into public.sales(id,company_id,branch_id,customer_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(sid,cid,p_branch,p_customer,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,
        case when upper(coalesce(p_currency,'USD'))='USD' then p_total else p_total/p_exchange_rate end,auth.uid());

 for item in select value from jsonb_array_elements(p_items)
 loop
   pid:=(item->>'product_id')::uuid;q:=(item->>'qty')::numeric;price:=coalesce((item->>'unit_price')::numeric,0);
   select coalesce(cost,0) into cost from public.products where id=pid and company_id=cid;
   total_cost:=total_cost+(cost*q);
   insert into public.sale_items(sale_id,product_id,qty,unit_price,unit_cost) values(sid,pid,q,price,cost);
   update public.inventory set stock=stock-q where company_id=cid and branch_id=p_branch and product_id=pid;
 end loop;

 if p_paid>0 then
   update public.cash_accounts set balance=balance+p_paid where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,p_cash_account,'IN',p_paid,upper(coalesce(p_currency,'USD')),n,'Cobro de venta',auth.uid());
 end if;

 due:=p_total-p_paid;
 if due>0 then
   if p_customer is null then raise exception 'Una venta con saldo pendiente requiere cliente'; end if;
   insert into public.receivables(company_id,customer_id,sale_id,reference,total,balance,status)
   values(cid,p_customer,sid,n,p_total,due,'OPEN');
 end if;

 perform public.atlas_post_sale_accounting(n,p_subtotal,p_tax,p_total,p_paid,total_cost);

 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','SALE',sid::text,jsonb_build_object('number',n,'total',p_total,'paid',p_paid,'accounted',true));

 return jsonb_build_object('id',sid,'number',n,'balance',due);
end $$;

revoke all on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
grant execute on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;

-- Compra atómica: inventario + caja/CxP + auditoría.
create or replace function public.atlas_create_purchase(
 p_branch uuid,
 p_supplier uuid,
 p_currency text,
 p_exchange_rate numeric,
 p_subtotal numeric,
 p_tax numeric,
 p_total numeric,
 p_paid numeric,
 p_cash_account uuid,
 p_items jsonb,
 p_prefix text default 'C-'
) returns jsonb
language plpgsql security definer
set search_path=public
as $$
declare
 cid uuid:=public.current_company_id();
 pidoc uuid:=gen_random_uuid();
 n text; item jsonb; pid uuid; q numeric; cost numeric; due numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('purchases.operate') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_total<0 or p_paid<0 or p_paid>p_total or p_exchange_rate<=0 then raise exception 'Totales inválidos'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Compra sin productos'; end if;
 if p_supplier is not null and not exists(select 1 from public.suppliers where id=p_supplier and company_id=cid) then raise exception 'Proveedor inválido'; end if;
 if p_paid>0 and (p_cash_account is null or not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true)) then raise exception 'Cuenta de caja inválida'; end if;

 n:=public.next_document_number('PURCHASE',p_prefix);

 insert into public.purchases(id,company_id,branch_id,supplier_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(pidoc,cid,p_branch,p_supplier,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,
        case when upper(coalesce(p_currency,'USD'))='USD' then p_total else p_total/p_exchange_rate end,auth.uid());

 for item in select value from jsonb_array_elements(p_items)
 loop
   pid:=(item->>'product_id')::uuid;q:=(item->>'qty')::numeric;cost:=coalesce((item->>'unit_cost')::numeric,0);
   if q<=0 or cost<0 then raise exception 'Línea de compra inválida'; end if;
   if not exists(select 1 from public.products where id=pid and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
   insert into public.purchase_items(purchase_id,product_id,qty,unit_cost) values(pidoc,pid,q,cost);
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
    values(cid,p_branch,pid,q,0)
    on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 end loop;

 if p_paid>0 then
   update public.cash_accounts set balance=balance-p_paid where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,p_cash_account,'OUT',p_paid,upper(coalesce(p_currency,'USD')),n,'Pago de compra',auth.uid());
 end if;

 due:=p_total-p_paid;
 if due>0 then
   if p_supplier is null then raise exception 'Una compra con saldo pendiente requiere proveedor'; end if;
   insert into public.payables(company_id,supplier_id,purchase_id,reference,total,balance,status)
   values(cid,p_supplier,pidoc,n,p_total,due,'OPEN');
 end if;

 perform public.atlas_post_purchase_accounting(n,p_subtotal,p_tax,p_total,p_paid);

 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','PURCHASE',pidoc::text,jsonb_build_object('number',n,'total',p_total,'paid',p_paid,'accounted',true));

 return jsonb_build_object('id',pidoc,'number',n,'balance',due);
end $$;

revoke all on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
grant execute on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;

-- Cobro de CxC atómico.
create or replace function public.atlas_collect_receivable(p_receivable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.receivables%rowtype; newbal numeric;
begin
 if not public.has_permission('ar.manage') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.receivables where id=p_receivable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Cobro inválido'; end if;
 if not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true) then raise exception 'Cuenta inválida'; end if;
 newbal:=r.balance-p_amount;
 update public.receivables set balance=newbal,status=case when newbal=0 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance+p_amount where id=p_cash_account;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'IN',p_amount,'USD',r.reference,'Cobro CxC',auth.uid());
 perform public.atlas_post_collection_accounting(r.reference,p_amount);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'COLLECT','RECEIVABLE',r.id::text,jsonb_build_object('amount',p_amount,'balance',newbal,'accounted',true));
 return jsonb_build_object('id',r.id,'balance',newbal);
end $$;
revoke all on function public.atlas_collect_receivable(uuid,numeric,uuid) from public;
grant execute on function public.atlas_collect_receivable(uuid,numeric,uuid) to authenticated;

-- Pago de CxP atómico.
create or replace function public.atlas_pay_payable(p_payable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.payables%rowtype; newbal numeric;
begin
 if not public.has_permission('ap.manage') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.payables where id=p_payable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Pago inválido'; end if;
 if not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true) then raise exception 'Cuenta inválida'; end if;
 newbal:=r.balance-p_amount;
 update public.payables set balance=newbal,status=case when newbal=0 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance-p_amount where id=p_cash_account;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'OUT',p_amount,'USD',r.reference,'Pago CxP',auth.uid());
 perform public.atlas_post_payment_accounting(r.reference,p_amount);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'PAY','PAYABLE',r.id::text,jsonb_build_object('amount',p_amount,'balance',newbal,'accounted',true));
 return jsonb_build_object('id',r.id,'balance',newbal);
end $$;
revoke all on function public.atlas_pay_payable(uuid,numeric,uuid) from public;
grant execute on function public.atlas_pay_payable(uuid,numeric,uuid) to authenticated;

-- Contabilidad: cada asiento debe quedar balanceado al finalizar la transacción.
create or replace function public.enforce_balanced_journal()
returns trigger language plpgsql as $$
declare eid uuid; d numeric; c numeric;
begin
 eid:=coalesce(new.entry_id,old.entry_id);
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into d,c from public.journal_lines where entry_id=eid;
 if abs(d-c)>0.0001 then raise exception 'Asiento contable desbalanceado: débito %, crédito %',d,c; end if;
 return null;
end $$;

drop trigger if exists trg_balanced_journal on public.journal_lines;
create constraint trigger trg_balanced_journal
after insert or update or delete on public.journal_lines
deferrable initially deferred
for each row execute function public.enforce_balanced_journal();

-- Se elimina escritura directa a tablas núcleo para usuarios autenticados.
-- La aplicación debe usar los RPC anteriores.
revoke insert, update, delete on public.sales,public.sale_items,public.purchases,public.purchase_items from authenticated;
grant select on public.sales,public.sale_items,public.purchases,public.purchase_items to authenticated;
