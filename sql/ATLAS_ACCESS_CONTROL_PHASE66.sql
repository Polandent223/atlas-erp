-- ATLAS Fase 66 — Usuarios, roles, permisos y configuración remota
-- No crea usuarios de auth directamente: eso requiere un flujo administrativo seguro.

alter table public.companies add column if not exists phone text;
alter table public.companies add column if not exists email text;
alter table public.companies add column if not exists display_currency text not null default 'USD';

create or replace function public.atlas_access_snapshot()
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); result jsonb;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then
   -- Un usuario normal solo necesita sus propios datos; no exponer directorio completo.
   select jsonb_build_object(
     'users',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'status',p.status,'role_id',ur.role_id,'branch_ids',coalesce((select jsonb_agg(ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb))),'[]'::jsonb),
     'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'permissions',r.permissions)) from public.roles r where r.company_id=cid),'[]'::jsonb)
   ) into result
   from public.profiles p left join public.user_roles ur on ur.user_id=p.id
   where p.id=auth.uid() and p.company_id=cid;
   return coalesce(result,jsonb_build_object('users','[]'::jsonb,'roles','[]'::jsonb));
 end if;

 select jsonb_build_object(
   'users',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'name',p.full_name,'status',p.status,'role_id',ur.role_id,
      'branch_ids',coalesce((select jsonb_agg(ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb)
   ) order by p.full_name) from public.profiles p left join public.user_roles ur on ur.user_id=p.id where p.company_id=cid),'[]'::jsonb),
   'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'permissions',r.permissions) order by r.name) from public.roles r where r.company_id=cid),'[]'::jsonb)
 ) into result;
 return result;
end $$;

create or replace function public.atlas_create_role(p_name text,p_permissions jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); rid uuid:=gen_random_uuid(); perms jsonb:=coalesce(p_permissions,'[]'::jsonb);
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if jsonb_typeof(perms)<>'array' then raise exception 'Permisos inválidos'; end if;
 if exists(select 1 from public.roles where company_id=cid and lower(name)=lower(btrim(p_name))) then raise exception 'Ya existe ese rol'; end if;
 insert into public.roles(id,company_id,name,permissions) values(rid,cid,btrim(p_name),perms);
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','ROLE',rid::text,jsonb_build_object('name',p_name,'permissions',perms));
 return jsonb_build_object('id',rid,'name',btrim(p_name));
end $$;

create or replace function public.atlas_update_role(p_role_id uuid,p_name text,p_permissions jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); perms jsonb:=coalesce(p_permissions,'[]'::jsonb);
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if jsonb_typeof(perms)<>'array' then raise exception 'Permisos inválidos'; end if;
 update public.roles set name=coalesce(nullif(btrim(coalesce(p_name,'')),''),name),permissions=perms
 where id=p_role_id and company_id=cid;
 if not found then raise exception 'Rol no encontrado'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','ROLE',p_role_id::text,jsonb_build_object('name',p_name,'permissions',perms));
 return jsonb_build_object('id',p_role_id);
end $$;

create or replace function public.atlas_assign_user_access(p_user_id uuid,p_role_id uuid,p_branch_ids uuid[],p_active boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); b uuid;
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and company_id=cid) then raise exception 'Usuario no pertenece a la empresa'; end if;
 if not exists(select 1 from public.roles where id=p_role_id and company_id=cid) then raise exception 'Rol inválido'; end if;
 if p_user_id=auth.uid() and p_active=false then raise exception 'No puedes desactivar tu propia sesión'; end if;
 foreach b in array coalesce(p_branch_ids,array[]::uuid[]) loop
   if not exists(select 1 from public.branches where id=b and company_id=cid and active=true) then raise exception 'Sucursal inválida'; end if;
 end loop;
 insert into public.user_roles(user_id,role_id) values(p_user_id,p_role_id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 delete from public.user_branches where user_id=p_user_id;
 insert into public.user_branches(user_id,branch_id)
 select p_user_id,x from unnest(coalesce(p_branch_ids,array[]::uuid[])) x;
 update public.profiles set status=case when p_active then 'ACTIVE' else 'INACTIVE' end where id=p_user_id and company_id=cid;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','USER_ACCESS',p_user_id::text,jsonb_build_object('role_id',p_role_id,'branch_ids',p_branch_ids,'active',p_active));
 return jsonb_build_object('id',p_user_id,'active',p_active);
end $$;

create or replace function public.atlas_update_company(p_name text,p_tax_id text,p_phone text,p_email text,p_country text,p_base_currency text,p_display_currency text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id(); base text:=upper(btrim(coalesce(p_base_currency,'USD'))); disp text:=upper(btrim(coalesce(p_display_currency,'USD')));
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if base not in ('USD','VES','EUR','USDT') or disp not in ('USD','VES','EUR','USDT') then raise exception 'Moneda inválida'; end if;
 update public.companies set name=btrim(p_name),tax_id=nullif(btrim(coalesce(p_tax_id,'')),''),phone=nullif(btrim(coalesce(p_phone,'')),''),email=nullif(btrim(coalesce(p_email,'')),''),country=upper(coalesce(nullif(btrim(p_country),''),'VE')),base_currency=base,display_currency=disp where id=cid;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','COMPANY',cid::text,jsonb_build_object('name',p_name,'base_currency',base,'display_currency',disp));
 return jsonb_build_object('id',cid,'name',btrim(p_name));
end $$;

create or replace function public.atlas_update_branch(p_branch_id uuid,p_name text,p_city text,p_active boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare cid uuid:=public.current_company_id();
begin
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 update public.branches set name=coalesce(nullif(btrim(coalesce(p_name,'')),''),name),city=nullif(btrim(coalesce(p_city,'')),''),active=coalesce(p_active,active)
 where id=p_branch_id and company_id=cid;
 if not found then raise exception 'Sucursal no encontrada'; end if;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','BRANCH',p_branch_id::text,jsonb_build_object('name',p_name,'city',p_city,'active',p_active));
 return jsonb_build_object('id',p_branch_id);
end $$;

revoke all on function public.atlas_access_snapshot() from public;
revoke all on function public.atlas_create_role(text,jsonb) from public;
revoke all on function public.atlas_update_role(uuid,text,jsonb) from public;
revoke all on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) from public;
revoke all on function public.atlas_update_company(text,text,text,text,text,text,text) from public;
revoke all on function public.atlas_update_branch(uuid,text,text,boolean) from public;
grant execute on function public.atlas_access_snapshot() to authenticated;
grant execute on function public.atlas_create_role(text,jsonb) to authenticated;
grant execute on function public.atlas_update_role(uuid,text,jsonb) to authenticated;
grant execute on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) to authenticated;
grant execute on function public.atlas_update_company(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.atlas_update_branch(uuid,text,text,boolean) to authenticated;