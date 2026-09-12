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
