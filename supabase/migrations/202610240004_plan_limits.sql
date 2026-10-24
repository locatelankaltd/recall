-- Authoritative product limits. No client/SDK/webhook paid flags can change them.
create function recall_private.plan_limits(p_owner uuid) returns jsonb
language sql stable set search_path='' as $$
 with plan as (
  select coalesce((select e.active and e.environment in ('production','sandbox')
    and e.verified_at>now()-interval '24 hours'
    and (e.expires_at is null or e.expires_at>now())
    from recall_private.entitlements e where e.owner_id=p_owner),false) as pro
 ) select jsonb_build_object('projectLimit',case when pro then 100 else 3 end,
   'analysisDailyLimit',case when pro then 20 else 5 end) from plan
$$;
revoke all on function recall_private.plan_limits(uuid) from public,anon,authenticated;

-- Retain the previously tested create/idempotency implementation as a private
-- helper. Only the new owner-locked public wrapper can be called by the app.
alter function public.recall_create_project(text,text,text,text) set schema recall_private;
alter function recall_private.recall_create_project(text,text,text,text) rename to create_project_snapshot;
revoke all on function recall_private.create_project_snapshot(text,text,text,text) from public,anon,authenticated;
create function public.recall_create_project(p_title text,p_client_name text,p_category text,p_request_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); v_limit int;
begin
 perform recall_private.check_request(p_request_id);
 -- One lock covers all project creations for this account, not just one request.
 perform pg_advisory_xact_lock(hashtextextended('recall-project-limit:'||v_owner::text,0));
 -- An identical retry must return its original snapshot even at the plan limit.
 -- The private helper still checks the exact payload fingerprint on every retry.
 if exists(select 1 from recall_private.requests where owner_id=v_owner and request_id=p_request_id) then
  return recall_private.create_project_snapshot(p_title,p_client_name,p_category,p_request_id);
 end if;
 v_limit:=(recall_private.plan_limits(v_owner)->>'projectLimit')::int;
 if (select count(*) from recall_private.projects where owner_id=v_owner)>=v_limit then
  raise exception using errcode='54000',message='Your project limit has been reached. Free supports 3 projects; verified Pro supports 100.';
 end if;
 return recall_private.create_project_snapshot(p_title,p_client_name,p_category,p_request_id);
end $$;
revoke all on function public.recall_create_project(text,text,text,text) from public,anon,authenticated;
grant execute on function public.recall_create_project(text,text,text,text) to authenticated;

create or replace function public.recall_entitlement() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); e recall_private.entitlements%rowtype; v_active boolean; v_fresh boolean; v_result jsonb;
begin
 select * into e from recall_private.entitlements where owner_id=v_owner;
 if not found then
  v_result:=jsonb_build_object('entitlement','pro','active',false,'expiresAt',null,'verifiedAt',null,'environment','unknown','status','unverified');
 else
  v_fresh:=e.verified_at>now()-interval '24 hours';
  v_active:=e.active and e.environment in ('production','sandbox') and v_fresh and (e.expires_at is null or e.expires_at>now());
  v_result:=jsonb_build_object('entitlement','pro','active',v_active,'expiresAt',e.expires_at,'verifiedAt',e.verified_at,'environment',e.environment,'status',case when not v_fresh then 'stale' when v_active then 'active' else 'inactive' end);
 end if;
 return v_result||recall_private.plan_limits(v_owner);
end $$;
revoke all on function public.recall_entitlement() from public,anon,authenticated;
grant execute on function public.recall_entitlement() to authenticated;

-- The aggregate count is deliberately not deleted with an account: deleting and
-- recreating accounts must not release spent service budget. It stores no UID.
create table recall_private.analysis_service_usage (
 usage_day date primary key,
 request_count int not null check(request_count between 0 and 100)
);
alter table recall_private.analysis_service_usage enable row level security;
revoke all on recall_private.analysis_service_usage from public,anon,authenticated;
create or replace function public.recall_reserve_analysis(p_user_id uuid,p_daily_limit int default 20)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_today date:=(now() at time zone 'UTC')::date; v_limit int; v_user_count int; v_service_count int;
begin
 if p_user_id is null or p_daily_limit is null or p_daily_limit not between 1 and 100 then
  raise exception using errcode='22023',message='Invalid analysis allowance.';
 end if;
 if not exists(select 1 from auth.users where id=p_user_id) then return false; end if;
 -- Every caller takes service-day then user-day locks in the same order. Both
 -- counters commit together; a denied request consumes neither counter.
 perform pg_advisory_xact_lock(hashtextextended('recall-analysis-service:'||v_today::text,0));
 perform pg_advisory_xact_lock(hashtextextended('recall-analysis-user:'||p_user_id::text||':'||v_today::text,0));
 v_limit:=least((recall_private.plan_limits(p_user_id)->>'analysisDailyLimit')::int,p_daily_limit);
 select request_count into v_user_count from recall_private.analysis_usage where owner_id=p_user_id and usage_day=v_today;
 select request_count into v_service_count from recall_private.analysis_service_usage where usage_day=v_today;
 if coalesce(v_user_count,0)>=v_limit or coalesce(v_service_count,0)>=100 then return false; end if;
 insert into recall_private.analysis_usage(owner_id,usage_day,request_count) values(p_user_id,v_today,1)
 on conflict(owner_id,usage_day) do update set request_count=recall_private.analysis_usage.request_count+1;
 insert into recall_private.analysis_service_usage(usage_day,request_count) values(v_today,1)
 on conflict(usage_day) do update set request_count=recall_private.analysis_service_usage.request_count+1;
 return true;
end $$;
revoke all on function public.recall_reserve_analysis(uuid,int) from public,anon,authenticated;
grant execute on function public.recall_reserve_analysis(uuid,int) to service_role;
