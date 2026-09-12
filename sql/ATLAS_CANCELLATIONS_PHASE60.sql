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
