-- Existing Auth accounts are linked atomically; this does not create credentials.
create or replace function public.atlas_access_snapshot()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare cid uuid:=public.current_company_id(); manager boolean;
begin
 if auth.uid() is null or cid is null then raise exception 'Sesión sin empresa'; end if;
 manager:=public.has_permission('settings.manage') or public.has_permission('*');
 return jsonb_build_object(
 'users',coalesce((select jsonb_agg(jsonb_build_object(
 'id',p.id,'name',p.full_name,'email',u.email,'status',p.status,'role_id',ur.role_id,
 'branch_ids',coalesce((select jsonb_agg(ub.branch_id order by ub.branch_id) from public.user_branches ub where ub.user_id=p.id),'[]'::jsonb)
 ) order by p.full_name,p.id)
 from public.profiles p left join public.user_roles ur on ur.user_id=p.id left join auth.users u on u.id=p.id
 where p.company_id=cid and (manager or p.id=auth.uid())),'[]'::jsonb),
 'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'permissions',r.permissions) order by r.name)
 from public.roles r where r.company_id=cid and (manager or exists(select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role_id=r.id))),'[]'::jsonb),
 'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code,'active',b.active) order by b.name)
 from public.branches b where b.company_id=cid and (manager or public.can_access_branch(b.id))),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.atlas_link_auth_user(p_user_id uuid, p_full_name text, p_role_id uuid, p_branch_ids uuid[], p_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 cid uuid:=public.current_company_id();
 b uuid;
 all_branches boolean:=false;
begin
 if auth.uid() is null then raise exception 'Sesión requerida'; end if;
 if p_active is null then raise exception 'Estado requerido'; end if;
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then
   raise exception 'Permiso insuficiente';
 end if;
 if p_user_id is null then raise exception 'UUID de Auth requerido'; end if;
 if nullif(btrim(coalesce(p_full_name,'')),'') is null then raise exception 'Nombre requerido'; end if;
 if not exists(select 1 from auth.users where id=p_user_id) then
   raise exception 'El usuario no existe en Supabase Authentication';
 end if;
 if p_user_id=auth.uid() then
   raise exception 'Usa la edición de acceso para modificar tu propio usuario';
 end if;
 if exists(select 1 from public.profiles where id=p_user_id and company_id is distinct from cid) then
   raise exception 'El usuario ya pertenece a otra empresa';
 end if;
 if exists(select 1 from public.profiles where id=p_user_id and company_id=cid) then
   raise exception 'El usuario ya está vinculado a esta empresa; usa la edición de acceso';
 end if;
 if not exists(select 1 from public.roles where id=p_role_id and company_id=cid) then
   raise exception 'Rol inválido';
 end if;
 select (permissions ? '*' or permissions ? 'branches.all') into all_branches
 from public.roles where id=p_role_id and company_id=cid;
 foreach b in array coalesce(p_branch_ids,array[]::uuid[]) loop
   if not exists(select 1 from public.branches where id=b and company_id=cid and active=true) then
     raise exception 'Sucursal inválida';
   end if;
 end loop;
 if not all_branches and cardinality(coalesce(p_branch_ids,array[]::uuid[]))=0 then
   raise exception 'Selecciona al menos una sucursal';
 end if;

 insert into public.profiles(id,company_id,full_name,status)
 values(p_user_id,cid,btrim(p_full_name),case when p_active then 'ACTIVE' else 'INACTIVE' end);

 insert into public.user_roles(user_id,role_id) values(p_user_id,p_role_id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 delete from public.user_branches where user_id=p_user_id;
 if not all_branches then
   insert into public.user_branches(user_id,branch_id)
   select distinct p_user_id,x from unnest(coalesce(p_branch_ids,array[]::uuid[])) x;
 end if;

 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'CREATE','USER_PROFILE',p_user_id::text,
   jsonb_build_object('full_name',btrim(p_full_name),'role_id',p_role_id,
     'branch_ids',coalesce(p_branch_ids,array[]::uuid[]),'active',p_active));
 return jsonb_build_object('id',p_user_id,'active',p_active);
end $function$
;
CREATE OR REPLACE FUNCTION public.atlas_assign_user_access(p_user_id uuid, p_role_id uuid, p_branch_ids uuid[], p_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=public.current_company_id(); b uuid; all_branches boolean;
begin
 if auth.uid() is null then raise exception 'Sesión requerida'; end if;
 if p_active is null then raise exception 'Estado requerido'; end if;
 if cid is null then raise exception 'Sesión sin empresa'; end if;
 if not (public.has_permission('settings.manage') or public.has_permission('*')) then raise exception 'Permiso insuficiente'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id and company_id=cid) then raise exception 'Usuario no pertenece a la empresa'; end if;
 if not exists(select 1 from public.roles where id=p_role_id and company_id=cid) then raise exception 'Rol inválido'; end if;
 if p_user_id=auth.uid() and p_active=false then raise exception 'No puedes desactivar tu propia sesión'; end if;
 select (permissions ? '*' or permissions ? 'branches.all') into all_branches from public.roles where id=p_role_id and company_id=cid;
 if not all_branches and cardinality(coalesce(p_branch_ids,array[]::uuid[]))=0 then raise exception 'Selecciona al menos una sucursal'; end if;
 if p_user_id=auth.uid() and not exists(select 1 from public.roles where id=p_role_id and (permissions ? '*' or permissions ? 'settings.manage')) then raise exception 'No puedes retirar tu propio permiso de administración'; end if;
 foreach b in array coalesce(p_branch_ids,array[]::uuid[]) loop
   if not exists(select 1 from public.branches where id=b and company_id=cid and active=true) then raise exception 'Sucursal inválida'; end if;
 end loop;
 insert into public.user_roles(user_id,role_id) values(p_user_id,p_role_id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 delete from public.user_branches where user_id=p_user_id;
 if not all_branches then
 insert into public.user_branches(user_id,branch_id)
 select distinct p_user_id,x from unnest(coalesce(p_branch_ids,array[]::uuid[])) x;
 end if;
 update public.profiles set status=case when p_active then 'ACTIVE' else 'INACTIVE' end where id=p_user_id and company_id=cid;
 insert into public.audit_log(company_id,user_id,action,entity,entity_id,detail)
 values(cid,auth.uid(),'UPDATE','USER_ACCESS',p_user_id::text,jsonb_build_object('role_id',p_role_id,'branch_ids',coalesce(p_branch_ids,array[]::uuid[]),'active',p_active));
 return jsonb_build_object('id',p_user_id,'active',p_active);
end $function$
;
revoke execute on function public.atlas_access_snapshot() from public,anon;
grant execute on function public.atlas_access_snapshot() to authenticated;
revoke execute on function public.atlas_link_auth_user(uuid,text,uuid,uuid[],boolean) from public,anon;
grant execute on function public.atlas_link_auth_user(uuid,text,uuid,uuid[],boolean) to authenticated;
revoke execute on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) from public,anon;
grant execute on function public.atlas_assign_user_access(uuid,uuid,uuid[],boolean) to authenticated;

