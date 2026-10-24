begin;
create function pg_temp.limit_assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
 raise notice 'PASS: %',label;
end $$;
insert into auth.users(id) values('77777777-7777-7777-7777-777777777777'),('88888888-8888-8888-8888-888888888888'),('99999999-9999-9999-9999-999999999999');
set local role authenticated;
set local request.jwt.claim.sub='77777777-7777-7777-7777-777777777777';
select pg_temp.limit_assert(public.recall_entitlement()->>'projectLimit'='3' and public.recall_entitlement()->>'analysisDailyLimit'='5','missing RevenueCat verification defaults to Free project and AI limits');
do $$ declare i int; begin
 for i in 1..3 loop perform public.recall_create_project('Free project '||i,'Client','Creative','free-create-000'||i); end loop;
 begin perform public.recall_create_project('Fourth free project','Client','Creative','free-create-0004');
 exception when sqlstate '54000' then raise notice 'PASS: fourth Free project is rejected by the server'; return; end;
 raise exception 'Fourth Free project exceeded the plan cap';
end $$;
select pg_temp.limit_assert(public.recall_create_project('Free project 1','Client','Creative','free-create-0001')->>'version'='1','identical project creation replay works at the plan limit');
reset role;
-- Even a temporary schema grant must not expose the former unlimited helper.
grant usage on schema recall_private to authenticated;
set local role authenticated;
do $$ begin
 begin perform recall_private.create_project_snapshot('Bypass','Client','Creative','free-bypass-0001');
 exception when insufficient_privilege then raise notice 'PASS: client cannot call the private uncapped creation helper'; return; end;
 raise exception 'Private project limit helper was callable';
end $$;
reset role;
revoke usage on schema recall_private from authenticated;
set local role service_role;
do $$ declare i int; begin
 for i in 1..5 loop
  if not public.recall_reserve_analysis('77777777-7777-7777-7777-777777777777',100) then raise exception 'Free reservation % rejected',i; end if;
 end loop;
 if public.recall_reserve_analysis('77777777-7777-7777-7777-777777777777',100) then raise exception 'Admin cap bypassed Free daily allowance'; end if;
 raise notice 'PASS: Free AI allowance is five even when admin upper cap is 100';
end $$;
select public.recall_apply_billing_state(jsonb_build_array(jsonb_build_object('ownerId','88888888-8888-8888-8888-888888888888','active',true,'environment','production','expiresAt',now()+interval '1 day','observedAt',now())),'plan-pro-event');
reset role;
set local role authenticated;
set local request.jwt.claim.sub='88888888-8888-8888-8888-888888888888';
select pg_temp.limit_assert(public.recall_entitlement()->>'projectLimit'='100' and public.recall_entitlement()->>'analysisDailyLimit'='20','fresh verified Pro has 100 projects and twenty daily AI requests');
do $$ declare i int; begin
 for i in 1..100 loop perform public.recall_create_project('Pro project '||i,'Client','Creative','pro-create-'||lpad(i::text,4,'0')); end loop;
 begin perform public.recall_create_project('Pro project 101','Client','Creative','pro-create-0101');
 exception when sqlstate '54000' then raise notice 'PASS: verified Pro project limit is enforced at 100'; return; end;
 raise exception 'Pro exceeded 100 projects';
end $$;
reset role;
set local role service_role;
do $$ declare i int; begin
 for i in 1..20 loop
  if not public.recall_reserve_analysis('88888888-8888-8888-8888-888888888888',100) then raise exception 'Pro reservation % rejected',i; end if;
 end loop;
 if public.recall_reserve_analysis('88888888-8888-8888-8888-888888888888',100) then raise exception 'Pro exceeded daily AI plan cap'; end if;
 raise notice 'PASS: Pro AI allowance is twenty and cannot be raised by admin upper cap';
end $$;
reset role;
update recall_private.entitlements set expires_at=now()-interval '1 second' where owner_id='88888888-8888-8888-8888-888888888888';
set local role authenticated;
select pg_temp.limit_assert(public.recall_entitlement()->>'projectLimit'='3' and public.recall_entitlement()->>'analysisDailyLimit'='5','expired Pro immediately falls back to Free limits');
do $$ begin
 begin perform public.recall_create_project('Expired Pro addition','Client','Creative','pro-expired-create');
 exception when sqlstate '54000' then raise notice 'PASS: expired Pro cannot add projects beyond the Free limit'; return; end;
 raise exception 'Expired Pro bypassed Free project cap';
end $$;
reset role;
update recall_private.entitlements set expires_at=null,verified_at=now()-interval '25 hours';
set local role authenticated;
select pg_temp.limit_assert(public.recall_entitlement()->>'projectLimit'='3','stale Pro verification uses the Free project limit');
reset role;
set local role service_role;
do $$ begin
 if not public.recall_reserve_analysis('99999999-9999-9999-9999-999999999999',1) then raise exception 'First admin-capped request failed'; end if;
 if public.recall_reserve_analysis('99999999-9999-9999-9999-999999999999',1) then raise exception 'Admin cap did not lower allowance'; end if;
 raise notice 'PASS: administrator upper cap can lower but cannot raise plan allowances';
end $$;
reset role;
-- Seed an aggregate budget boundary without using provider calls.
update recall_private.analysis_service_usage set request_count=100;
set local role service_role;
select pg_temp.limit_assert(not public.recall_reserve_analysis('99999999-9999-9999-9999-999999999999',5),'combined AI service budget blocks account fanout at 100 UTC-day requests');
reset role;
select pg_temp.limit_assert((select request_count from recall_private.analysis_usage where owner_id='99999999-9999-9999-9999-999999999999')=1,'denied service budget reservation does not consume a user request');
grant usage on schema recall_private to authenticated;
grant select on recall_private.analysis_service_usage to authenticated;
set local role authenticated;
select pg_temp.limit_assert((select count(*) from recall_private.analysis_service_usage)=0,'RLS hides aggregate usage even with an accidental read grant');
reset role;
revoke usage on schema recall_private from authenticated;
revoke select on recall_private.analysis_service_usage from authenticated;
delete from auth.users where id='99999999-9999-9999-9999-999999999999';
select pg_temp.limit_assert((select request_count from recall_private.analysis_service_usage)=100,'account deletion does not release spent aggregate service budget');
rollback;
