begin;
insert into auth.users(id) values('44444444-4444-4444-4444-444444444444');
set local role authenticated;
do $$ begin
 begin perform public.recall_reserve_analysis('44444444-4444-4444-4444-444444444444',100);
 exception when insufficient_privilege then raise notice 'PASS: authenticated client cannot reserve or change an AI allowance'; return; end;
 raise exception 'Client quota mutation unexpectedly succeeded';
end $$;
reset role;
set local role service_role;
do $$ begin
 if not public.recall_reserve_analysis('44444444-4444-4444-4444-444444444444',2) or not public.recall_reserve_analysis('44444444-4444-4444-4444-444444444444',2) then raise exception 'First quota reservations rejected'; end if;
 if public.recall_reserve_analysis('44444444-4444-4444-4444-444444444444',2) then raise exception 'Exceeded daily quota'; end if;
 raise notice 'PASS: server quota enforces daily per-user analysis bound';
end $$;
reset role;
delete from auth.users where id='44444444-4444-4444-4444-444444444444';
do $$ begin
 if exists(select 1 from recall_private.analysis_usage) then raise exception 'Account deletion left AI usage'; end if;
 raise notice 'PASS: account deletion removes AI usage metadata';
end $$;
rollback;
