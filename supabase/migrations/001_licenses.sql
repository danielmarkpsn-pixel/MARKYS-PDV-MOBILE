begin;
create schema if not exists markys_private;
revoke all on schema markys_private from public, anon, authenticated;
create table if not exists markys_private.admins (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists markys_private.licenses (
 user_id uuid primary key references auth.users(id) on delete cascade,
 product text not null default 'MARKYS-PDV-MOBILE',
 plan text not null check (plan in ('trial','monthly','annual','lifetime')),
 status text not null default 'pending' check (status in ('pending','active','blocked')),
 expires_at timestamptz,
 device_limit integer not null default 1 check (device_limit between 1 and 100),
 updated_at timestamptz not null default now(),
 check (plan='lifetime' or expires_at is not null)
);
create table if not exists markys_private.devices (
 user_id uuid not null references markys_private.licenses(user_id) on delete cascade,
 device_id uuid not null,
 registered_at timestamptz not null default now(),
 last_seen timestamptz not null default now(),
 primary key(user_id,device_id)
);
create table if not exists markys_private.audit (
 id bigint generated always as identity primary key,
 actor uuid not null,
 target uuid not null,
 action text not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);
alter table markys_private.admins enable row level security;
alter table markys_private.licenses enable row level security;
alter table markys_private.devices enable row level security;
alter table markys_private.audit enable row level security;
revoke all on all tables in schema markys_private from public, anon, authenticated;
create or replace function public.markys_license_check(p_device uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); l markys_private.licenses%rowtype; n integer; t timestamptz := now();
begin
 if u is null or p_device is null then raise exception 'Unauthorized'; end if;
 select * into l from markys_private.licenses where user_id=u for update;
 if not found then return jsonb_build_object('status','pending'); end if;
 if l.status <> 'active' then return jsonb_build_object('status',l.status); end if;
 if l.expires_at is not null and l.expires_at <= t then return jsonb_build_object('status','expired'); end if;
 if not exists(select 1 from markys_private.devices where user_id=u and device_id=p_device) then
   select count(*) into n from markys_private.devices where user_id=u;
   if n>=l.device_limit then return jsonb_build_object('status','device_limit'); end if;
   insert into markys_private.devices(user_id,device_id) values(u,p_device);
 end if;
 update markys_private.devices set last_seen=t where user_id=u and device_id=p_device;
 return jsonb_build_object('status','active','plan',l.plan,'server_time',t,'expires_at',l.expires_at,'offline_until',least(coalesce(l.expires_at,t+interval '72 hours'),t+interval '72 hours'));
end $$;
create or replace function public.markys_admin_set_license(p_user uuid,p_plan text,p_status text,p_expires timestamptz,p_limit integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from markys_private.admins where user_id=auth.uid()) then raise exception 'Unauthorized'; end if;
 insert into markys_private.licenses(user_id,plan,status,expires_at,device_limit)
 values(p_user,p_plan,p_status,p_expires,p_limit)
 on conflict(user_id) do update set plan=excluded.plan,status=excluded.status,expires_at=excluded.expires_at,device_limit=excluded.device_limit,updated_at=now();
 insert into markys_private.audit(actor,target,action,details) values(auth.uid(),p_user,'set_license',jsonb_build_object('plan',p_plan,'status',p_status,'expires_at',p_expires,'device_limit',p_limit));
end $$;
create or replace function public.markys_admin_list()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from markys_private.admins where user_id=auth.uid()) then raise exception 'Unauthorized'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',u.id,'email',u.email,'plan',l.plan,'status',case when l.status='active' and l.expires_at<=now() then 'expired' else coalesce(l.status,'pending') end,'expires_at',l.expires_at,'device_limit',l.device_limit,'devices',(select count(*) from markys_private.devices d where d.user_id=u.id))) from auth.users u left join markys_private.licenses l on l.user_id=u.id),'[]'::jsonb);
end $$;
create or replace function public.markys_admin_reset_devices(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from markys_private.admins where user_id=auth.uid()) then raise exception 'Unauthorized'; end if;
 perform 1 from markys_private.licenses where user_id=p_user for update;
 delete from markys_private.devices where user_id=p_user;
 insert into markys_private.audit(actor,target,action) values(auth.uid(),p_user,'reset_devices');
end $$;
revoke all on function public.markys_license_check(uuid), public.markys_admin_set_license(uuid,text,text,timestamptz,integer), public.markys_admin_list(), public.markys_admin_reset_devices(uuid) from public, anon, authenticated;
grant execute on function public.markys_license_check(uuid), public.markys_admin_set_license(uuid,text,text,timestamptz,integer), public.markys_admin_list(), public.markys_admin_reset_devices(uuid) to authenticated;
commit;
