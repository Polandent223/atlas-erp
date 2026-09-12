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
