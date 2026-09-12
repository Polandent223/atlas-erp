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
