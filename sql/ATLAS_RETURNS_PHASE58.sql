-- ATLAS Fase 58 / corrección F67 — Devolución de venta segura
-- Reemplaza la implementación legacy incompatible con sale_returns F44.
-- Devolución parcial por producto, reintegro de inventario, ajuste CxC/crédito cliente,
-- reverso contable y auditoría. No realiza reembolso de caja automático.

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'2.1.03','Créditos de clientes','Pasivo',true from public.companies c
on conflict(company_id,code) do nothing;

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
   insert into public.customer_credits(company_id,customer_id,balance,currency,reference) values(cid,s.customer_id,credit_amount,'USD',n);
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
