-- ATLAS Fase 36 — asignación segura de UUID para migración
create or replace function public.prepare_migration_id(
 p_run uuid,p_entity text,p_local_id text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_company uuid; v_id uuid;
begin
 v_company:=public.current_company_id();
 if v_company is null then raise exception 'Usuario sin empresa'; end if;
 if not exists(select 1 from public.migration_runs r where r.id=p_run and r.company_id=v_company and r.created_by=auth.uid())
 then raise exception 'Migración no autorizada'; end if;
 select cloud_id into v_id from public.migration_id_map
 where run_id=p_run and company_id=v_company and entity=p_entity and local_id=p_local_id;
 if v_id is null then
   v_id:=gen_random_uuid();
   insert into public.migration_id_map(run_id,company_id,entity,local_id,cloud_id)
   values(p_run,v_company,p_entity,p_local_id,v_id)
   on conflict(run_id,entity,local_id) do update set cloud_id=public.migration_id_map.cloud_id
   returning cloud_id into v_id;
 end if;
 return v_id;
end $$;
revoke all on function public.prepare_migration_id(uuid,text,text) from public;
grant execute on function public.prepare_migration_id(uuid,text,text) to authenticated;
