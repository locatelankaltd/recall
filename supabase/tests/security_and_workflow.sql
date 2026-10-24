\set ON_ERROR_STOP on
begin;
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'FAIL: %',label; end if;
 raise notice 'PASS: %',label;
end $$;
create function pg_temp.expect_error(statement text,expected_state text,label text) returns void language plpgsql as $$
begin
 begin execute statement; exception when others then
  if sqlstate=expected_state then raise notice 'PASS: %',label; return; end if;
  raise exception 'FAIL: % (expected %, got %: %)',label,expected_state,sqlstate,sqlerrm;
 end;
 raise exception 'FAIL: % (statement succeeded)',label;
end $$;
insert into auth.users(id) values('11111111-1111-1111-1111-111111111111'),('22222222-2222-2222-2222-222222222222');
set local role anon;
select pg_temp.expect_error('select public.recall_list_projects()','42501','anonymous user cannot list owner projects');
select pg_temp.expect_error('select * from recall_private.projects','42501','anonymous user cannot read private tables');
select pg_temp.expect_error($q$select public.recall_review_link('not-a-token')$q$,'P0002','invalid bearer token rejected');
reset role;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
set local role authenticated;
select public.recall_create_project('A multilingual project','Client','Creative','request-create-0001') as created \gset
select :'created'::jsonb->'project'->>'id' as project_id \gset
select pg_temp.assert((:'created'::jsonb->>'version')::int=1,'new project starts at version one');
select pg_temp.assert(:'created'::jsonb=public.recall_create_project('A multilingual project','Client','Creative','request-create-0001'),'creation retry is idempotent');
select pg_temp.expect_error($q$select public.recall_create_project('Changed title','Client','Creative','request-create-0001')$q$,'22023','reused request ID with new payload rejected');
select pg_temp.expect_error('select * from recall_private.projects','42501','authenticated client cannot directly read private tables');
select pg_temp.expect_error('insert into recall_private.projects(id,owner_id,title,client_name,category) values(''forged'',''11111111-1111-1111-1111-111111111111'',''x'',''y'',''z'')','42501','authenticated direct writes denied');
select public.recall_mutate_project(:'project_id',1,'add_item','{"item":{"id":"item-a","title":"ஆரம்ப வேலை","details":"Original","ownerId":"you","amountMinor":1000,"currency":"USD"}}','request-add-0001') as added \gset
select public.recall_mutate_project(:'project_id',2,'add_item','{"item":{"id":"item-b","title":"Second item","ownerId":"you"}}','request-add-0002') as added_two \gset
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,1,''set_status'',''{"itemId":"item-a","status":"delivered"}'',''request-stale-0001'')',:'project_id'),'40001','stale CAS mutation rejected');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,3,''set_status'',''{"itemId":"item-a","status":"accepted"}'',''request-self-accept'')',:'project_id'),'42501','owner cannot self-accept delivery');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,3,''add_item'',''{"item":{"id":"bad","title":"Bad","amountMinor":-1}}'',''request-negative'')',:'project_id'),'22023','negative amount rejected');
select public.recall_mutate_project(:'project_id',3,'set_status','{"itemId":"item-a","status":"delivered"}','request-status-0001') as delivered \gset
select public.recall_mutate_project(:'project_id',4,'propose_change','{"items":[{"id":"item-a","title":"Updated scope","ownerId":"you","amountMinor":1200,"currency":"USD"},{"id":"item-b","title":"Second update","ownerId":"you"}],"evidence":[{"id":"source-a","text":"Please change both tasks. مصدر أصلي","language":"ar","kind":"originalText"}]}','request-propose-0001') as proposed \gset
select :'proposed'::jsonb->'project'->'proposals'->0->>'id' as revision_id \gset
select pg_temp.assert(:'proposed'::jsonb->'project'->'currentRevision'->'items'->0->>'title'='ஆரம்ப வேலை','proposal preserves current plan');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,5,''confirm'',%L::jsonb,''request-forged-0001'')',:'project_id',jsonb_build_object('revisionId',:'revision_id','actorId','client')::text),'42501','owner cannot forge client confirmation');
select public.recall_create_review_link(:'project_id',:'revision_id','client',array['item-a']) as link_a \gset
select public.recall_create_review_link(:'project_id',:'revision_id','client',array['item-b']) as link_b \gset
select pg_temp.assert(not(public.recall_list_review_links(:'project_id')::text like '%token%'),'owner link list exposes no token or hash');
reset role;
-- The data-at-rest record contains a SHA-256 hash, never the bearer token.
select pg_temp.assert(not exists(select 1 from recall_private.review_links where token_hash=(:'link_a'::jsonb->>'token')),'raw link token is not stored');
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
set local role authenticated;
select pg_temp.assert(public.recall_list_projects()='[]'::jsonb,'outsider sees no owner projects');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,5,''delete'',''{}'',''request-outsider'')',:'project_id'),'P0002','outsider cannot mutate owner project');
select pg_temp.expect_error(format('select public.recall_create_review_link(%L,%L,''client'')',:'project_id',:'revision_id'),'P0002','outsider cannot mint owner review links');
select pg_temp.expect_error(format('select public.recall_revoke_review_link(%L)',:'link_a'::jsonb->>'id'),'P0002','outsider cannot revoke owner links');
reset role;
-- Grant read access temporarily to test RLS independently from denied API grants.
grant usage on schema recall_private to authenticated;
grant select on all tables in schema recall_private to authenticated;
set local role authenticated;
select pg_temp.assert((select count(*) from recall_private.projects)=0,'RLS hides owner project even if table read granted');
select pg_temp.assert((select count(*) from recall_private.revisions)=0,'RLS hides revision snapshots');
select pg_temp.assert((select count(*) from recall_private.review_links)=0,'RLS hides bearer hashes from outsider');
reset role;
revoke usage on schema recall_private from authenticated;
revoke select on all tables in schema recall_private from authenticated;
set local role anon;
select public.recall_review_link(:'link_a'::jsonb->>'token') as review_a \gset
select pg_temp.assert(jsonb_array_length(:'review_a'::jsonb->'changes')=1 and :'review_a'::jsonb->'changes'->0->>'itemId'='item-a','bearer reads only selected changed item');
select pg_temp.assert(:'review_a'::jsonb->'evidence'='[]'::jsonb and (:'review_a'::jsonb->>'evidenceOmitted')::boolean,'partial review omits unscoped evidence');
select pg_temp.assert(:'review_a'::jsonb->>'identity' like '%not verified%','link holder identity is explicitly unverified');
select public.recall_respond_review(:'link_a'::jsonb->>'token','confirm','','response-first-0001') as receipt_a \gset
select pg_temp.assert(:'receipt_a'::jsonb->>'status'='proposed','partial item confirmation does not publish full revision');
select pg_temp.assert(public.recall_respond_review(:'link_a'::jsonb->>'token','confirm','','response-first-0001')=:'receipt_a'::jsonb,'response retry returns same receipt');
select pg_temp.expect_error(format('select public.recall_respond_review(%L,''decline'','''',''response-other-0001'')',:'link_a'::jsonb->>'token'),'40001','conflicting response replay rejected');
select public.recall_respond_review(:'link_b'::jsonb->>'token','confirm','','response-second-0001') as receipt_b \gset
select pg_temp.assert(:'receipt_b'::jsonb->>'status'='confirmed','all actors and all changed items publish exact revision');
reset role;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
set local role authenticated;
select public.recall_list_projects()->0 as published \gset
select pg_temp.assert(:'published'::jsonb->'project'->'currentRevision'->>'id'=:'revision_id','confirmed version becomes current');
select pg_temp.assert(:'published'::jsonb->'project'->'currentRevision'->'acceptedBy'='["you","client"]'::jsonb,'confirmed snapshot includes all required reviewers');
select pg_temp.assert(:'published'::jsonb->'project'->'itemStatuses'='{}'::jsonb,'changed items reset delivery progress on publication');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,7,''add_item'',''{"item":{"id":"new-item","title":"Cannot append"}}'',''request-shared-add'')',:'project_id'),'22023','shared plans cannot silently alter private baseline');
reset role;
select pg_temp.expect_error(format('update recall_private.revisions set items=''[]'' where id=%L',:'revision_id'),'22023','database trigger rejects rewriting immutable proposal content');
-- Prepare competing proposals, then advance the baseline via one of them.
set local role authenticated;
select public.recall_mutate_project(:'project_id',7,'propose_change','{"items":[{"id":"item-a","title":"Version winner"}],"evidence":[{"id":"winner-source","text":"Updated request","language":"en","kind":"personalRecollection"}]}','request-winner-0001') as winner \gset
select :'winner'::jsonb->'project'->'proposals'->1->>'id' as winner_id \gset
select public.recall_mutate_project(:'project_id',8,'propose_change','{"items":[{"id":"item-a","title":"Version loser"}],"evidence":[{"id":"loser-source","text":"Another request","language":"en","kind":"originalText"}]}','request-loser-0001') as loser \gset
select :'loser'::jsonb->'project'->'proposals'->2->>'id' as loser_id \gset
select public.recall_create_review_link(:'project_id',:'winner_id','client') as winner_link \gset
select public.recall_create_review_link(:'project_id',:'loser_id','client') as loser_link \gset
reset role;
set local role anon;
select pg_temp.assert(jsonb_array_length(public.recall_review_link(:'winner_link'::jsonb->>'token')->'evidence')=1,'full review includes sanitized revision evidence');
select public.recall_respond_review(:'winner_link'::jsonb->>'token','confirm','','response-winner-0001');
select pg_temp.assert(public.recall_review_link(:'loser_link'::jsonb->>'token')->>'status'='stale','competing proposal becomes stale after publication');
select pg_temp.expect_error(format('select public.recall_respond_review(%L,''confirm'','''',''response-stale-0001'')',:'loser_link'::jsonb->>'token'),'40001','stale link cannot replace current revision');
reset role;
set local role authenticated;
select public.recall_mutate_project(:'project_id',10,'propose_change','{"items":[{"id":"item-a","title":"Needs correction"}],"evidence":[{"id":"correction-source","text":"A request","language":"en","kind":"originalText"}]}','request-correction-0001') as correction \gset
select :'correction'::jsonb->'project'->'proposals'->3->>'id' as correction_id \gset
select public.recall_create_review_link(:'project_id',:'correction_id','client') as correction_link \gset
select public.recall_create_review_link(:'project_id',:'correction_id','client') as revoked_link \gset
select public.recall_create_review_link(:'project_id',:'correction_id','client') as expired_link \gset
select public.recall_revoke_review_link(:'revoked_link'::jsonb->>'id');
select pg_temp.expect_error(format('select public.recall_mutate_project(%L,11,''propose_change'',''{"items":[{"id":"item-a","title":"Bad upload"}],"evidence":[{"id":"source-file","text":"Audio","language":"en","kind":"personalRecollection","attachmentPath":"/private/recording.m4a"}]}'',''request-path-upload'')',:'project_id'),'22023','device recording path cannot be uploaded');
reset role;
update recall_private.review_links set expires_at=now()-interval '1 second' where id=:'expired_link'::jsonb->>'id';
set local role anon;
select pg_temp.expect_error(format('select public.recall_review_link(%L)',:'revoked_link'::jsonb->>'token'),'P0002','revoked review link cannot be read');
select pg_temp.expect_error(format('select public.recall_respond_review(%L,''confirm'','''',''response-expired-0001'')',:'expired_link'::jsonb->>'token'),'P0002','expired review link cannot respond');
select public.recall_respond_review(:'correction_link'::jsonb->>'token','correction','Please fix the deadline','response-correction-0001');
select pg_temp.assert(public.recall_review_link(:'correction_link'::jsonb->>'token')->>'status'='correctionRequested','correction closes the immutable proposal');
reset role;
select pg_temp.assert((select accepted_by='{}'::text[] from recall_private.revisions where id=:'correction_id'),'correction clears prior reviewers');
select pg_temp.assert(not exists(select 1 from recall_private.confirmations where revision_id=:'correction_id'),'correction clears prior item confirmations');
set local role authenticated;
select public.recall_mutate_project(:'project_id',12,'delete','{}','request-delete-0001') as deleted \gset
select pg_temp.assert((:'deleted'::jsonb->>'deleted')::boolean,'project deletion returns tombstone');
select pg_temp.assert(public.recall_mutate_project(:'project_id',12,'delete','{}','request-delete-0001')=:'deleted'::jsonb,'project deletion retry is idempotent');
select pg_temp.assert(public.recall_list_projects()='[]'::jsonb,'deleted project leaves owner workspace');
reset role;
select pg_temp.assert(not exists(select 1 from recall_private.revisions),'project deletion cascades immutable revision snapshots');
select pg_temp.assert(not exists(select 1 from recall_private.review_links),'project deletion cascades bearer links');
select pg_temp.assert(not exists(select 1 from recall_private.requests where response->'project' is distinct from 'null'::jsonb),'project deletion scrubs cached project contents');
set local role authenticated;
select public.recall_create_project('Delete account','Client','Creative','request-account-0001');
reset role;
delete from auth.users where id='11111111-1111-1111-1111-111111111111';
select pg_temp.assert(not exists(select 1 from recall_private.projects),'auth account deletion cascades private workspace');
select pg_temp.assert(not exists(select 1 from recall_private.requests),'auth account deletion cascades idempotency records');
rollback;
