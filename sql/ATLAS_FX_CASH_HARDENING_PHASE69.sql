-- ATLAS Fase 69 / corrección F72 — Endurecimiento FX de caja y gastos multimoneda
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

-- Reemplaza la transferencia F68 añadiendo validación de coherencia FX en servidor.
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
 select * into fa from public.cash_accounts where id=p_from_account and company_id=cid and active=true for update;
 select * into ta from public.cash_accounts where id=p_to_account and company_id=cid and active=true for update;
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
