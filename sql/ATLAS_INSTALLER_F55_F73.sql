-- ============================================================
-- ATLAS — INSTALADOR CONSOLIDADO F55 → F73
-- Base requerida: F32 + F44 ya instaladas.
-- Generado automáticamente desde las fases revisadas de la rama.
-- REGLA: ejecutar el archivo completo; no ejecutar fragmentos.
-- Toda la migración corre en una sola transacción.
-- ============================================================

begin;

-- Preflight estructural: aborta antes de modificar si falta la base esperada.
do $$
declare missing text[] := array[]::text[];
begin
  if to_regclass('public.companies') is null then missing:=array_append(missing,'companies'); end if;
  if to_regclass('public.profiles') is null then missing:=array_append(missing,'profiles'); end if;
  if to_regclass('public.branches') is null then missing:=array_append(missing,'branches'); end if;
  if to_regclass('public.products') is null then missing:=array_append(missing,'products'); end if;
  if to_regclass('public.inventory') is null then missing:=array_append(missing,'inventory'); end if;
  if to_regclass('public.cash_accounts') is null then missing:=array_append(missing,'cash_accounts'); end if;
  if to_regclass('public.sales') is null then missing:=array_append(missing,'sales'); end if;
  if to_regclass('public.purchases') is null then missing:=array_append(missing,'purchases'); end if;
  if to_regclass('public.receivables') is null then missing:=array_append(missing,'receivables'); end if;
  if to_regclass('public.payables') is null then missing:=array_append(missing,'payables'); end if;
  if to_regclass('public.document_counters') is null then missing:=array_append(missing,'document_counters'); end if;
  if to_regprocedure('public.current_company_id()') is null then missing:=array_append(missing,'current_company_id()'); end if;
  if to_regprocedure('public.has_permission(text)') is null then missing:=array_append(missing,'has_permission(text)'); end if;
  if to_regprocedure('public.can_access_branch(uuid)') is null then missing:=array_append(missing,'can_access_branch(uuid)'); end if;
  if cardinality(missing)>0 then
    raise exception 'ATLAS preflight falló. Falta base F32/F44: %', array_to_string(missing,', ');
  end if;
end $$;

-- ============================================================
-- BLOQUE 1/14: sql/ATLAS_TRANSACTIONAL_ACCOUNTING_PHASE55.sql
-- ============================================================
-- ATLAS Fase 55 — Integridad transaccional + contabilidad automática
-- Ejecutar DESPUÉS de Fase 45. Es idempotente.
-- Objetivo: venta, compra, cobro y pago dejan inventario/caja/deuda/contabilidad/auditoría
-- dentro de la MISMA transacción PostgreSQL.

create extension if not exists pgcrypto;

-- Plan mínimo requerido por el motor. No elimina ni reemplaza cuentas existentes.
insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,x.code,x.name,x.type,true
from public.companies c
cross join (values
 ('1.1.01','Caja y bancos','Activo'),
 ('1.1.02','Cuentas por cobrar','Activo'),
 ('1.1.03','Inventario','Activo'),
 ('1.1.04','IVA crédito fiscal','Activo'),
 ('2.1.01','Cuentas por pagar','Pasivo'),
 ('2.1.02','IVA por pagar','Pasivo'),
 ('4.1.01','Ventas','Ingreso'),
 ('5.1.01','Costo de ventas','Costo')
) as x(code,name,type)
on conflict(company_id,code) do nothing;

create or replace function public.atlas_post_journal(
 p_company uuid,p_reference text,p_description text,p_lines jsonb
) returns uuid
language plpgsql security definer set search_path=public as $$
declare eid uuid:=gen_random_uuid(); l jsonb; d numeric:=0; c numeric:=0;
begin
 if p_company is null or p_company<>public.current_company_id() then raise exception 'Empresa inválida'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Asiento sin líneas'; end if;
 for l in select value from jsonb_array_elements(p_lines) loop
   d:=d+coalesce((l->>'debit')::numeric,0); c:=c+coalesce((l->>'credit')::numeric,0);
 end loop;
 if abs(d-c)>0.0001 then raise exception 'Asiento desbalanceado: débito %, crédito %',d,c; end if;
 insert into public.journal_entries(id,company_id,reference,description) values(eid,p_company,p_reference,p_description);
 for l in select value from jsonb_array_elements(p_lines) loop
   if coalesce((l->>'debit')::numeric,0)>0 or coalesce((l->>'credit')::numeric,0)>0 then
    if not exists(select 1 from public.accounting_accounts a where a.company_id=p_company and a.code=l->>'account_code' and a.active=true)
      then raise exception 'Cuenta contable % inexistente o inactiva',l->>'account_code'; end if;
    insert into public.journal_lines(entry_id,account_code,description,debit,credit)
    values(eid,l->>'account_code',coalesce(l->>'description',p_description),coalesce((l->>'debit')::numeric,0),coalesce((l->>'credit')::numeric,0));
   end if;
 end loop;
 return eid;
end $$;
revoke all on function public.atlas_post_journal(uuid,text,text,jsonb) from public;

