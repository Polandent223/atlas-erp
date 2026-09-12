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
