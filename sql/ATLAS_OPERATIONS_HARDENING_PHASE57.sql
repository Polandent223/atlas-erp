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
