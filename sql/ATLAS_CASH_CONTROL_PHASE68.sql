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
