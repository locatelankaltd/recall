-- Paid status can only be written by a trusted server reconciliation.
create table recall_private.entitlements (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null,
  expires_at timestamptz,
  environment text not null check(environment in ('production','sandbox','unknown')),
  observed_at timestamptz not null,
  verified_at timestamptz not null default now()
);
alter table recall_private.entitlements enable row level security;
create policy owner_read on recall_private.entitlements for select to authenticated using(owner_id=(select auth.uid()));
revoke all on recall_private.entitlements from public,anon,authenticated;
create table recall_private.billing_events (
  event_hash text primary key,
  processed_at timestamptz not null default now()
);
alter table recall_private.billing_events enable row level security;
revoke all on recall_private.billing_events from public,anon,authenticated;

create function public.recall_entitlement() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); e recall_private.entitlements%rowtype; v_active boolean; v_fresh boolean;
begin
 select * into e from recall_private.entitlements where owner_id=v_owner;
 if not found then return jsonb_build_object('entitlement','pro','active',false,'expiresAt',null,'verifiedAt',null,'environment','unknown','status','unverified'); end if;
 v_fresh:=e.verified_at>now()-interval '24 hours';
 v_active:=e.active and v_fresh and (e.expires_at is null or e.expires_at>now());
 return jsonb_build_object('entitlement','pro','active',v_active,'expiresAt',e.expires_at,'verifiedAt',e.verified_at,'environment',e.environment,'status',case when not v_fresh then 'stale' when v_active then 'active' else 'inactive' end);
end $$;
create function public.recall_billing_event_seen(p_event_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from recall_private.billing_events where event_hash=encode(extensions.digest(p_event_id,'sha256'),'hex'))
$$;
create function public.recall_apply_billing_state(p_updates jsonb,p_event_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u jsonb; v_owner uuid; v_observed timestamptz; v_expires timestamptz; v_applied int:=0; v_rows int; v_hash text;
begin
 if jsonb_typeof(p_updates) is distinct from 'array' or jsonb_array_length(p_updates) not between 1 and 20 then raise exception using errcode='22023',message='Invalid verified billing update.'; end if;
 if p_event_id is not null then
  if length(p_event_id) not between 1 and 200 then raise exception using errcode='22023',message='Invalid billing event.'; end if;
  v_hash:=encode(extensions.digest(p_event_id,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('billing-event:'||v_hash,0));
  if exists(select 1 from recall_private.billing_events where event_hash=v_hash) then return jsonb_build_object('duplicate',true,'applied',0); end if;
 end if;
 -- Always order owner row locks to keep simultaneous transfer reconciliations deadlock-free.
 for u in select value from jsonb_array_elements(p_updates) order by value->>'ownerId' loop
  if coalesce(u->>'ownerId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or jsonb_typeof(u->'active') is distinct from 'boolean' or coalesce(u->>'environment','') not in ('production','sandbox','unknown') or u->>'observedAt' is null then raise exception using errcode='22023',message='Invalid verified billing values.'; end if;
  v_owner:=(u->>'ownerId')::uuid;
  v_observed:=(u->>'observedAt')::timestamptz;
  v_expires:=(u->>'expiresAt')::timestamptz;
  if v_observed>now()+interval '5 minutes' or v_observed<now()-interval '24 hours' then raise exception using errcode='22023',message='Billing verification must use fresh provider state.'; end if;
  if exists(select 1 from auth.users where id=v_owner) then
   insert into recall_private.entitlements(owner_id,active,expires_at,environment,observed_at) values(v_owner,(u->>'active')::boolean,v_expires,u->>'environment',v_observed)
   on conflict(owner_id) do update set active=excluded.active,expires_at=excluded.expires_at,environment=excluded.environment,observed_at=excluded.observed_at,verified_at=now()
   where recall_private.entitlements.observed_at<=excluded.observed_at;
   get diagnostics v_rows=row_count;
   v_applied:=v_applied+v_rows;
  end if;
 end loop;
 if v_hash is not null then insert into recall_private.billing_events(event_hash) values(v_hash); end if;
 return jsonb_build_object('duplicate',false,'applied',v_applied);
end $$;
revoke all on function public.recall_entitlement() from public,anon,authenticated;
revoke all on function public.recall_billing_event_seen(text) from public,anon,authenticated;
revoke all on function public.recall_apply_billing_state(jsonb,text) from public,anon,authenticated;
grant execute on function public.recall_entitlement() to authenticated;
grant execute on function public.recall_billing_event_seen(text) to service_role;
grant execute on function public.recall_apply_billing_state(jsonb,text) to service_role;
