begin;
create function pg_temp.receipt_assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
 raise notice 'PASS: %',label;
end $$;
insert into auth.users(id) values('cccccccc-cccc-cccc-cccc-cccccccccccc');
set local role authenticated;
set local request.jwt.claim.sub='cccccccc-cccc-cccc-cccc-cccccccccccc';
select public.recall_create_project('Private receipt project','Private client','Creative','receipt-create-0001')->'project'->>'id' as receipt_project \gset
select public.recall_mutate_project(:'receipt_project',1,'add_item','{"item":{"id":"receipt-a","title":"Original A"}}','receipt-add-0001');
select public.recall_mutate_project(:'receipt_project',2,'add_item','{"item":{"id":"receipt-b","title":"Original B"}}','receipt-add-0002');
select public.recall_mutate_project(:'receipt_project',3,'propose_change','{"items":[{"id":"receipt-a","title":"Changed A"},{"id":"receipt-b","title":"Changed B"}],"evidence":[{"id":"receipt-source","text":"Private source context","language":"en","kind":"originalText"}]}','receipt-proposal-0001')->'project'->'proposals'->0->>'id' as receipt_revision \gset
select public.recall_create_review_link(:'receipt_project',:'receipt_revision','client',array['receipt-a']) as receipt_link_a \gset
select public.recall_create_review_link(:'receipt_project',:'receipt_revision','client',array['receipt-b']) as receipt_link_b \gset
select public.recall_create_review_link(:'receipt_project',:'receipt_revision','client') as receipt_link_unused \gset
reset role;
set local role anon;
select public.recall_respond_review(:'receipt_link_a'::jsonb->>'token','confirm','','receipt-response-a') as committed_a \gset
select public.recall_respond_review(:'receipt_link_b'::jsonb->>'token','confirm','','receipt-response-b') as committed_b \gset
reset role;
update recall_private.review_links set revoked_at=now() where id=:'receipt_link_a'::jsonb->>'id';
update recall_private.review_links set expires_at=now()-interval '1 second' where id in (:'receipt_link_b'::jsonb->>'id',:'receipt_link_unused'::jsonb->>'id');
set local role anon;
select pg_temp.receipt_assert(public.recall_respond_review(:'receipt_link_a'::jsonb->>'token','confirm','','receipt-response-a')=:'committed_a'::jsonb,'identical committed response retry returns its receipt after revocation');
select pg_temp.receipt_assert(public.recall_respond_review(:'receipt_link_b'::jsonb->>'token','confirm','','receipt-response-b')=:'committed_b'::jsonb,'identical committed response retry returns its receipt after expiry');
select pg_temp.receipt_assert(not (:'committed_b'::jsonb ?| array['projectTitle','changes','evidence','note','participantName']),'expired/revoked committed replay exposes only a minimal receipt');
reset role;
create function pg_temp.expect_receipt_error(statement text,expected_state text,label text) returns void language plpgsql as $$ begin
 begin execute statement; exception when others then
  if sqlstate=expected_state then raise notice 'PASS: %',label; return; end if;
  raise exception 'FAIL: % expected % got %',label,expected_state,sqlstate;
 end;
 raise exception 'FAIL: % unexpectedly succeeded',label;
end $$;
set local role anon;
select pg_temp.expect_receipt_error(format('select public.recall_respond_review(%L,''decline'','''',''receipt-response-a'')',:'receipt_link_a'::jsonb->>'token'),'40001','closed-token replay cannot change an already committed response');
select pg_temp.expect_receipt_error(format('select public.recall_respond_review(%L,''confirm'','''',''receipt-new-request'')',:'receipt_link_unused'::jsonb->>'token'),'P0002','uncommitted expired link cannot create a response');
select pg_temp.expect_receipt_error(format('select public.recall_review_link(%L)',:'receipt_link_b'::jsonb->>'token'),'P0002','receipt replay does not reopen expired source/context access');
reset role;
rollback;