-- Venta atómica. El frontend F53 entrega importes base USD; p_currency identifica
-- la moneda documental. p_exchange_rate se conserva como snapshot informativo.
create or replace function public.atlas_create_sale(
 p_branch uuid,p_customer uuid,p_currency text,p_exchange_rate numeric,
 p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cash_account uuid,
 p_items jsonb,p_prefix text default 'V-'
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); sid uuid:=gen_random_uuid(); n text; item jsonb;
 pid uuid; q numeric; price numeric; cost numeric; available numeric; due numeric; cogs numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('sales.operate') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_subtotal<0 or p_tax<0 or p_total<0 or p_paid<0 or p_paid>p_total then raise exception 'Totales inválidos'; end if;
 if abs((p_subtotal+p_tax)-p_total)>0.02 then raise exception 'Total de venta inconsistente'; end if;
 if p_exchange_rate<=0 then raise exception 'Tasa inválida'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Venta sin productos'; end if;
 if p_customer is not null and not exists(select 1 from public.customers where id=p_customer and company_id=cid and active=true) then raise exception 'Cliente inválido'; end if;
 if p_paid>0 and (p_cash_account is null or not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true)) then raise exception 'Cuenta de caja inválida'; end if;
 n:=public.next_document_number('SALE',p_prefix);
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; price:=coalesce((item->>'unit_price')::numeric,0);
   if q<=0 or price<0 then raise exception 'Línea de venta inválida'; end if;
   if not exists(select 1 from public.products where id=pid and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
   select stock-reserved into available from public.inventory where company_id=cid and branch_id=p_branch and product_id=pid for update;
   if available is null or available<q then raise exception 'Stock insuficiente para producto %',pid; end if;
 end loop;
 insert into public.sales(id,company_id,branch_id,customer_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(sid,cid,p_branch,p_customer,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,p_total,auth.uid());
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; price:=coalesce((item->>'unit_price')::numeric,0);
   select coalesce(cost,0) into cost from public.products where id=pid and company_id=cid;
   cogs:=cogs+(cost*q);
   insert into public.sale_items(sale_id,product_id,qty,unit_price,unit_cost) values(sid,pid,q,price,cost);
   update public.inventory set stock=stock-q where company_id=cid and branch_id=p_branch and product_id=pid;
 end loop;
 if p_paid>0 then
   update public.cash_accounts set balance=balance+p_paid where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   select cid,p_cash_account,'IN',p_paid,ca.currency,n,'Cobro de venta',auth.uid() from public.cash_accounts ca where ca.id=p_cash_account;
 end if;
 due:=p_total-p_paid;
 if due>0 then
   if p_customer is null then raise exception 'Una venta con saldo pendiente requiere cliente'; end if;
   insert into public.receivables(company_id,customer_id,sale_id,reference,total,balance,status)
   values(cid,p_customer,sid,n,p_total,due,'OPEN');
 end if;
 perform public.atlas_post_journal(cid,n,'Venta',jsonb_build_array(
   jsonb_build_object('account_code',case when p_paid>0 then '1.1.01' else '1.1.02' end,'debit',case when p_paid>0 then p_paid else due end,'credit',0),
   jsonb_build_object('account_code','1.1.02','debit',case when p_paid>0 then due else 0 end,'credit',0),
   jsonb_build_object('account_code','4.1.01','debit',0,'credit',p_subtotal),
   jsonb_build_object('account_code','2.1.02','debit',0,'credit',p_tax),
   jsonb_build_object('account_code','5.1.01','debit',cogs,'credit',0),
   jsonb_build_object('account_code','1.1.03','debit',0,'credit',cogs)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','SALE',sid::text,jsonb_build_object('number',n,'total',p_total,'paid',p_paid,'due',due,'cogs',cogs));
 return jsonb_build_object('id',sid,'number',n,'balance',due);
end $$;
revoke all on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
grant execute on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;

-- Compra atómica con asiento automático.
create or replace function public.atlas_create_purchase(
 p_branch uuid,p_supplier uuid,p_currency text,p_exchange_rate numeric,
 p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cash_account uuid,
 p_items jsonb,p_prefix text default 'C-'
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); pidoc uuid:=gen_random_uuid(); n text; item jsonb; pid uuid; q numeric; cost numeric; due numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('purchases.operate') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_subtotal<0 or p_tax<0 or p_total<0 or p_paid<0 or p_paid>p_total or p_exchange_rate<=0 then raise exception 'Totales inválidos'; end if;
 if abs((p_subtotal+p_tax)-p_total)>0.02 then raise exception 'Total de compra inconsistente'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Compra sin productos'; end if;
 if p_supplier is not null and not exists(select 1 from public.suppliers where id=p_supplier and company_id=cid and active=true) then raise exception 'Proveedor inválido'; end if;
 if p_paid>0 and (p_cash_account is null or not exists(select 1 from public.cash_accounts where id=p_cash_account and company_id=cid and active=true)) then raise exception 'Cuenta de caja inválida'; end if;
 n:=public.next_document_number('PURCHASE',p_prefix);
 insert into public.purchases(id,company_id,branch_id,supplier_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(pidoc,cid,p_branch,p_supplier,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,p_total,auth.uid());
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; cost:=coalesce((item->>'unit_cost')::numeric,0);
   if q<=0 or cost<0 then raise exception 'Línea de compra inválida'; end if;
   if not exists(select 1 from public.products where id=pid and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
   insert into public.purchase_items(purchase_id,product_id,qty,unit_cost) values(pidoc,pid,q,cost);
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved) values(cid,p_branch,pid,q,0)
   on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 end loop;
 if p_paid>0 then
   update public.cash_accounts set balance=balance-p_paid where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   select cid,p_cash_account,'OUT',p_paid,ca.currency,n,'Pago de compra',auth.uid() from public.cash_accounts ca where ca.id=p_cash_account;
 end if;
 due:=p_total-p_paid;
 if due>0 then
   if p_supplier is null then raise exception 'Una compra con saldo pendiente requiere proveedor'; end if;
   insert into public.payables(company_id,supplier_id,purchase_id,reference,total,balance,status) values(cid,p_supplier,pidoc,n,p_total,due,'OPEN');
 end if;
 perform public.atlas_post_journal(cid,n,'Compra de mercancía',jsonb_build_array(
   jsonb_build_object('account_code','1.1.03','debit',p_subtotal,'credit',0),
   jsonb_build_object('account_code','1.1.04','debit',p_tax,'credit',0),
   jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_paid),
   jsonb_build_object('account_code','2.1.01','debit',0,'credit',due)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','PURCHASE',pidoc::text,jsonb_build_object('number',n,'total',p_total,'paid',p_paid,'due',due));
 return jsonb_build_object('id',pidoc,'number',n,'balance',due);
end $$;
revoke all on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
grant execute on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;

-- Cobro CxC: deuda + caja + asiento + auditoría en una sola transacción.
create or replace function public.atlas_collect_receivable(p_receivable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.receivables%rowtype; newbal numeric; cur text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('ar.manage') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.receivables where id=p_receivable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Cobro inválido'; end if;
 select currency into cur from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
 if cur is null then raise exception 'Cuenta inválida'; end if;
 newbal:=r.balance-p_amount;
 update public.receivables set balance=newbal,status=case when newbal=0 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance+p_amount where id=p_cash_account and company_id=cid;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'IN',p_amount,cur,r.reference,'Cobro CxC',auth.uid());
 perform public.atlas_post_journal(cid,'COBRO-'||r.reference,'Cobro de cuenta por cobrar',jsonb_build_array(
   jsonb_build_object('account_code','1.1.01','debit',p_amount,'credit',0),
   jsonb_build_object('account_code','1.1.02','debit',0,'credit',p_amount)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'COLLECT','RECEIVABLE',r.id::text,jsonb_build_object('amount',p_amount,'balance',newbal));
 return jsonb_build_object('id',r.id,'balance',newbal);
end $$;
revoke all on function public.atlas_collect_receivable(uuid,numeric,uuid) from public;
grant execute on function public.atlas_collect_receivable(uuid,numeric,uuid) to authenticated;

-- Pago CxP: deuda + caja + asiento + auditoría en una sola transacción.
create or replace function public.atlas_pay_payable(p_payable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.payables%rowtype; newbal numeric; cur text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not public.has_permission('ap.manage') and not public.has_permission('*') then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.payables where id=p_payable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Pago inválido'; end if;
 select currency into cur from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
 if cur is null then raise exception 'Cuenta inválida'; end if;
 newbal:=r.balance-p_amount;
 update public.payables set balance=newbal,status=case when newbal=0 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance-p_amount where id=p_cash_account and company_id=cid;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'OUT',p_amount,cur,r.reference,'Pago CxP',auth.uid());
 perform public.atlas_post_journal(cid,'PAGO-'||r.reference,'Pago de cuenta por pagar',jsonb_build_array(
   jsonb_build_object('account_code','2.1.01','debit',p_amount,'credit',0),
   jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_amount)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'PAY','PAYABLE',r.id::text,jsonb_build_object('amount',p_amount,'balance',newbal));
 return jsonb_build_object('id',r.id,'balance',newbal);
end $$;
revoke all on function public.atlas_pay_payable(uuid,numeric,uuid) from public;
grant execute on function public.atlas_pay_payable(uuid,numeric,uuid) to authenticated;

-- Mantiene protegidas las tablas núcleo: las escrituras pasan por RPC.
revoke insert,update,delete on public.sales,public.sale_items,public.purchases,public.purchase_items from authenticated;
revoke insert,update,delete on public.journal_entries,public.journal_lines from authenticated;
grant select on public.journal_entries,public.journal_lines to authenticated;

-- ============================================================
-- BLOQUE 2/14: sql/ATLAS_MULTICURRENCY_CONTRACT_PHASE56.sql
-- ============================================================
-- ATLAS Fase 56 — Contrato multi-moneda seguro
-- Complementa F55. No reemplaza importes contables base; evita mezclar importes USD con saldos de caja en otra moneda.

create or replace function public.atlas_fx_amount(
 p_base_amount numeric,
 p_account_currency text,
 p_document_currency text,
 p_exchange_rate numeric
) returns numeric
language plpgsql immutable
as $$
declare ac text:=upper(coalesce(p_account_currency,'USD')); dc text:=upper(coalesce(p_document_currency,'USD'));
begin
 if p_base_amount is null or p_base_amount<0 then raise exception 'Importe base inválido'; end if;
 if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Tasa inválida'; end if;
 -- ATLAS F53/F55 usa USD como importe de referencia contable.
 -- Si la cuenta está en USD, el movimiento es exactamente el importe base.
 if ac='USD' then return round(p_base_amount,4); end if;
 -- Si la cuenta está en la misma moneda documental no-USD, convierte el importe base con el snapshot de tasa.
 if ac=dc and dc<>'USD' then return round(p_base_amount*p_exchange_rate,4); end if;
 -- No se permite inferir cruces (ej. EUR documento -> VES cuenta) con una sola tasa.
 raise exception 'Conversión no soportada: documento %, cuenta %. Se requiere tasa cruzada explícita.',dc,ac;
end $$;

revoke all on function public.atlas_fx_amount(numeric,text,text,numeric) from public;
grant execute on function public.atlas_fx_amount(numeric,text,text,numeric) to authenticated;

-- Verificador de integridad de configuración monetaria para diagnóstico previo a operación.
create or replace function public.atlas_currency_healthcheck()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare cid uuid:=public.current_company_id(); invalid_accounts int; invalid_rates int;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 select count(*) into invalid_accounts from public.cash_accounts
 where company_id=cid and active=true and (currency is null or btrim(currency)='');
 select count(*) into invalid_rates from public.exchange_rates
 where company_id=cid and (currency is null or btrim(currency)='' or rate<=0);
 return jsonb_build_object(
   'ok',invalid_accounts=0 and invalid_rates=0,
   'invalid_cash_accounts',invalid_accounts,
   'invalid_exchange_rates',invalid_rates,
   'reference_currency','USD',
   'rule','No cross-currency inference without explicit rate'
 );
end $$;
revoke all on function public.atlas_currency_healthcheck() from public;
grant execute on function public.atlas_currency_healthcheck() to authenticated;

-- ============================================================
-- BLOQUE 3/14: sql/ATLAS_OPERATIONS_HARDENING_PHASE57.sql
-- ============================================================
-- ATLAS Fase 57 — Operaciones remotas endurecidas
-- Compatible con esquema de producción F32/F44. Reemplaza RPC legacy de F13 que usaba columnas antiguas.

-- Campo operativo que la UI ya utiliza y que no existía en F44.
alter table public.expenses add column if not exists category text not null default 'General';

-- Cuenta contable de gastos operativos requerida.
insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'5.2.01','Gastos operativos','Gasto',true from public.companies c
on conflict(company_id,code) do nothing;

-- Transferencia de inventario: una sola transacción, contador atómico, auditoría.
create or replace function public.atlas_transfer_stock(
 p_product_id uuid,p_from_branch uuid,p_to_branch uuid,p_qty numeric
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); available numeric; n text; tid uuid:=gen_random_uuid();
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_qty is null or p_qty<=0 then raise exception 'Cantidad inválida'; end if;
 if p_from_branch=p_to_branch then raise exception 'Origen y destino deben ser distintos'; end if;
 if not public.can_access_branch(p_from_branch) or not public.can_access_branch(p_to_branch) then raise exception 'Sucursal no autorizada'; end if;
 if not exists(select 1 from public.products where id=p_product_id and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
 select stock-reserved into available from public.inventory
 where company_id=cid and branch_id=p_from_branch and product_id=p_product_id for update;
 if available is null or available<p_qty then raise exception 'Stock insuficiente'; end if;
 n:=public.next_document_number('STOCK_TRANSFER','TR-');
 update public.inventory set stock=stock-p_qty
 where company_id=cid and branch_id=p_from_branch and product_id=p_product_id;
 insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
 values(cid,p_to_branch,p_product_id,p_qty,0)
 on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 insert into public.stock_transfers(id,company_id,from_branch_id,to_branch_id,number,status,payload)
 values(tid,cid,p_from_branch,p_to_branch,n,'DONE',jsonb_build_object('product_id',p_product_id,'qty',p_qty));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','STOCK_TRANSFER',tid::text,jsonb_build_object('number',n,'product_id',p_product_id,'from',p_from_branch,'to',p_to_branch,'qty',p_qty));
 return jsonb_build_object('id',tid,'number',n,'qty',p_qty);
end $$;
revoke all on function public.atlas_transfer_stock(uuid,uuid,uuid,numeric) from public;
grant execute on function public.atlas_transfer_stock(uuid,uuid,uuid,numeric) to authenticated;

-- Gasto remoto: caja + gasto + contabilidad + auditoría atómicos.
-- Por seguridad F57 sólo permite registrar directamente contra una cuenta USD.
-- Otras monedas se habilitan cuando el frontend entregue snapshot FX explícito.
create or replace function public.atlas_create_expense(
 p_cash_account_id uuid,p_category text,p_description text,p_amount numeric,p_reference text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); eid uuid:=gen_random_uuid(); ref text; cur text; bal numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Monto inválido'; end if;
 if nullif(btrim(coalesce(p_description,'')),'') is null then raise exception 'Descripción requerida'; end if;
 select currency,balance into cur,bal from public.cash_accounts
 where id=p_cash_account_id and company_id=cid and active=true for update;
 if cur is null then raise exception 'Cuenta de caja inválida'; end if;
 if upper(cur)<>'USD' then raise exception 'Gasto multi-moneda requiere tasa explícita'; end if;
 if coalesce(bal,0)<p_amount then raise exception 'Saldo insuficiente'; end if;
 ref:=coalesce(nullif(btrim(p_reference),''),public.next_document_number('EXPENSE','G-'));
 insert into public.expenses(id,company_id,cash_account_id,category,description,amount,currency,reference,created_by)
 values(eid,cid,p_cash_account_id,coalesce(nullif(btrim(p_category),''),'General'),p_description,p_amount,'USD',ref,auth.uid());
 update public.cash_accounts set balance=balance-p_amount where id=p_cash_account_id and company_id=cid;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account_id,'OUT',p_amount,'USD',ref,p_description,auth.uid());
 perform public.atlas_post_journal(cid,ref,'Gasto: '||p_description,jsonb_build_array(
   jsonb_build_object('account_code','5.2.01','debit',p_amount,'credit',0),
   jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_amount)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','EXPENSE',eid::text,jsonb_build_object('reference',ref,'amount',p_amount,'category',p_category));
 return jsonb_build_object('id',eid,'reference',ref,'amount',p_amount);
end $$;
revoke all on function public.atlas_create_expense(uuid,text,text,numeric,text) from public;
grant execute on function public.atlas_create_expense(uuid,text,text,numeric,text) to authenticated;

-- ============================================================
-- BLOQUE 4/14: sql/ATLAS_RETURNS_PHASE58.sql
-- ============================================================
-- ATLAS Fase 58 / corrección F73 — Devolución de venta segura
-- Reemplaza la implementación legacy incompatible con sale_returns F44.
-- Devolución parcial por producto, reintegro de inventario, ajuste CxC/crédito cliente,
-- reverso contable y auditoría. No realiza reembolso de caja automático.

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'2.1.03','Créditos de clientes','Pasivo',true from public.companies c
on conflict(company_id,code) do nothing;

-- Conserva el valor original del crédito aunque luego se aplique parcialmente.
alter table public.customer_credits add column if not exists original_amount numeric(18,4);
update public.customer_credits set original_amount=balance where original_amount is null;
alter table public.customer_credits alter column original_amount set default 0;

create or replace function public.atlas_return_sale(
 p_sale_id uuid,p_product_id uuid,p_qty numeric
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); s public.sales%rowtype; li public.sale_items%rowtype;
 already numeric:=0; amount numeric:=0; tax_amount numeric:=0; subtotal_amount numeric:=0;
 cost_amount numeric:=0; rid uuid:=gen_random_uuid(); n text; ar public.receivables%rowtype;
 ar_apply numeric:=0; credit_amount numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_qty is null or p_qty<=0 then raise exception 'Cantidad inválida'; end if;
 select * into s from public.sales where id=p_sale_id and company_id=cid and status='ACTIVE' for update;
 if s.id is null then raise exception 'Venta activa no encontrada'; end if;
 if not public.can_access_branch(s.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 select * into li from public.sale_items where sale_id=s.id and product_id=p_product_id;
 if li.id is null then raise exception 'Producto no pertenece a la venta'; end if;
 select coalesce(sum(coalesce((r.payload->>'qty')::numeric,0)),0) into already
 from public.sale_returns r
 where r.company_id=cid and r.sale_id=s.id and r.payload->>'product_id'=p_product_id::text;
 if already+p_qty>li.qty then raise exception 'Cantidad devuelta supera la vendida'; end if;
 subtotal_amount:=round(p_qty*li.unit_price,4);
 tax_amount:=case when s.subtotal>0 then round(subtotal_amount*(s.tax/s.subtotal),4) else 0 end;
 amount:=subtotal_amount+tax_amount;
 cost_amount:=round(p_qty*coalesce(li.unit_cost,0),4);
 n:=public.next_document_number('SALE_RETURN','DV-');
 insert into public.sale_returns(id,company_id,sale_id,number,total,payload)
 values(rid,cid,s.id,n,amount,jsonb_build_object('product_id',p_product_id,'qty',p_qty,'subtotal',subtotal_amount,'tax',tax_amount,'cost',cost_amount,'currency','USD'));
 insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
 values(cid,s.branch_id,p_product_id,p_qty,0)
 on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 select * into ar from public.receivables where company_id=cid and sale_id=s.id and status<>'PAID' order by balance desc limit 1 for update;
 if ar.id is not null then
   ar_apply:=least(amount,ar.balance);
   update public.receivables set balance=balance-ar_apply,status=case when balance-ar_apply<=0.0001 then 'PAID' else 'OPEN' end where id=ar.id;
 end if;
 credit_amount:=round(amount-ar_apply,4);
 if credit_amount>0 then
   if s.customer_id is null then raise exception 'La devolución genera crédito pero la venta no tiene cliente'; end if;
   insert into public.customer_credits(company_id,customer_id,original_amount,balance,currency,reference)
   values(cid,s.customer_id,credit_amount,credit_amount,'USD',n);
 end if;
 update public.sale_returns set payload=payload||jsonb_build_object('ar_applied',ar_apply,'customer_credit',credit_amount) where id=rid;
 perform public.atlas_post_journal(cid,n,'Devolución de venta',jsonb_build_array(
   jsonb_build_object('account_code','4.1.01','debit',subtotal_amount,'credit',0),
   jsonb_build_object('account_code','2.1.02','debit',tax_amount,'credit',0),
   jsonb_build_object('account_code','1.1.02','debit',0,'credit',ar_apply),
   jsonb_build_object('account_code','2.1.03','debit',0,'credit',credit_amount),
   jsonb_build_object('account_code','1.1.03','debit',cost_amount,'credit',0),
   jsonb_build_object('account_code','5.1.01','debit',0,'credit',cost_amount)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'RETURN','SALE',rid::text,jsonb_build_object('number',n,'sale_id',s.id,'product_id',p_product_id,'qty',p_qty,'amount',amount,'ar_applied',ar_apply,'customer_credit',credit_amount));
 return jsonb_build_object('id',rid,'number',n,'amount',amount,'qty',p_qty,'receivable_applied',ar_apply,'customer_credit',credit_amount);
end $$;
revoke all on function public.atlas_return_sale(uuid,uuid,numeric) from public;
grant execute on function public.atlas_return_sale(uuid,uuid,numeric) to authenticated;

-- ============================================================
-- BLOQUE 5/14: sql/ATLAS_PURCHASE_RETURNS_PHASE59.sql
-- ============================================================
-- ATLAS Fase 59 / corrección F73 — Devolución de compra segura
-- Devolución parcial por producto: inventario + CxP/crédito proveedor + reverso contable + auditoría.
-- No mueve caja automáticamente: cualquier reembolso exige cuenta y tasa explícitas.

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'1.1.05','Créditos de proveedores','Activo',true from public.companies c
on conflict(company_id,code) do nothing;

-- Conserva el valor original del crédito aunque luego se aplique parcialmente.
alter table public.supplier_credits add column if not exists original_amount numeric(18,4);
update public.supplier_credits set original_amount=balance where original_amount is null;
alter table public.supplier_credits alter column original_amount set default 0;

create or replace function public.atlas_return_purchase(
 p_purchase_id uuid,p_product_id uuid,p_qty numeric
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); p public.purchases%rowtype; li public.purchase_items%rowtype;
 already numeric:=0; subtotal_amount numeric:=0; tax_amount numeric:=0; amount numeric:=0;
 rid uuid:=gen_random_uuid(); n text; ap public.payables%rowtype; ap_apply numeric:=0; credit_amount numeric:=0;
 available numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_qty is null or p_qty<=0 then raise exception 'Cantidad inválida'; end if;
 select * into p from public.purchases where id=p_purchase_id and company_id=cid and status='ACTIVE' for update;
 if p.id is null then raise exception 'Compra activa no encontrada'; end if;
 if not public.can_access_branch(p.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 select * into li from public.purchase_items where purchase_id=p.id and product_id=p_product_id;
 if li.id is null then raise exception 'Producto no pertenece a la compra'; end if;
 select coalesce(sum(coalesce((r.payload->>'qty')::numeric,0)),0) into already
 from public.purchase_returns r
 where r.company_id=cid and r.purchase_id=p.id and r.payload->>'product_id'=p_product_id::text;
 if already+p_qty>li.qty then raise exception 'Cantidad devuelta supera la comprada'; end if;
 select stock-reserved into available from public.inventory where company_id=cid and branch_id=p.branch_id and product_id=p_product_id for update;
 if available is null or available<p_qty then raise exception 'Stock insuficiente para devolver al proveedor'; end if;
 subtotal_amount:=round(p_qty*li.unit_cost,4);
 tax_amount:=case when p.subtotal>0 then round(subtotal_amount*(p.tax/p.subtotal),4) else 0 end;
 amount:=subtotal_amount+tax_amount;
 n:=public.next_document_number('PURCHASE_RETURN','DC-');
 insert into public.purchase_returns(id,company_id,purchase_id,number,total,payload)
 values(rid,cid,p.id,n,amount,jsonb_build_object('product_id',p_product_id,'qty',p_qty,'subtotal',subtotal_amount,'tax',tax_amount,'currency','USD'));
 update public.inventory set stock=stock-p_qty where company_id=cid and branch_id=p.branch_id and product_id=p_product_id;
 select * into ap from public.payables where company_id=cid and purchase_id=p.id and status<>'PAID' order by balance desc limit 1 for update;
 if ap.id is not null then
   ap_apply:=least(amount,ap.balance);
   update public.payables set balance=balance-ap_apply,status=case when balance-ap_apply<=0.0001 then 'PAID' else 'OPEN' end where id=ap.id;
 end if;
 credit_amount:=round(amount-ap_apply,4);
 if credit_amount>0 then
   if p.supplier_id is null then raise exception 'La devolución genera crédito pero la compra no tiene proveedor'; end if;
   insert into public.supplier_credits(company_id,supplier_id,original_amount,balance,currency,reference)
   values(cid,p.supplier_id,credit_amount,credit_amount,'USD',n);
 end if;
 update public.purchase_returns set payload=payload||jsonb_build_object('ap_applied',ap_apply,'supplier_credit',credit_amount) where id=rid;
 perform public.atlas_post_journal(cid,n,'Devolución de compra',jsonb_build_array(
   jsonb_build_object('account_code','2.1.01','debit',ap_apply,'credit',0),
   jsonb_build_object('account_code','1.1.05','debit',credit_amount,'credit',0),
   jsonb_build_object('account_code','1.1.03','debit',0,'credit',subtotal_amount),
   jsonb_build_object('account_code','1.1.04','debit',0,'credit',tax_amount)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'RETURN','PURCHASE',rid::text,jsonb_build_object('number',n,'purchase_id',p.id,'product_id',p_product_id,'qty',p_qty,'amount',amount,'ap_applied',ap_apply,'supplier_credit',credit_amount));
 return jsonb_build_object('id',rid,'number',n,'amount',amount,'qty',p_qty,'payable_applied',ap_apply,'supplier_credit',credit_amount);
end $$;
revoke all on function public.atlas_return_purchase(uuid,uuid,numeric) from public;
grant execute on function public.atlas_return_purchase(uuid,uuid,numeric) to authenticated;

-- ============================================================
-- BLOQUE 6/14: sql/ATLAS_CANCELLATIONS_PHASE60.sql
-- ============================================================
-- ATLAS Fase 60 / corrección F67 — Anulaciones atómicas de ventas y compras
-- Requiere F55. Evita doble reverso y mantiene inventario, caja, CxC/CxP, contabilidad y auditoría coherentes.
-- F67 bloquea anulaciones de documentos a crédito que ya tengan pagos aplicados; esos casos deben ir por devolución.

create or replace function public.atlas_reverse_journal(
 p_company uuid,p_reference text,p_new_reference text,p_description text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare src uuid; eid uuid:=gen_random_uuid(); cnt integer;
begin
 if p_company is null or p_company<>public.current_company_id() then raise exception 'Empresa inválida'; end if;
 select count(*) into cnt from public.journal_entries where company_id=p_company and reference=p_reference;
 if cnt=0 then raise exception 'Asiento original no encontrado para %',p_reference; end if;
 if cnt<>1 then raise exception 'No se puede anular automáticamente: la referencia % tiene % asientos; requiere revisión',p_reference,cnt; end if;
 select id into src from public.journal_entries where company_id=p_company and reference=p_reference limit 1;
 if exists(select 1 from public.journal_entries where company_id=p_company and reference=p_new_reference) then raise exception 'Reverso ya registrado'; end if;
 insert into public.journal_entries(id,company_id,reference,description) values(eid,p_company,p_new_reference,p_description);
 insert into public.journal_lines(entry_id,account_code,description,debit,credit)
 select eid,account_code,coalesce(description,p_description),credit,debit from public.journal_lines where entry_id=src;
 return eid;
end $$;
revoke all on function public.atlas_reverse_journal(uuid,text,text,text) from public;

create or replace function public.atlas_cancel_sale(p_sale uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); s public.sales%rowtype; li record; cm record; ar public.receivables%rowtype; ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 select * into s from public.sales where id=p_sale and company_id=cid for update;
 if s.id is null then raise exception 'Venta no encontrada'; end if;
 if s.status<>'ACTIVE' then raise exception 'Venta ya anulada o no activa'; end if;
 if exists(select 1 from public.sale_returns where company_id=cid and sale_id=s.id) then raise exception 'No se puede anular una venta con devoluciones registradas'; end if;
 if not public.can_access_branch(s.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 select * into ar from public.receivables where company_id=cid and sale_id=s.id order by total desc limit 1 for update;
 if ar.id is not null and ar.balance < ar.total-0.0001 then
   raise exception 'La venta a crédito ya tiene cobros aplicados. Usa devolución para conservar la trazabilidad';
 end if;
 for li in select * from public.sale_items where sale_id=s.id loop
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
   values(cid,s.branch_id,li.product_id,li.qty,0)
   on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 end loop;
 -- En venta de contado revierte exactamente los importes y monedas registrados originalmente.
 for cm in select * from public.cash_movements where company_id=cid and reference=s.number and direction='IN' order by created_at for update loop
   update public.cash_accounts set balance=balance-cm.amount where id=cm.account_id and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,cm.account_id,'OUT',cm.amount,cm.currency,'AN-'||s.number,'Reverso anulación venta',auth.uid());
 end loop;
 if ar.id is not null then update public.receivables set balance=0,status='PAID' where id=ar.id; end if;
 update public.sales set status='CANCELLED' where id=s.id;
 ref:='AN-'||s.number;
 perform public.atlas_reverse_journal(cid,s.number,ref,'Anulación de venta '||s.number);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CANCEL','SALE',s.id::text,jsonb_build_object('number',s.number,'reason',p_reason));
 return jsonb_build_object('id',s.id,'number',s.number,'status','CANCELLED');
end $$;
revoke all on function public.atlas_cancel_sale(uuid,text) from public;
grant execute on function public.atlas_cancel_sale(uuid,text) to authenticated;

create or replace function public.atlas_cancel_purchase(p_purchase uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); p public.purchases%rowtype; li record; cm record; ap public.payables%rowtype; available numeric; ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 select * into p from public.purchases where id=p_purchase and company_id=cid for update;
 if p.id is null then raise exception 'Compra no encontrada'; end if;
 if p.status<>'ACTIVE' then raise exception 'Compra ya anulada o no activa'; end if;
 if exists(select 1 from public.purchase_returns where company_id=cid and purchase_id=p.id) then raise exception 'No se puede anular una compra con devoluciones registradas'; end if;
 if not public.can_access_branch(p.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 select * into ap from public.payables where company_id=cid and purchase_id=p.id order by total desc limit 1 for update;
 if ap.id is not null and ap.balance < ap.total-0.0001 then
   raise exception 'La compra a crédito ya tiene pagos aplicados. Usa devolución para conservar la trazabilidad';
 end if;
 for li in select * from public.purchase_items where purchase_id=p.id loop
   select stock-reserved into available from public.inventory where company_id=cid and branch_id=p.branch_id and product_id=li.product_id for update;
   if available is null or available<li.qty then raise exception 'No se puede anular: parte del stock comprado ya no está disponible'; end if;
 end loop;
 for li in select * from public.purchase_items where purchase_id=p.id loop
   update public.inventory set stock=stock-li.qty where company_id=cid and branch_id=p.branch_id and product_id=li.product_id;
 end loop;
 -- En compra de contado reintegra exactamente los importes y monedas registrados originalmente.
 for cm in select * from public.cash_movements where company_id=cid and reference=p.number and direction='OUT' order by created_at for update loop
   update public.cash_accounts set balance=balance+cm.amount where id=cm.account_id and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,cm.account_id,'IN',cm.amount,cm.currency,'AN-'||p.number,'Reverso anulación compra',auth.uid());
 end loop;
 if ap.id is not null then update public.payables set balance=0,status='PAID' where id=ap.id; end if;
 update public.purchases set status='CANCELLED' where id=p.id;
 ref:='AN-'||p.number;
 perform public.atlas_reverse_journal(cid,p.number,ref,'Anulación de compra '||p.number);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CANCEL','PURCHASE',p.id::text,jsonb_build_object('number',p.number,'reason',p_reason));
 return jsonb_build_object('id',p.id,'number',p.number,'status','CANCELLED');
end $$;
revoke all on function public.atlas_cancel_purchase(uuid,text) from public;
grant execute on function public.atlas_cancel_purchase(uuid,text) to authenticated;

-- ============================================================
-- BLOQUE 7/14: sql/ATLAS_MULTICURRENCY_RPCS_PHASE61.sql
-- ============================================================
-- ATLAS Fase 61 — FX aplicado dentro de RPC críticos
-- Contrato: todos los importes p_* son base USD. La tasa representa unidades de moneda documental por 1 USD.
-- Contabilidad y CxC/CxP permanecen en USD base. Caja se mueve en la moneda propia de la cuenta.

create or replace function public.atlas_create_sale(
 p_branch uuid,p_customer uuid,p_currency text,p_exchange_rate numeric,
 p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cash_account uuid,
 p_items jsonb,p_prefix text default 'V-'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); sid uuid:=gen_random_uuid(); n text; item jsonb;
 pid uuid; q numeric; price numeric; cost numeric; available numeric; due numeric; cogs numeric:=0;
 cash_cur text; cash_amount numeric:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('sales.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_subtotal<0 or p_tax<0 or p_total<0 or p_paid<0 or p_paid>p_total or p_exchange_rate<=0 then raise exception 'Totales inválidos'; end if;
 if abs((p_subtotal+p_tax)-p_total)>0.02 then raise exception 'Total inconsistente'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Venta sin productos'; end if;
 if p_customer is not null and not exists(select 1 from public.customers where id=p_customer and company_id=cid and active=true) then raise exception 'Cliente inválido'; end if;
 if p_paid>0 then
   select currency into cash_cur from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
   if cash_cur is null then raise exception 'Cuenta de caja inválida'; end if;
   cash_amount:=public.atlas_fx_amount(p_paid,cash_cur,p_currency,p_exchange_rate);
 end if;
 n:=public.next_document_number('SALE',p_prefix);
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; price:=coalesce((item->>'unit_price')::numeric,0);
   if q<=0 or price<0 then raise exception 'Línea inválida'; end if;
   select stock-reserved into available from public.inventory where company_id=cid and branch_id=p_branch and product_id=pid for update;
   if available is null or available<q then raise exception 'Stock insuficiente'; end if;
 end loop;
 insert into public.sales(id,company_id,branch_id,customer_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(sid,cid,p_branch,p_customer,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,p_total,auth.uid());
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; price:=coalesce((item->>'unit_price')::numeric,0);
   select coalesce(cost,0) into cost from public.products where id=pid and company_id=cid;
   cogs:=cogs+(cost*q);
   insert into public.sale_items(sale_id,product_id,qty,unit_price,unit_cost) values(sid,pid,q,price,cost);
   update public.inventory set stock=stock-q where company_id=cid and branch_id=p_branch and product_id=pid;
 end loop;
 if p_paid>0 then
   update public.cash_accounts set balance=balance+cash_amount where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,p_cash_account,'IN',cash_amount,cash_cur,n,'Cobro de venta',auth.uid());
 end if;
 due:=p_total-p_paid;
 if due>0 then
   if p_customer is null then raise exception 'Venta con saldo requiere cliente'; end if;
   insert into public.receivables(company_id,customer_id,sale_id,reference,total,balance,status) values(cid,p_customer,sid,n,p_total,due,'OPEN');
 end if;
 perform public.atlas_post_journal(cid,n,'Venta',jsonb_build_array(
   jsonb_build_object('account_code',case when p_paid>0 then '1.1.01' else '1.1.02' end,'debit',case when p_paid>0 then p_paid else due end,'credit',0),
   jsonb_build_object('account_code','1.1.02','debit',case when p_paid>0 then due else 0 end,'credit',0),
   jsonb_build_object('account_code','4.1.01','debit',0,'credit',p_subtotal),
   jsonb_build_object('account_code','2.1.02','debit',0,'credit',p_tax),
   jsonb_build_object('account_code','5.1.01','debit',cogs,'credit',0),
   jsonb_build_object('account_code','1.1.03','debit',0,'credit',cogs)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','SALE',sid::text,jsonb_build_object('number',n,'base_usd',p_total,'paid_usd',p_paid,'cash_amount',cash_amount,'cash_currency',cash_cur,'document_currency',upper(p_currency),'rate',p_exchange_rate));
 return jsonb_build_object('id',sid,'number',n,'balance',due,'cash_amount',cash_amount,'cash_currency',cash_cur);
end $$;

create or replace function public.atlas_create_purchase(
 p_branch uuid,p_supplier uuid,p_currency text,p_exchange_rate numeric,
 p_subtotal numeric,p_tax numeric,p_total numeric,p_paid numeric,p_cash_account uuid,
 p_items jsonb,p_prefix text default 'C-'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); pidoc uuid:=gen_random_uuid(); n text; item jsonb; pid uuid; q numeric; cost numeric; due numeric;
 cash_cur text; cash_amount numeric:=0; bal numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('purchases.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if not public.can_access_branch(p_branch) then raise exception 'Sucursal no autorizada'; end if;
 if p_subtotal<0 or p_tax<0 or p_total<0 or p_paid<0 or p_paid>p_total or p_exchange_rate<=0 then raise exception 'Totales inválidos'; end if;
 if abs((p_subtotal+p_tax)-p_total)>0.02 then raise exception 'Total inconsistente'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Compra sin productos'; end if;
 if p_paid>0 then
   select currency,balance into cash_cur,bal from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
   if cash_cur is null then raise exception 'Cuenta de caja inválida'; end if;
   cash_amount:=public.atlas_fx_amount(p_paid,cash_cur,p_currency,p_exchange_rate);
   if coalesce(bal,0)<cash_amount then raise exception 'Saldo insuficiente en cuenta de pago'; end if;
 end if;
 n:=public.next_document_number('PURCHASE',p_prefix);
 insert into public.purchases(id,company_id,branch_id,supplier_id,number,status,document_currency,exchange_rate,subtotal,tax,total,base_total_usd,created_by)
 values(pidoc,cid,p_branch,p_supplier,n,'ACTIVE',upper(coalesce(p_currency,'USD')),p_exchange_rate,p_subtotal,p_tax,p_total,p_total,auth.uid());
 for item in select value from jsonb_array_elements(p_items) loop
   pid:=(item->>'product_id')::uuid; q:=(item->>'qty')::numeric; cost:=coalesce((item->>'unit_cost')::numeric,0);
   if q<=0 or cost<0 then raise exception 'Línea inválida'; end if;
   if not exists(select 1 from public.products where id=pid and company_id=cid and active=true) then raise exception 'Producto inválido'; end if;
   insert into public.purchase_items(purchase_id,product_id,qty,unit_cost) values(pidoc,pid,q,cost);
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved) values(cid,p_branch,pid,q,0)
   on conflict(branch_id,product_id) do update set stock=public.inventory.stock+excluded.stock;
 end loop;
 if p_paid>0 then
   update public.cash_accounts set balance=balance-cash_amount where id=p_cash_account and company_id=cid;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
   values(cid,p_cash_account,'OUT',cash_amount,cash_cur,n,'Pago de compra',auth.uid());
 end if;
 due:=p_total-p_paid;
 if due>0 then
   if p_supplier is null then raise exception 'Compra con saldo requiere proveedor'; end if;
   insert into public.payables(company_id,supplier_id,purchase_id,reference,total,balance,status) values(cid,p_supplier,pidoc,n,p_total,due,'OPEN');
 end if;
 perform public.atlas_post_journal(cid,n,'Compra de mercancía',jsonb_build_array(
   jsonb_build_object('account_code','1.1.03','debit',p_subtotal,'credit',0),
   jsonb_build_object('account_code','1.1.04','debit',p_tax,'credit',0),
   jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_paid),
   jsonb_build_object('account_code','2.1.01','debit',0,'credit',due)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','PURCHASE',pidoc::text,jsonb_build_object('number',n,'base_usd',p_total,'paid_usd',p_paid,'cash_amount',cash_amount,'cash_currency',cash_cur,'document_currency',upper(p_currency),'rate',p_exchange_rate));
 return jsonb_build_object('id',pidoc,'number',n,'balance',due,'cash_amount',cash_amount,'cash_currency',cash_cur);
end $$;

create or replace function public.atlas_collect_receivable(p_receivable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.receivables%rowtype; s public.sales%rowtype; cur text; cash_amount numeric; newbal numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('ar.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.receivables where id=p_receivable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Cobro inválido'; end if;
 select * into s from public.sales where id=r.sale_id and company_id=cid;
 if s.id is null then raise exception 'Venta origen no encontrada'; end if;
 select currency into cur from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
 if cur is null then raise exception 'Cuenta inválida'; end if;
 cash_amount:=public.atlas_fx_amount(p_amount,cur,s.document_currency,s.exchange_rate);
 newbal:=r.balance-p_amount;
 update public.receivables set balance=newbal,status=case when newbal<=0.0001 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance+cash_amount where id=p_cash_account and company_id=cid;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'IN',cash_amount,cur,r.reference,'Cobro CxC',auth.uid());
 perform public.atlas_post_journal(cid,'COBRO-'||r.reference,'Cobro de cuenta por cobrar',jsonb_build_array(
  jsonb_build_object('account_code','1.1.01','debit',p_amount,'credit',0),jsonb_build_object('account_code','1.1.02','debit',0,'credit',p_amount)));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail) values(cid,auth.uid(),'COLLECT','RECEIVABLE',r.id::text,jsonb_build_object('base_usd',p_amount,'cash_amount',cash_amount,'cash_currency',cur,'rate',s.exchange_rate));
 return jsonb_build_object('id',r.id,'balance',newbal,'cash_amount',cash_amount,'cash_currency',cur);
end $$;

create or replace function public.atlas_pay_payable(p_payable uuid,p_amount numeric,p_cash_account uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); r public.payables%rowtype; p public.purchases%rowtype; cur text; cash_amount numeric; bal numeric; newbal numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('ap.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 select * into r from public.payables where id=p_payable and company_id=cid for update;
 if r.id is null or p_amount<=0 or p_amount>r.balance then raise exception 'Pago inválido'; end if;
 select * into p from public.purchases where id=r.purchase_id and company_id=cid;
 if p.id is null then raise exception 'Compra origen no encontrada'; end if;
 select currency,balance into cur,bal from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
 if cur is null then raise exception 'Cuenta inválida'; end if;
 cash_amount:=public.atlas_fx_amount(p_amount,cur,p.document_currency,p.exchange_rate);
 if coalesce(bal,0)<cash_amount then raise exception 'Saldo insuficiente'; end if;
 newbal:=r.balance-p_amount;
 update public.payables set balance=newbal,status=case when newbal<=0.0001 then 'PAID' else 'OPEN' end where id=r.id;
 update public.cash_accounts set balance=balance-cash_amount where id=p_cash_account and company_id=cid;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,p_cash_account,'OUT',cash_amount,cur,r.reference,'Pago CxP',auth.uid());
 perform public.atlas_post_journal(cid,'PAGO-'||r.reference,'Pago de cuenta por pagar',jsonb_build_array(
  jsonb_build_object('account_code','2.1.01','debit',p_amount,'credit',0),jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_amount)));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail) values(cid,auth.uid(),'PAY','PAYABLE',r.id::text,jsonb_build_object('base_usd',p_amount,'cash_amount',cash_amount,'cash_currency',cur,'rate',p.exchange_rate));
 return jsonb_build_object('id',r.id,'balance',newbal,'cash_amount',cash_amount,'cash_currency',cur);
end $$;

revoke all on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
revoke all on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) from public;
revoke all on function public.atlas_collect_receivable(uuid,numeric,uuid) from public;
revoke all on function public.atlas_pay_payable(uuid,numeric,uuid) from public;
grant execute on function public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;
grant execute on function public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text) to authenticated;
grant execute on function public.atlas_collect_receivable(uuid,numeric,uuid) to authenticated;
grant execute on function public.atlas_pay_payable(uuid,numeric,uuid) to authenticated;

-- ============================================================
-- BLOQUE 8/14: sql/ATLAS_MASTER_DATA_PHASE62.sql
-- ============================================================
-- ATLAS Fase 62 — Maestros remotos coherentes con la UI
-- Añade los campos que la interfaz ya maneja y centraliza altas/ediciones en RPCs seguros.

alter table public.customers add column if not exists code text;
alter table public.suppliers add column if not exists code text;
alter table public.products add column if not exists category text not null default 'General';
alter table public.products add column if not exists tax numeric(9,4) not null default 0 check(tax>=0 and tax<=100);

create unique index if not exists customers_company_code_uq on public.customers(company_id,code) where code is not null and code<>'';
create unique index if not exists suppliers_company_code_uq on public.suppliers(company_id,code) where code is not null and code<>'';

create or replace function public.atlas_create_master(p_entity text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); e text:=lower(trim(p_entity));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if e='customer' then
   if not (public.has_permission('customers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Nombre requerido'; end if;
   insert into public.customers(id,company_id,code,name,tax_id,phone,email,address,active)
   values(rid,cid,nullif(trim(p_payload->>'code'),''),trim(p_payload->>'name'),nullif(trim(p_payload->>'tax_id'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'address'),''),true);
 elsif e='supplier' then
   if not (public.has_permission('suppliers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Nombre requerido'; end if;
   insert into public.suppliers(id,company_id,code,name,tax_id,phone,email,address,active)
   values(rid,cid,nullif(trim(p_payload->>'code'),''),trim(p_payload->>'name'),nullif(trim(p_payload->>'tax_id'),''),nullif(trim(p_payload->>'phone'),''),nullif(trim(p_payload->>'email'),''),nullif(trim(p_payload->>'address'),''),true);
 elsif e='product' then
   if not (public.has_permission('products.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   if nullif(trim(p_payload->>'sku'),'') is null or nullif(trim(p_payload->>'name'),'') is null then raise exception 'SKU y nombre requeridos'; end if;
   insert into public.products(id,company_id,sku,name,category,cost,price,tax,min_stock,active)
   values(rid,cid,trim(p_payload->>'sku'),trim(p_payload->>'name'),coalesce(nullif(trim(p_payload->>'category'),''),'General'),coalesce((p_payload->>'cost')::numeric,0),coalesce((p_payload->>'price')::numeric,0),coalesce((p_payload->>'tax')::numeric,0),coalesce((p_payload->>'min_stock')::numeric,0),true);
   insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
   select cid,b.id,rid,0,0 from public.branches b where b.company_id=cid and b.active=true
   on conflict(branch_id,product_id) do nothing;
 else raise exception 'Entidad no permitida'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE',upper(e),rid::text,p_payload);
 return jsonb_build_object('id',rid,'entity',e);
end $$;

create or replace function public.atlas_update_master(p_entity text,p_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); e text:=lower(trim(p_entity));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if e='customer' then
   if not (public.has_permission('customers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.customers set
    code=coalesce(nullif(trim(p_payload->>'code'),''),code),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    tax_id=case when p_payload ? 'tax_id' then nullif(trim(p_payload->>'tax_id'),'') else tax_id end,
    phone=case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'),'') else phone end,
    email=case when p_payload ? 'email' then nullif(trim(p_payload->>'email'),'') else email end,
    address=case when p_payload ? 'address' then nullif(trim(p_payload->>'address'),'') else address end
   where id=p_id and company_id=cid;
 elsif e='supplier' then
   if not (public.has_permission('suppliers.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.suppliers set
    code=coalesce(nullif(trim(p_payload->>'code'),''),code),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    tax_id=case when p_payload ? 'tax_id' then nullif(trim(p_payload->>'tax_id'),'') else tax_id end,
    phone=case when p_payload ? 'phone' then nullif(trim(p_payload->>'phone'),'') else phone end,
    email=case when p_payload ? 'email' then nullif(trim(p_payload->>'email'),'') else email end,
    address=case when p_payload ? 'address' then nullif(trim(p_payload->>'address'),'') else address end
   where id=p_id and company_id=cid;
 elsif e='product' then
   if not (public.has_permission('products.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
   update public.products set
    sku=coalesce(nullif(trim(p_payload->>'sku'),''),sku),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
    category=coalesce(nullif(trim(p_payload->>'category'),''),category),
    cost=case when p_payload ? 'cost' then (p_payload->>'cost')::numeric else cost end,
    price=case when p_payload ? 'price' then (p_payload->>'price')::numeric else price end,
    tax=case when p_payload ? 'tax' then (p_payload->>'tax')::numeric else tax end,
    min_stock=case when p_payload ? 'min_stock' then (p_payload->>'min_stock')::numeric else min_stock end
   where id=p_id and company_id=cid;
 else raise exception 'Entidad no permitida'; end if;
 if not found then raise exception 'Registro no encontrado'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE',upper(e),p_id::text,p_payload);
 return jsonb_build_object('id',p_id,'entity',e);
end $$;

revoke all on function public.atlas_create_master(text,jsonb) from public;
revoke all on function public.atlas_update_master(text,uuid,jsonb) from public;
grant execute on function public.atlas_create_master(text,jsonb) to authenticated;
grant execute on function public.atlas_update_master(text,uuid,jsonb) to authenticated;

-- ============================================================
-- BLOQUE 9/14: sql/ATLAS_ADMIN_OPERATIONS_PHASE64.sql
-- ============================================================
-- ATLAS Fase 64 / corrección F70 — Operaciones administrativas remotas
-- Cierra fugas de estado local: ajuste de inventario y alta de cuenta financiera.
-- F70 separa contablemente los ajustes de inventario de las diferencias de caja
-- y elimina la dependencia del contador genérico con permisos incompatibles.

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'5.2.03','Ajustes de inventario','Gasto',true from public.companies c
on conflict(company_id,code) do update set name=excluded.name,type=excluded.type,active=true;

create or replace function public.atlas_adjust_inventory(
 p_branch_id uuid,p_product_id uuid,p_new_stock numeric,p_reason text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); old_stock numeric; delta numeric; cost numeric; ref text; seq bigint;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('products.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_new_stock is null or p_new_stock<0 then raise exception 'Existencia inválida'; end if;
 if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'Motivo requerido'; end if;
 if not public.can_access_branch(p_branch_id) then raise exception 'Sucursal no autorizada'; end if;
 select i.stock,p.cost into old_stock,cost
 from public.inventory i join public.products p on p.id=i.product_id and p.company_id=i.company_id
 where i.company_id=cid and i.branch_id=p_branch_id and i.product_id=p_product_id for update of i;
 if old_stock is null then raise exception 'Inventario no encontrado'; end if;
 delta:=round(p_new_stock-old_stock,4);
 if delta=0 then return jsonb_build_object('changed',false,'stock',old_stock); end if;

 -- Contador atómico propio: no depende de next_document_number(), cuya política está pensada
 -- para ventas/compras/operaciones y podía bloquear a un usuario con products.manage.
 insert into public.document_counters(company_id,document_type,prefix,current_value)
 values(cid,'INVENTORY_ADJUSTMENT','AJ-',1)
 on conflict(company_id,document_type) do update
 set current_value=public.document_counters.current_value+1,prefix='AJ-'
 returning current_value into seq;
 ref:='AJ-'||lpad(seq::text,6,'0');

 update public.inventory set stock=p_new_stock
 where company_id=cid and branch_id=p_branch_id and product_id=p_product_id;

 -- Contabilidad en USD usando costo actual del producto como valoración del ajuste.
 -- 5.2.03 queda reservado a ajustes de inventario; 5.2.02 se reserva a diferencias de caja.
 if coalesce(cost,0)>0 then
   if delta>0 then
     perform public.atlas_post_journal(cid,ref,'Ajuste de inventario: '||p_reason,jsonb_build_array(
       jsonb_build_object('account_code','1.1.03','debit',round(delta*cost,4),'credit',0),
       jsonb_build_object('account_code','5.2.03','debit',0,'credit',round(delta*cost,4))));
   else
     perform public.atlas_post_journal(cid,ref,'Ajuste de inventario: '||p_reason,jsonb_build_array(
       jsonb_build_object('account_code','5.2.03','debit',round(abs(delta)*cost,4),'credit',0),
       jsonb_build_object('account_code','1.1.03','debit',0,'credit',round(abs(delta)*cost,4))));
   end if;
 end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'ADJUST','INVENTORY',p_branch_id::text||':'||p_product_id::text,
   jsonb_build_object('reference',ref,'old_stock',old_stock,'new_stock',p_new_stock,'delta',delta,'reason',p_reason,'unit_cost_usd',coalesce(cost,0)));
 return jsonb_build_object('changed',true,'reference',ref,'old_stock',old_stock,'stock',p_new_stock,'delta',delta);
end $$;

create or replace function public.atlas_create_cash_account(
 p_name text,p_currency text,p_branch_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); cur text:=upper(trim(coalesce(p_currency,'')));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('cash.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if cur not in ('USD','VES','EUR','USDT') then raise exception 'Moneda no permitida'; end if;
 if p_branch_id is not null and not public.can_access_branch(p_branch_id) then raise exception 'Sucursal no autorizada'; end if;
 if exists(select 1 from public.cash_accounts where company_id=cid and lower(name)=lower(trim(p_name)) and active=true) then
   raise exception 'Ya existe una cuenta financiera activa con ese nombre';
 end if;
 insert into public.cash_accounts(id,company_id,branch_id,name,currency,balance,active)
 values(rid,cid,p_branch_id,trim(p_name),cur,0,true);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','CASH_ACCOUNT',rid::text,jsonb_build_object('name',trim(p_name),'currency',cur,'branch_id',p_branch_id));
 return jsonb_build_object('id',rid,'name',trim(p_name),'currency',cur,'balance',0);
end $$;

revoke all on function public.atlas_adjust_inventory(uuid,uuid,numeric,text) from public;
revoke all on function public.atlas_create_cash_account(text,text,uuid) from public;
grant execute on function public.atlas_adjust_inventory(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.atlas_create_cash_account(text,text,uuid) to authenticated;

-- ============================================================
-- BLOQUE 10/14: sql/ATLAS_CONFIGURATION_PHASE65.sql
-- ============================================================
-- ATLAS Fase 65 / endurecimiento F71 — Configuración operativa remota
-- Sucursales, métodos de pago y tasas dejan de depender del almacenamiento local.

alter table public.branches add column if not exists city text;

-- Lectura: usuarios ven sus sucursales; administradores de configuración pueden ver todas
-- las de su empresa para gestionarlas. Escritura directa bloqueada: toda mutación va por RPC auditado.
drop policy if exists atlas_branches_read on public.branches;
create policy atlas_branches_read on public.branches for select to authenticated
using(
 company_id=public.current_company_id()
 and (
   public.has_permission('branches.all')
   or public.has_permission('settings.manage')
   or public.has_permission('*')
   or public.can_access_branch(id)
 )
);
drop policy if exists atlas_branches_write on public.branches;
revoke insert, update, delete on public.branches from authenticated;

create or replace function public.atlas_create_branch(p_name text,p_code text default null,p_city text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); code_value text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 code_value:=upper(coalesce(nullif(regexp_replace(btrim(coalesce(p_code,'')),'[^A-Za-z0-9]+','','g'),''),substr(replace(rid::text,'-',''),1,8)));
 if exists(select 1 from public.branches where company_id=cid and lower(name)=lower(btrim(p_name))) then raise exception 'Ya existe una sucursal con ese nombre'; end if;
 insert into public.branches(id,company_id,name,code,city,active) values(rid,cid,btrim(p_name),code_value,nullif(btrim(coalesce(p_city,'')),''),true);
 insert into public.inventory(company_id,branch_id,product_id,stock,reserved)
 select cid,rid,p.id,0,0 from public.products p where p.company_id=cid and p.active=true
 on conflict(branch_id,product_id) do nothing;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','BRANCH',rid::text,jsonb_build_object('name',btrim(p_name),'code',code_value,'city',p_city));
 return jsonb_build_object('id',rid,'name',btrim(p_name),'code',code_value);
end $$;

create or replace function public.atlas_create_payment_method(p_name text,p_kind text default 'OTHER')
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); k text:=upper(coalesce(nullif(btrim(p_kind),''),'OTHER'));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if k not in ('CASH','BANK','MOBILE','OTHER') then k:='OTHER'; end if;
 if exists(select 1 from public.payment_methods where company_id=cid and lower(name)=lower(btrim(p_name))) then raise exception 'Ya existe ese método de pago'; end if;
 insert into public.payment_methods(id,company_id,name,kind,active) values(rid,cid,btrim(p_name),k,true);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','PAYMENT_METHOD',rid::text,jsonb_build_object('name',btrim(p_name),'kind',k));
 return jsonb_build_object('id',rid,'name',btrim(p_name),'kind',k);
end $$;

create or replace function public.atlas_create_exchange_rate(p_currency text,p_rate numeric,p_source text default 'Manual',p_effective_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); cur text:=upper(btrim(coalesce(p_currency,'')));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if cur not in ('VES','USD','EUR','USDT') then raise exception 'Moneda no soportada'; end if;
 if p_rate is null or p_rate<=0 then raise exception 'Tasa inválida'; end if;
 if cur='USD' and abs(p_rate-1)>0.000001 then raise exception 'La tasa USD debe ser 1'; end if;
 insert into public.exchange_rates(id,company_id,currency,rate,source,effective_at)
 values(rid,cid,cur,p_rate,coalesce(nullif(btrim(p_source),''),'Manual'),coalesce(p_effective_at,now()));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','EXCHANGE_RATE',rid::text,jsonb_build_object('currency',cur,'rate',p_rate,'source',p_source,'effective_at',p_effective_at));
 return jsonb_build_object('id',rid,'currency',cur,'rate',p_rate);
end $$;

revoke all on function public.atlas_create_branch(text,text,text) from public;
revoke all on function public.atlas_create_payment_method(text,text) from public;
revoke all on function public.atlas_create_exchange_rate(text,numeric,text,timestamptz) from public;
grant execute on function public.atlas_create_branch(text,text,text) to authenticated;
grant execute on function public.atlas_create_payment_method(text,text) to authenticated;
grant execute on function public.atlas_create_exchange_rate(text,numeric,text,timestamptz) to authenticated;

-- ============================================================
-- BLOQUE 11/14: sql/ATLAS_ACCESS_CONTROL_PHASE66.sql
-- ============================================================
-- ATLAS Fase 66 / endurecimiento F71 — Usuarios, roles, permisos y configuración remota
-- No crea usuarios de auth directamente: eso requiere un flujo administrativo seguro.

alter table public.companies add column if not exists phone text;
alter table public.companies add column if not exists email text;
alter table public.companies add column if not exists display_currency text not null default 'USD';

create or replace function public.atlas_access_snapshot()
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); result jsonb; own_role uuid;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then
   -- Usuario normal: sólo su perfil y su propio rol. No exponer el directorio ni permisos de otros roles.
   select ur.role_id into own_role from public.user_roles ur where ur.user_id=auth.uid();
   select jsonb_build_object(
     'users',coalesce(jsonb_agg(jsonb_build_object(
       'id',p.id,'name',p.full_name,'status',p.status,'role_id',ur.role_id,
       'branch_ids',coalesce((select jsonb_agg(ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb)
     )),'[]'::jsonb),
     'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'permissions',r.permissions))
       from public.roles r where r.company_id=cid and r.id=own_role),'[]'::jsonb)
   ) into result
   from public.profiles p left join public.user_roles ur on ur.user_id=p.id
   where p.id=auth.uid() and p.company_id=cid;
   return coalesce(result,jsonb_build_object('users','[]'::jsonb,'roles','[]'::jsonb));
 end if;

 select jsonb_build_object(
   'users',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'name',p.full_name,'status',p.status,'role_id',ur.role_id,
      'branch_ids',coalesce((select jsonb_agg(ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb)
   ) order by p.full_name) from public.profiles p left join public.user_roles ur on ur.user_id=p.id where p.company_id=cid),'[]'::jsonb),
   'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'permissions',r.permissions) order by r.name) from public.roles r where r.company_id=cid),'[]'::jsonb)
 ) into result;
 return result;
end $$;

create or replace function public.atlas_create_role(p_name text,p_permissions jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); perms jsonb:=coalesce(p_permissions,'[]'::jsonb);
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if jsonb_typeof(perms)<>'array' then raise exception 'Permisos inválidos'; end if;
 if exists(select 1 from public.roles where company_id=cid and lower(name)=lower(btrim(p_name))) then raise exception 'Ya existe ese rol'; end if;
 insert into public.roles(id,company_id,name,permissions) values(rid,cid,btrim(p_name),perms);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','ROLE',rid::text,jsonb_build_object('name',p_name,'permissions',perms));
 return jsonb_build_object('id',rid,'name',btrim(p_name));
end $$;

create or replace function public.atlas_update_role(p_role_id uuid,p_name text,p_permissions jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); perms jsonb:=coalesce(p_permissions,'[]'::jsonb);
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if jsonb_typeof(perms)<>'array' then raise exception 'Permisos inválidos'; end if;
 update public.roles set name=coalesce(nullif(btrim(coalesce(p_name,'')),''),name),permissions=perms
 where id=p_role_id and company_id=cid;
 if not found then raise exception 'Rol no encontrado'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','ROLE',p_role_id::text,jsonb_build_object('name',p_name,'permissions',perms));
 return jsonb_build_object('id',p_role_id);
end $$;

create or replace function public.atlas_assign_user_access(p_user_id uuid,p_role_id uuid,p_branch_ids uuid[],p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); b uuid;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and company_id=cid) then raise exception 'Usuario no pertenece a la empresa'; end if;
 if not exists(select 1 from public.roles where id=p_role_id and company_id=cid) then raise exception 'Rol inválido'; end if;
 if p_user_id=auth.uid() and p_active=false then raise exception 'No puedes desactivar tu propia sesión'; end if;
 foreach b in array coalesce(p_branch_ids,array[]::uuid[]) loop
   if not exists(select 1 from public.branches where id=b and company_id=cid and active=true) then raise exception 'Sucursal inválida'; end if;
 end loop;
 insert into public.user_roles(user_id,role_id) values(p_user_id,p_role_id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 delete from public.user_branches where user_id=p_user_id;
 insert into public.user_branches(user_id,branch_id)
 select p_user_id,x from unnest(coalesce(p_branch_ids,array[]::uuid[])) x;
 update public.profiles set status=case when p_active then 'ACTIVE' else 'INACTIVE' end where id=p_user_id and company_id=cid;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','USER_ACCESS',p_user_id::text,jsonb_build_object('role_id',p_role_id,'branch_ids',coalesce(p_branch_ids,array[]::uuid[]),'active',p_active));
 return jsonb_build_object('id',p_user_id,'active',p_active);
end $$;

create or replace function public.atlas_update_company(p_name text,p_tax_id text,p_phone text,p_email text,p_country text,p_base_currency text,p_display_currency text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); base text:=upper(btrim(coalesce(p_base_currency,'USD'))); disp text:=upper(btrim(coalesce(p_display_currency,'USD')));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if base not in ('USD','VES','EUR','USDT') or disp not in ('USD','VES','EUR','USDT') then raise exception 'Moneda inválida'; end if;
 update public.companies set name=btrim(p_name),tax_id=nullif(btrim(coalesce(p_tax_id,'')),''),phone=nullif(btrim(coalesce(p_phone,'')),''),email=nullif(btrim(coalesce(p_email,'')),''),country=upper(coalesce(nullif(btrim(p_country),''),'VE')),base_currency=base,display_currency=disp where id=cid;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','COMPANY',cid::text,jsonb_build_object('name',p_name,'base_currency',base,'display_currency',disp));
 return jsonb_build_object('id',cid,'name',btrim(p_name));
end $$;

create or replace function public.atlas_update_branch(p_branch_id uuid,p_name text,p_city text,p_active boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id();
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 update public.branches set name=coalesce(nullif(btrim(coalesce(p_name,'')),''),name),city=nullif(btrim(coalesce(p_city,'')),''),active=coalesce(p_active,active)
 where id=p_branch_id and company_id=cid;
 if not found then raise exception 'Sucursal no encontrada'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','BRANCH',p_branch_id::text,jsonb_build_object('name',p_name,'city',p_city,'active',p_active));
 return jsonb_build_object('id',p_branch_id);
end $$;

revoke all on function public.atlas_access_snapshot() from public;
revoke all on function public.atlas_create_role(text,jsonb) from public;
revoke all on function public.atlas_update_role(uuid,text,jsonb) from public;
revoke all on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) from public;
revoke all on function public.atlas_update_company(text,text,text,text,text,text,text) from public;
revoke all on function public.atlas_update_branch(uuid,text,text,boolean) from public;
grant execute on function public.atlas_access_snapshot() to authenticated;
grant execute on function public.atlas_create_role(text,jsonb) to authenticated;
grant execute on function public.atlas_update_role(uuid,text,jsonb) to authenticated;
grant execute on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) to authenticated;
grant execute on function public.atlas_update_company(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.atlas_update_branch(uuid,text,text,boolean) to authenticated;

-- ============================================================
-- BLOQUE 12/14: sql/ATLAS_CASH_CONTROL_PHASE68.sql
-- ============================================================
-- ATLAS Fase 68 / corrección F72 — Caja, conciliación y aplicación de créditos
-- Operaciones monetarias remotas, atómicas y auditables.

create table if not exists public.cash_transfers(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 from_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 to_account_id uuid not null references public.cash_accounts(id) on delete restrict,
 reference text not null,
 from_amount numeric(18,6) not null check(from_amount>0),
 from_currency text not null,
 to_amount numeric(18,6) not null check(to_amount>0),
 to_currency text not null,
 base_amount_usd numeric(18,6) not null check(base_amount_usd>0),
 from_rate numeric(18,8) not null check(from_rate>0),
 to_rate numeric(18,8) not null check(to_rate>0),
 note text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(company_id,reference),
 check(from_account_id<>to_account_id)
);

alter table public.cash_closings add column if not exists reference text;
alter table public.cash_closings add column if not exists currency text;
alter table public.cash_closings add column if not exists note text;
alter table public.cash_closings add column if not exists status text not null default 'OPEN';
alter table public.cash_closings add column if not exists reconciled_at timestamptz;
alter table public.cash_closings add column if not exists reconciliation_reason text;

alter table public.cash_transfers enable row level security;
drop policy if exists atlas_cash_transfers_read on public.cash_transfers;
create policy atlas_cash_transfers_read on public.cash_transfers for select to authenticated
using(company_id=public.current_company_id());
revoke insert, update, delete on public.cash_transfers from authenticated;

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'5.2.02','Ajustes y diferencias de caja','Gasto',true from public.companies c
on conflict(company_id,code) do nothing;

-- F72: contador interno sin depender de permisos de ventas/compras.
-- No se concede EXECUTE al rol authenticated; sólo lo invocan RPC security definer autorizados.
create or replace function public.atlas_internal_document_number(p_type text,p_prefix text default '')
returns text language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); n bigint;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 insert into public.document_counters(company_id,document_type,prefix,current_value)
 values(cid,upper(trim(p_type)),coalesce(p_prefix,''),1)
 on conflict(company_id,document_type) do update
 set current_value=public.document_counters.current_value+1,
     prefix=excluded.prefix
 returning current_value into n;
 return coalesce(p_prefix,'')||lpad(n::text,5,'0');
end $$;
revoke all on function public.atlas_internal_document_number(text,text) from public;
revoke execute on function public.atlas_internal_document_number(text,text) from authenticated;

create or replace function public.atlas_cash_transfer(
 p_from_account uuid,p_to_account uuid,
 p_from_amount numeric,p_to_amount numeric,p_base_amount_usd numeric,
 p_from_rate numeric,p_to_rate numeric,p_reference text default null,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); fa public.cash_accounts%rowtype; ta public.cash_accounts%rowtype;
 tid uuid:=gen_random_uuid(); ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('cash.manage') or public.has_permission('cash.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_from_account=p_to_account then raise exception 'Las cuentas deben ser diferentes'; end if;
 if p_from_amount is null or p_from_amount<=0 or p_to_amount is null or p_to_amount<=0 or p_base_amount_usd is null or p_base_amount_usd<=0 then raise exception 'Monto inválido'; end if;
 if p_from_rate is null or p_from_rate<=0 or p_to_rate is null or p_to_rate<=0 then raise exception 'Tasa inválida'; end if;
 select * into fa from public.cash_accounts where id=p_from_account and company_id=cid and active=true for update;
 select * into ta from public.cash_accounts where id=p_to_account and company_id=cid and active=true for update;
 if fa.id is null or ta.id is null then raise exception 'Cuenta inválida'; end if;
 if fa.branch_id is not null and not public.can_access_branch(fa.branch_id) then raise exception 'Sucursal origen no autorizada'; end if;
 if ta.branch_id is not null and not public.can_access_branch(ta.branch_id) then raise exception 'Sucursal destino no autorizada'; end if;
 if fa.balance<p_from_amount then raise exception 'Saldo insuficiente'; end if;
 ref:=coalesce(nullif(btrim(p_reference),''),public.atlas_internal_document_number('CASH_TRANSFER','TF-'));
 update public.cash_accounts set balance=balance-p_from_amount where id=fa.id;
 update public.cash_accounts set balance=balance+p_to_amount where id=ta.id;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values
 (cid,fa.id,'OUT',p_from_amount,fa.currency,ref,coalesce(nullif(btrim(p_note),''),'Transferencia entre cuentas'),auth.uid()),
 (cid,ta.id,'IN',p_to_amount,ta.currency,ref,coalesce(nullif(btrim(p_note),''),'Transferencia entre cuentas'),auth.uid());
 insert into public.cash_transfers(id,company_id,from_account_id,to_account_id,reference,from_amount,from_currency,to_amount,to_currency,base_amount_usd,from_rate,to_rate,note,created_by)
 values(tid,cid,fa.id,ta.id,ref,p_from_amount,fa.currency,p_to_amount,ta.currency,p_base_amount_usd,p_from_rate,p_to_rate,p_note,auth.uid());
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','CASH_TRANSFER',tid::text,jsonb_build_object('reference',ref,'from_account',fa.id,'to_account',ta.id,'from_amount',p_from_amount,'from_currency',fa.currency,'to_amount',p_to_amount,'to_currency',ta.currency,'base_usd',p_base_amount_usd,'from_rate',p_from_rate,'to_rate',p_to_rate));
 return jsonb_build_object('id',tid,'reference',ref);
end $$;

create or replace function public.atlas_cash_close(
 p_cash_account uuid,p_counted numeric,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); a public.cash_accounts%rowtype; rid uuid:=gen_random_uuid(); ref text; diff numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('cash.manage') or public.has_permission('cash.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_counted is null or p_counted<0 then raise exception 'Monto contado inválido'; end if;
 select * into a from public.cash_accounts where id=p_cash_account and company_id=cid and active=true for update;
 if a.id is null then raise exception 'Cuenta inválida'; end if;
 if a.branch_id is not null and not public.can_access_branch(a.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 diff:=round(p_counted-a.balance,6); ref:=public.atlas_internal_document_number('CASH_CLOSING','CJ-');
 insert into public.cash_closings(id,company_id,branch_id,cash_account_id,expected,counted,difference,created_by,reference,currency,note,status)
 values(rid,cid,a.branch_id,a.id,a.balance,p_counted,diff,auth.uid(),ref,a.currency,p_note,case when abs(diff)<0.0001 then 'BALANCED' else 'DIFFERENCE' end);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','CASH_CLOSING',rid::text,jsonb_build_object('reference',ref,'account',a.id,'expected',a.balance,'counted',p_counted,'difference',diff,'currency',a.currency));
 return jsonb_build_object('id',rid,'reference',ref,'difference',diff,'currency',a.currency);
end $$;

create or replace function public.atlas_reconcile_cash_closing(p_closing uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); c public.cash_closings%rowtype; a public.cash_accounts%rowtype; amt numeric; base_usd numeric; rate numeric:=1; ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('cash.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'Motivo requerido'; end if;
 select * into c from public.cash_closings where id=p_closing and company_id=cid for update;
 if c.id is null then raise exception 'Cierre no encontrado'; end if;
 if c.status<>'DIFFERENCE' then raise exception 'El cierre no tiene diferencia pendiente'; end if;
 select * into a from public.cash_accounts where id=c.cash_account_id and company_id=cid for update;
 if a.id is null then raise exception 'Cuenta no encontrada'; end if;
 if upper(a.currency)<>'USD' then
   select er.rate into rate from public.exchange_rates er where er.company_id=cid and upper(er.currency)=upper(a.currency) and er.effective_at<=c.created_at order by er.effective_at desc limit 1;
   if rate is null or rate<=0 then raise exception 'No existe tasa histórica para conciliar esta moneda'; end if;
 end if;
 amt:=abs(c.difference); base_usd:=case when upper(a.currency)='USD' then amt else round(amt/rate,6) end; ref:='AJ-'||coalesce(c.reference,c.id::text);
 if c.difference>0 then
   update public.cash_accounts set balance=balance+amt where id=a.id;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by) values(cid,a.id,'IN',amt,a.currency,ref,p_reason,auth.uid());
   perform public.atlas_post_journal(cid,ref,'Sobrante de caja',jsonb_build_array(
    jsonb_build_object('account_code','1.1.01','debit',base_usd,'credit',0),jsonb_build_object('account_code','5.2.02','debit',0,'credit',base_usd)));
 else
   if a.balance<amt then raise exception 'Saldo insuficiente para conciliar faltante'; end if;
   update public.cash_accounts set balance=balance-amt where id=a.id;
   insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by) values(cid,a.id,'OUT',amt,a.currency,ref,p_reason,auth.uid());
   perform public.atlas_post_journal(cid,ref,'Faltante de caja',jsonb_build_array(
    jsonb_build_object('account_code','5.2.02','debit',base_usd,'credit',0),jsonb_build_object('account_code','1.1.01','debit',0,'credit',base_usd)));
 end if;
 update public.cash_closings set status='RECONCILED',reconciled_at=now(),reconciliation_reason=p_reason where id=c.id;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'RECONCILE','CASH_CLOSING',c.id::text,jsonb_build_object('reference',ref,'difference',c.difference,'currency',a.currency,'base_usd',base_usd,'rate',rate,'reason',p_reason));
 return jsonb_build_object('id',c.id,'reference',ref,'status','RECONCILED');
end $$;

create or replace function public.atlas_apply_customer_credit(p_credit uuid,p_receivable uuid,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); c public.customer_credits%rowtype; r public.receivables%rowtype; amt numeric; ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('ar.manage') or public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Monto inválido'; end if;
 select * into c from public.customer_credits where id=p_credit and company_id=cid for update;
 select * into r from public.receivables where id=p_receivable and company_id=cid for update;
 if c.id is null or r.id is null then raise exception 'Crédito o cuenta por cobrar inválidos'; end if;
 if c.customer_id<>r.customer_id then raise exception 'El crédito pertenece a otro cliente'; end if;
 if upper(c.currency)<>'USD' then raise exception 'Sólo créditos base USD pueden aplicarse automáticamente'; end if;
 amt:=least(p_amount,c.balance,r.balance); if amt<=0 then raise exception 'No hay saldo aplicable'; end if;
 update public.customer_credits set balance=balance-amt where id=c.id;
 update public.receivables set balance=balance-amt,status=case when balance-amt<=0.0001 then 'PAID' else 'OPEN' end where id=r.id;
 ref:=public.atlas_internal_document_number('CUSTOMER_CREDIT_APPLY','NC-');
 perform public.atlas_post_journal(cid,ref,'Aplicación de crédito de cliente',jsonb_build_array(
  jsonb_build_object('account_code','2.1.03','debit',amt,'credit',0),jsonb_build_object('account_code','1.1.02','debit',0,'credit',amt)));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail) values(cid,auth.uid(),'APPLY','CUSTOMER_CREDIT',c.id::text,jsonb_build_object('reference',ref,'receivable',r.id,'amount',amt));
 return jsonb_build_object('reference',ref,'amount',amt);
end $$;

create or replace function public.atlas_apply_supplier_credit(p_credit uuid,p_payable uuid,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); c public.supplier_credits%rowtype; r public.payables%rowtype; amt numeric; ref text;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('ap.manage') or public.has_permission('operations.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Monto inválido'; end if;
 select * into c from public.supplier_credits where id=p_credit and company_id=cid for update;
 select * into r from public.payables where id=p_payable and company_id=cid for update;
 if c.id is null or r.id is null then raise exception 'Crédito o cuenta por pagar inválidos'; end if;
 if c.supplier_id<>r.supplier_id then raise exception 'El crédito pertenece a otro proveedor'; end if;
 if upper(c.currency)<>'USD' then raise exception 'Sólo créditos base USD pueden aplicarse automáticamente'; end if;
 amt:=least(p_amount,c.balance,r.balance); if amt<=0 then raise exception 'No hay saldo aplicable'; end if;
 update public.supplier_credits set balance=balance-amt where id=c.id;
 update public.payables set balance=balance-amt,status=case when balance-amt<=0.0001 then 'PAID' else 'OPEN' end where id=r.id;
 ref:=public.atlas_internal_document_number('SUPPLIER_CREDIT_APPLY','CP-');
 perform public.atlas_post_journal(cid,ref,'Aplicación de crédito de proveedor',jsonb_build_array(
  jsonb_build_object('account_code','2.1.01','debit',amt,'credit',0),jsonb_build_object('account_code','1.1.05','debit',0,'credit',amt)));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail) values(cid,auth.uid(),'APPLY','SUPPLIER_CREDIT',c.id::text,jsonb_build_object('reference',ref,'payable',r.id,'amount',amt));
 return jsonb_build_object('reference',ref,'amount',amt);
end $$;

revoke all on function public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text) from public;
revoke all on function public.atlas_cash_close(uuid,numeric,text) from public;
revoke all on function public.atlas_reconcile_cash_closing(uuid,text) from public;
revoke all on function public.atlas_apply_customer_credit(uuid,uuid,numeric) from public;
revoke all on function public.atlas_apply_supplier_credit(uuid,uuid,numeric) from public;
grant execute on function public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function public.atlas_cash_close(uuid,numeric,text) to authenticated;
grant execute on function public.atlas_reconcile_cash_closing(uuid,text) to authenticated;
grant execute on function public.atlas_apply_customer_credit(uuid,uuid,numeric) to authenticated;
grant execute on function public.atlas_apply_supplier_credit(uuid,uuid,numeric) to authenticated;

-- ============================================================
-- BLOQUE 13/14: sql/ATLAS_FX_CASH_HARDENING_PHASE69.sql
-- ============================================================
-- ATLAS Fase 69 / corrección F73 — Endurecimiento FX de caja y gastos multimoneda
-- Contrato monetario: rate = unidades de la moneda de la cuenta por 1 USD.

alter table public.expenses add column if not exists base_amount_usd numeric(18,6);
alter table public.expenses add column if not exists exchange_rate numeric(18,8);

-- Gasto multimoneda seguro. El cliente entrega el monto físico de caja, el equivalente USD y la tasa usada.
create or replace function public.atlas_create_expense_fx(
 p_cash_account_id uuid,p_category text,p_description text,
 p_cash_amount numeric,p_base_amount_usd numeric,p_rate numeric,
 p_reference text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); eid uuid:=gen_random_uuid(); ref text; a public.cash_accounts%rowtype; expected numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('operations.manage') or public.has_permission('cash.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_description,'')),'') is null then raise exception 'Descripción requerida'; end if;
 if p_cash_amount is null or p_cash_amount<=0 or p_base_amount_usd is null or p_base_amount_usd<=0 then raise exception 'Monto inválido'; end if;
 if p_rate is null or p_rate<=0 then raise exception 'Tasa inválida'; end if;
 select * into a from public.cash_accounts where id=p_cash_account_id and company_id=cid and active=true for update;
 if a.id is null then raise exception 'Cuenta inválida'; end if;
 if a.branch_id is not null and not public.can_access_branch(a.branch_id) then raise exception 'Sucursal no autorizada'; end if;
 if a.balance<p_cash_amount then raise exception 'Saldo insuficiente'; end if;
 expected:=case when upper(a.currency)='USD' then p_base_amount_usd else p_base_amount_usd*p_rate end;
 if abs(expected-p_cash_amount)>greatest(0.01,abs(p_cash_amount)*0.0005) then raise exception 'Monto/tasa inconsistentes'; end if;
 if upper(a.currency)='USD' and abs(p_rate-1)>0.000001 then raise exception 'La tasa USD debe ser 1'; end if;
 ref:=coalesce(nullif(btrim(p_reference),''),public.atlas_internal_document_number('EXPENSE','G-'));
 insert into public.expenses(id,company_id,branch_id,cash_account_id,category,description,amount,currency,base_amount_usd,exchange_rate,reference,created_by)
 values(eid,cid,a.branch_id,a.id,coalesce(nullif(btrim(p_category),''),'General'),btrim(p_description),p_cash_amount,upper(a.currency),p_base_amount_usd,p_rate,ref,auth.uid());
 update public.cash_accounts set balance=balance-p_cash_amount where id=a.id;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values(cid,a.id,'OUT',p_cash_amount,upper(a.currency),ref,btrim(p_description),auth.uid());
 perform public.atlas_post_journal(cid,ref,'Gasto: '||btrim(p_description),jsonb_build_array(
  jsonb_build_object('account_code','5.2.01','debit',p_base_amount_usd,'credit',0),
  jsonb_build_object('account_code','1.1.01','debit',0,'credit',p_base_amount_usd)
 ));
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','EXPENSE',eid::text,jsonb_build_object('reference',ref,'cash_amount',p_cash_amount,'currency',a.currency,'base_usd',p_base_amount_usd,'rate',p_rate,'category',p_category));
 return jsonb_build_object('id',eid,'reference',ref,'cash_amount',p_cash_amount,'currency',a.currency,'base_amount_usd',p_base_amount_usd,'rate',p_rate);
end $$;

-- Transferencia con coherencia FX y bloqueo determinista para evitar deadlocks en transferencias opuestas concurrentes.
create or replace function public.atlas_cash_transfer(
 p_from_account uuid,p_to_account uuid,
 p_from_amount numeric,p_to_amount numeric,p_base_amount_usd numeric,
 p_from_rate numeric,p_to_rate numeric,p_reference text default null,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); fa public.cash_accounts%rowtype; ta public.cash_accounts%rowtype;
 tid uuid:=gen_random_uuid(); ref text; expected_from numeric; expected_to numeric;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('cash.manage') or public.has_permission('cash.operate') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if p_from_account=p_to_account then raise exception 'Las cuentas deben ser diferentes'; end if;
 if p_from_amount is null or p_from_amount<=0 or p_to_amount is null or p_to_amount<=0 or p_base_amount_usd is null or p_base_amount_usd<=0 then raise exception 'Monto inválido'; end if;
 if p_from_rate is null or p_from_rate<=0 or p_to_rate is null or p_to_rate<=0 then raise exception 'Tasa inválida'; end if;

 -- Bloquea ambas cuentas siempre en el mismo orden de UUID, independientemente de origen/destino.
 perform id from public.cash_accounts
 where company_id=cid and active=true and id in (p_from_account,p_to_account)
 order by id for update;
 select * into fa from public.cash_accounts where id=p_from_account and company_id=cid and active=true;
 select * into ta from public.cash_accounts where id=p_to_account and company_id=cid and active=true;
 if fa.id is null or ta.id is null then raise exception 'Cuenta inválida'; end if;

 if fa.branch_id is not null and not public.can_access_branch(fa.branch_id) then raise exception 'Sucursal origen no autorizada'; end if;
 if ta.branch_id is not null and not public.can_access_branch(ta.branch_id) then raise exception 'Sucursal destino no autorizada'; end if;
 if upper(fa.currency)='USD' and abs(p_from_rate-1)>0.000001 then raise exception 'Tasa USD origen debe ser 1'; end if;
 if upper(ta.currency)='USD' and abs(p_to_rate-1)>0.000001 then raise exception 'Tasa USD destino debe ser 1'; end if;
 expected_from:=case when upper(fa.currency)='USD' then p_base_amount_usd else p_base_amount_usd*p_from_rate end;
 expected_to:=case when upper(ta.currency)='USD' then p_base_amount_usd else p_base_amount_usd*p_to_rate end;
 if abs(expected_from-p_from_amount)>greatest(0.01,abs(p_from_amount)*0.0005) then raise exception 'Monto origen/tasa inconsistentes'; end if;
 if abs(expected_to-p_to_amount)>greatest(0.01,abs(p_to_amount)*0.0005) then raise exception 'Monto destino/tasa inconsistentes'; end if;
 if fa.balance<p_from_amount then raise exception 'Saldo insuficiente'; end if;
 ref:=coalesce(nullif(btrim(p_reference),''),public.atlas_internal_document_number('CASH_TRANSFER','TF-'));
 update public.cash_accounts set balance=balance-p_from_amount where id=fa.id;
 update public.cash_accounts set balance=balance+p_to_amount where id=ta.id;
 insert into public.cash_movements(company_id,account_id,direction,amount,currency,reference,description,created_by)
 values
 (cid,fa.id,'OUT',p_from_amount,upper(fa.currency),ref,coalesce(nullif(btrim(p_note),''),'Transferencia entre cuentas'),auth.uid()),
 (cid,ta.id,'IN',p_to_amount,upper(ta.currency),ref,coalesce(nullif(btrim(p_note),''),'Transferencia entre cuentas'),auth.uid());
 insert into public.cash_transfers(id,company_id,from_account_id,to_account_id,reference,from_amount,from_currency,to_amount,to_currency,base_amount_usd,from_rate,to_rate,note,created_by)
 values(tid,cid,fa.id,ta.id,ref,p_from_amount,upper(fa.currency),p_to_amount,upper(ta.currency),p_base_amount_usd,p_from_rate,p_to_rate,p_note,auth.uid());
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','CASH_TRANSFER',tid::text,jsonb_build_object('reference',ref,'from_account',fa.id,'to_account',ta.id,'from_amount',p_from_amount,'from_currency',fa.currency,'to_amount',p_to_amount,'to_currency',ta.currency,'base_usd',p_base_amount_usd,'from_rate',p_from_rate,'to_rate',p_to_rate));
 return jsonb_build_object('id',tid,'reference',ref,'base_amount_usd',p_base_amount_usd);
end $$;

revoke all on function public.atlas_create_expense_fx(uuid,text,text,numeric,numeric,numeric,text) from public;
grant execute on function public.atlas_create_expense_fx(uuid,text,text,numeric,numeric,numeric,text) to authenticated;
revoke all on function public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text) from public;
grant execute on function public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text) to authenticated;

-- ============================================================
-- BLOQUE 14/14: sql/ATLAS_FINANCIAL_INTEGRITY_PHASE70.sql
-- ============================================================
-- ATLAS Fase 70 — Diagnóstico financiero integral
-- Valida invariantes críticas sin modificar datos. Útil antes de liberar una migración a producción.

create or replace function public.atlas_financial_integrity_check()
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id();
 issues jsonb:='[]'::jsonb;
 r record;
 n integer:=0;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('audit.view') or public.has_permission('settings.manage') or public.has_permission('*')) then
   raise exception 'Permiso insuficiente';
 end if;

 -- 1. Asientos descuadrados.
 for r in
   select je.id,je.reference,
          round(coalesce(sum(jl.debit),0),4) debit,
          round(coalesce(sum(jl.credit),0),4) credit
   from public.journal_entries je
   left join public.journal_lines jl on jl.entry_id=je.id
   where je.company_id=cid
   group by je.id,je.reference
   having abs(coalesce(sum(jl.debit),0)-coalesce(sum(jl.credit),0))>0.009
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','JOURNAL_UNBALANCED','reference',r.reference,'debit',r.debit,'credit',r.credit));
 end loop;

 -- 2. Movimientos de caja cuya moneda no coincide con la cuenta.
 for r in
   select cm.id,cm.reference,cm.currency movement_currency,ca.currency account_currency
   from public.cash_movements cm
   join public.cash_accounts ca on ca.id=cm.account_id and ca.company_id=cm.company_id
   where cm.company_id=cid and upper(coalesce(cm.currency,''))<>upper(coalesce(ca.currency,''))
 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','CASH_CURRENCY_MISMATCH','reference',r.reference,'movement_currency',r.movement_currency,'account_currency',r.account_currency));
 end loop;

 -- 3. Saldos de caja negativos: se consideran error mientras ATLAS no tenga sobregiro explícito.
 for r in select id,name,currency,balance from public.cash_accounts where company_id=cid and active=true and balance<0 loop
   issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_CASH','account',r.name,'currency',r.currency,'balance',r.balance));
 end loop;

 -- 4. Transferencias financieras: verifica que ambos lados representen el mismo valor USD.
 if to_regclass('public.cash_transfers') is not null then
  for r in
    select id,reference,from_amount,from_currency,to_amount,to_currency,base_amount_usd,from_rate,to_rate
    from public.cash_transfers where company_id=cid
  loop
    if r.base_amount_usd<=0 or r.from_rate<=0 or r.to_rate<=0
       or abs((case when upper(r.from_currency)='USD' then r.from_amount else r.from_amount/r.from_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
       or abs((case when upper(r.to_currency)='USD' then r.to_amount else r.to_amount/r.to_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
    then
      issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','TRANSFER_FX_MISMATCH','reference',r.reference));
    end if;
  end loop;
 end if;

 -- 5. Gastos con snapshot FX incoherente.
 for r in
   select id,reference,amount,currency,base_amount_usd,exchange_rate
   from public.expenses
   where company_id=cid and base_amount_usd is not null
 loop
   if r.base_amount_usd<=0 or coalesce(r.exchange_rate,0)<=0
      or abs((case when upper(r.currency)='USD' then r.amount else r.amount/r.exchange_rate end)-r.base_amount_usd)>greatest(0.01,abs(r.base_amount_usd)*0.0005)
   then
     issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','EXPENSE_FX_MISMATCH','reference',r.reference));
   end if;
 end loop;

 -- 6. Créditos o cuentas por cobrar/pagar nunca pueden quedar negativos.
 select count(*) into n from public.receivables where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_RECEIVABLES','count',n)); end if;
 select count(*) into n from public.payables where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_PAYABLES','count',n)); end if;
 select count(*) into n from public.customer_credits where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_CUSTOMER_CREDITS','count',n)); end if;
 select count(*) into n from public.supplier_credits where company_id=cid and balance<0;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('severity','ERROR','code','NEGATIVE_SUPPLIER_CREDITS','count',n)); end if;

 return jsonb_build_object(
   'ok',jsonb_array_length(issues)=0,
   'checked_at',now(),
   'company_id',cid,
   'issue_count',jsonb_array_length(issues),
   'issues',issues
 );
end $$;

revoke all on function public.atlas_financial_integrity_check() from public;
grant execute on function public.atlas_financial_integrity_check() to authenticated;

-- ============================================================
-- Verificación estructural final. Si algo falta, toda la transacción revierte.
-- ============================================================
do $$
declare missing text[] := array[]::text[];
begin
  if to_regclass('public.cash_transfers') is null then missing:=array_append(missing,'cash_transfers'); end if;
  if to_regprocedure('public.atlas_post_journal(uuid,text,text,jsonb)') is null then missing:=array_append(missing,'atlas_post_journal'); end if;
  if to_regprocedure('public.atlas_fx_amount(numeric,text,text,numeric)') is null then missing:=array_append(missing,'atlas_fx_amount'); end if;
  if to_regprocedure('public.atlas_create_sale(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text)') is null then missing:=array_append(missing,'atlas_create_sale'); end if;
  if to_regprocedure('public.atlas_create_purchase(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,uuid,jsonb,text)') is null then missing:=array_append(missing,'atlas_create_purchase'); end if;
  if to_regprocedure('public.atlas_return_sale(uuid,uuid,numeric)') is null then missing:=array_append(missing,'atlas_return_sale'); end if;
  if to_regprocedure('public.atlas_return_purchase(uuid,uuid,numeric)') is null then missing:=array_append(missing,'atlas_return_purchase'); end if;
  if to_regprocedure('public.atlas_cancel_sale(uuid,text)') is null then missing:=array_append(missing,'atlas_cancel_sale'); end if;
  if to_regprocedure('public.atlas_cancel_purchase(uuid,text)') is null then missing:=array_append(missing,'atlas_cancel_purchase'); end if;
  if to_regprocedure('public.atlas_cash_transfer(uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text)') is null then missing:=array_append(missing,'atlas_cash_transfer'); end if;
  if to_regprocedure('public.atlas_cash_close(uuid,numeric,text)') is null then missing:=array_append(missing,'atlas_cash_close'); end if;
  if to_regprocedure('public.atlas_create_expense_fx(uuid,text,text,numeric,numeric,numeric,text)') is null then missing:=array_append(missing,'atlas_create_expense_fx'); end if;
  if to_regprocedure('public.atlas_financial_integrity_check()') is null then missing:=array_append(missing,'atlas_financial_integrity_check'); end if;
  if cardinality(missing)>0 then
    raise exception 'ATLAS verificación final falló: %', array_to_string(missing,', ');
  end if;
end $$;

commit;

-- Fin del instalador consolidado ATLAS F55 → F73.
