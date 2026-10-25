begin;
insert into auth.users(id) values('55555555-5555-5555-5555-555555555555'),('66666666-6666-6666-6666-666666666666');
set local role authenticated;
set local request.jwt.claim.sub='55555555-5555-5555-5555-555555555555';
do $$ begin
 if public.recall_entitlement()->>'status'<>'unverified' or (public.recall_entitlement()->>'active')::boolean then raise exception 'Unverified user has paid status'; end if;
 raise notice 'PASS: unverified billing user has no paid access';
 begin perform public.recall_apply_billing_state('[{"ownerId":"55555555-5555-5555-5555-555555555555","active":true}]','forged-event');
 exception when insufficient_privilege then raise notice 'PASS: client cannot forge verified entitlement state'; return; end;
 raise exception 'Client paid write unexpectedly succeeded';
end $$;
reset role;
set local role service_role;
select public.recall_apply_billing_state(jsonb_build_array(jsonb_build_object('ownerId','55555555-5555-5555-5555-555555555555','active',true,'environment','production','expiresAt',now()+interval '1 day','observedAt',now())),'billing-event-0001');
do $$ begin
 if not public.recall_billing_event_seen('billing-event-0001') then raise exception 'Billing event was not deduplicated'; end if;
 raise notice 'PASS: successful webhook event is deduplicated';
end $$;
select public.recall_apply_billing_state(jsonb_build_array(jsonb_build_object('ownerId','55555555-5555-5555-5555-555555555555','active',false,'environment','production','expiresAt',now()-interval '1 day','observedAt',now()-interval '1 minute')),'billing-event-older');
reset role;
set local role authenticated;
set local request.jwt.claim.sub='55555555-5555-5555-5555-555555555555';
do $$ begin
 if not (public.recall_entitlement()->>'active')::boolean then raise exception 'Older provider observation replaced current state'; end if;
 raise notice 'PASS: older provider observation cannot regress newer billing state';
end $$;
set local request.jwt.claim.sub='66666666-6666-6666-6666-666666666666';
do $$ begin
 if (public.recall_entitlement()->>'active')::boolean then raise exception 'Outsider inherited paid status'; end if;
 raise notice 'PASS: entitlement RPC reads only the authenticated owner';
end $$;
reset role;
update recall_private.entitlements set expires_at=now()-interval '1 second' where owner_id='55555555-5555-5555-5555-555555555555';
set local role authenticated;
set local request.jwt.claim.sub='55555555-5555-5555-5555-555555555555';
do $$ begin
 if (public.recall_entitlement()->>'active')::boolean then raise exception 'Expired cached entitlement remained active'; end if;
 raise notice 'PASS: expiry is enforced at entitlement read time';
end $$;
reset role;
update recall_private.entitlements set expires_at=null,verified_at=now()-interval '25 hours';
set local role authenticated;
do $$ begin
 if (public.recall_entitlement()->>'active')::boolean or public.recall_entitlement()->>'status'<>'stale' then raise exception 'Stale cached verification remained active'; end if;
 raise notice 'PASS: stale server billing verification cannot unlock indefinitely';
end $$;
reset role;
delete from auth.users where id='55555555-5555-5555-5555-555555555555';
do $$ begin
 if exists(select 1 from recall_private.entitlements) then raise exception 'Account deletion retained billing identity'; end if;
 raise notice 'PASS: account deletion removes verified billing status';
end $$;
rollback;
