-- ATLAS Fase 35 — staging de migración
create table if not exists public.migration_runs(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete cascade,
 created_by uuid not null references public.profiles(id),
 source_schema integer not null,
 status text not null default 'PREPARED',
 local_counts jsonb not null default '{}'::jsonb,
 cloud_counts jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create table if not exists public.migration_id_map(
 run_id uuid not null references public.migration_runs(id) on delete cascade,
 company_id uuid not null references public.companies(id) on delete cascade,
 entity text not null,
 local_id text not null,
 cloud_id uuid not null,
 primary key(run_id,entity,local_id),
 unique(run_id,entity,cloud_id)
);
alter table public.migration_runs enable row level security;
alter table public.migration_id_map enable row level security;
drop policy if exists atlas_migration_runs on public.migration_runs;
create policy atlas_migration_runs on public.migration_runs for all to authenticated
using(company_id=public.current_company_id() and created_by=auth.uid())
with check(company_id=public.current_company_id() and created_by=auth.uid());
drop policy if exists atlas_migration_map on public.migration_id_map;
create policy atlas_migration_map on public.migration_id_map for all to authenticated
using(company_id=public.current_company_id())
with check(company_id=public.current_company_id());
