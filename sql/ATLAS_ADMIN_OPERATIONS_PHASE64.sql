-- ATLAS Fase 64 — Operaciones administrativas remotas
-- Cierra dos fugas de estado local: ajuste de inventario y alta de cuenta financiera.

insert into public.accounting_accounts(company_id,code,name,type,active)
select c.id,'5.2.02','Ajustes de inventario','Gasto',true from public.companies c
on conflict(company_id,code) do nothing;

create or replace function public.atlas_adjust_inventory(
 p_branch_id uuid,p_product_id uuid,p_new_stock numeric,p_reason text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
 cid uuid:=public.current_company_id(); old_stock numeric; delta numeric; cost numeric; ref text;
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
 update public.inventory set stock=p_new_stock
 where company_id=cid and branch_id=p_branch_id and product_id=p_product_id;
 ref:=public.next_document_number('INVENTORY_ADJUSTMENT','AJ-');
 -- Contabilidad en USD usando costo actual del producto como valoración del ajuste.
 if coalesce(cost,0)>0 then
   if delta>0 then
     perform public.atlas_post_journal(cid,ref,'Ajuste de inventario: '||p_reason,jsonb_build_array(
       jsonb_build_object('account_code','1.1.03','debit',round(delta*cost,4),'credit',0),
       jsonb_build_object('account_code','5.2.02','debit',0,'credit',round(delta*cost,4))));
   else
     perform public.atlas_post_journal(cid,ref,'Ajuste de inventario: '||p_reason,jsonb_build_array(
       jsonb_build_object('account_code','5.2.02','debit',round(abs(delta)*cost,4),'credit',0),
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
