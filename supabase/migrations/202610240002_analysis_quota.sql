-- Server-only reservation before an optional paid analysis request. No source text stored.
create table recall_private.analysis_usage (
  owner_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  request_count int not null check(request_count between 0 and 100),
  primary key(owner_id,usage_day)
);
alter table recall_private.analysis_usage enable row level security;
revoke all on recall_private.analysis_usage from public,anon,authenticated;
create function public.recall_reserve_analysis(p_user_id uuid,p_daily_limit int default 20) returns boolean
language plpgsql security definer set search_path='' as $$
declare v_count int; v_today date:=(now() at time zone 'UTC')::date;
begin
 if p_user_id is null or p_daily_limit is null or p_daily_limit not between 1 and 100 then raise exception using errcode='22023',message='Invalid analysis allowance.'; end if;
 if not exists(select 1 from auth.users where id=p_user_id) then return false; end if;
 insert into recall_private.analysis_usage(owner_id,usage_day,request_count) values(p_user_id,v_today,1)
 on conflict(owner_id,usage_day) do update set request_count=recall_private.analysis_usage.request_count+1
 where recall_private.analysis_usage.request_count<p_daily_limit
 returning request_count into v_count;
 return v_count is not null;
end $$;
revoke all on function public.recall_reserve_analysis(uuid,int) from public,anon,authenticated;
grant execute on function public.recall_reserve_analysis(uuid,int) to service_role;
