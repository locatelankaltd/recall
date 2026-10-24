-- Recall cloud v1. Public API is RPC-only; private snapshots are never client-writable.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema recall_private;
revoke all on schema recall_private from public, anon, authenticated;

create table recall_private.projects (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  client_name text not null,
  category text not null,
  version bigint not null default 1 check (version > 0),
  current_revision_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index projects_owner on recall_private.projects(owner_id, updated_at desc);
create table recall_private.revisions (
  id text primary key,
  project_id text not null references recall_private.projects(id) on delete cascade,
  number int not null check (number > 0),
  base_revision_id text,
  author_id text not null check (author_id = 'you'),
  items jsonb not null check (jsonb_typeof(items) = 'array'),
  required_participant_ids text[] not null,
  evidence jsonb not null default '[]' check (jsonb_typeof(evidence) = 'array'),
  is_proposal boolean not null,
  status text not null check (status in ('proposed','confirmed','correctionRequested','rejected')),
  accepted_by text[] not null,
  correction_note text,
  created_at timestamptz not null default now(),
  unique(project_id, number),
  check (required_participant_ids <@ array['you','client']::text[]),
  check (accepted_by <@ required_participant_ids),
  check (status <> 'confirmed' or required_participant_ids <@ accepted_by)
);
create index revisions_project on recall_private.revisions(project_id, number);
create table recall_private.item_statuses (
  project_id text not null references recall_private.projects(id) on delete cascade,
  item_id text not null,
  status text not null check (status in ('open','inProgress','delivered','accepted')),
  primary key(project_id,item_id)
);
create table recall_private.events (
  id text primary key,
  project_id text not null references recall_private.projects(id) on delete cascade,
  actor_id text not null,
  revision_id text,
  message text not null,
  created_at timestamptz not null default now()
);
create index events_project on recall_private.events(project_id, created_at, id);
create table recall_private.review_links (
  id text primary key,
  project_id text not null references recall_private.projects(id) on delete cascade,
  revision_id text not null references recall_private.revisions(id) on delete cascade,
  participant_id text not null check (participant_id = 'client'),
  item_ids text[] not null,
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index links_project on recall_private.review_links(project_id, created_at);
create table recall_private.response_events (
  id text primary key,
  link_id text not null unique references recall_private.review_links(id) on delete cascade,
  revision_id text not null references recall_private.revisions(id) on delete cascade,
  participant_id text not null,
  action text not null check (action in ('confirm','correction','decline')),
  note text not null,
  request_id text not null,
  payload_hash text not null,
  receipt jsonb not null,
  created_at timestamptz not null default now()
);
create index responses_revision on recall_private.response_events(revision_id);
create table recall_private.confirmations (
  revision_id text not null references recall_private.revisions(id) on delete cascade,
  participant_id text not null,
  item_id text not null,
  primary key(revision_id,participant_id,item_id)
);
create table recall_private.requests (
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,
  fingerprint text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(owner_id,request_id)
);

-- Defense in depth. No table or schema grants are made to API roles.
alter table recall_private.projects enable row level security;
alter table recall_private.revisions enable row level security;
alter table recall_private.item_statuses enable row level security;
alter table recall_private.events enable row level security;
alter table recall_private.review_links enable row level security;
alter table recall_private.response_events enable row level security;
alter table recall_private.confirmations enable row level security;
alter table recall_private.requests enable row level security;
create policy owner_read on recall_private.projects for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_read on recall_private.revisions for select to authenticated using (exists(select 1 from recall_private.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.item_statuses for select to authenticated using (exists(select 1 from recall_private.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.events for select to authenticated using (exists(select 1 from recall_private.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.review_links for select to authenticated using (exists(select 1 from recall_private.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.response_events for select to authenticated using (exists(select 1 from recall_private.revisions r join recall_private.projects p on p.id=r.project_id where r.id=revision_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.confirmations for select to authenticated using (exists(select 1 from recall_private.revisions r join recall_private.projects p on p.id=r.project_id where r.id=revision_id and p.owner_id = (select auth.uid())));
create policy owner_read on recall_private.requests for select to authenticated using (owner_id=(select auth.uid()));

create function recall_private.immutable_revision() returns trigger language plpgsql set search_path = '' as $$
begin
 if row(new.id,new.project_id,new.number,new.base_revision_id,new.author_id,new.items,new.required_participant_ids,new.evidence,new.is_proposal,new.created_at)
    is distinct from row(old.id,old.project_id,old.number,old.base_revision_id,old.author_id,old.items,old.required_participant_ids,old.evidence,old.is_proposal,old.created_at) then
   raise exception using errcode='22023', message='Revision content is immutable. Create a new proposal.';
 end if;
 return new;
end $$;
create trigger immutable_revision before update on recall_private.revisions for each row execute function recall_private.immutable_revision();

create function recall_private.new_id(p_prefix text) returns text language sql volatile set search_path='' as $$ select p_prefix || '-' || pg_catalog.gen_random_uuid()::text $$;
create function recall_private.require_owner() returns uuid language plpgsql stable set search_path='' as $$
declare v uuid := auth.uid(); begin
 if v is null then raise exception using errcode='28000',message='Sign in to access your workspace.'; end if;
 return v;
end $$;
create function recall_private.check_request(p_request_id text) returns void language plpgsql immutable set search_path='' as $$ begin
 if p_request_id is null or p_request_id !~ '^[A-Za-z0-9_-]{8,128}$' then raise exception using errcode='22023',message='Provide a unique request ID (8 to 128 letters, numbers, dashes or underscores).'; end if;
end $$;
create function recall_private.add_event(p_project text,p_actor text,p_revision text,p_message text) returns void language sql volatile set search_path='' as $$
 insert into recall_private.events(id,project_id,actor_id,revision_id,message) values(recall_private.new_id('event'),p_project,p_actor,p_revision,p_message)
$$;
create function recall_private.revision_json(p_id text) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',id,'number',number,'baseRevisionId',base_revision_id,'createdAt',created_at,'authorId',author_id,'items',items,'requiredParticipantIds',to_jsonb(required_participant_ids),'acceptedBy',to_jsonb(accepted_by),'evidence',evidence,'status',status,'correctionNote',correction_note) from recall_private.revisions where id=p_id
$$;
create function recall_private.project_json(p_id text) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',p.id,'title',p.title,'clientName',p.client_name,'category',p.category,
 'participants',jsonb_build_array(jsonb_build_object('id','you','name','You','role','Creator'),jsonb_build_object('id','client','name',p.client_name,'role','Client')),
 'currentRevision',recall_private.revision_json(p.current_revision_id),
 'proposals',coalesce((select jsonb_agg(recall_private.revision_json(r.id) order by r.number) from recall_private.revisions r where r.project_id=p.id and r.is_proposal),'[]'::jsonb),
 'archivedRevisions',coalesce((select jsonb_agg(recall_private.revision_json(r.id) order by r.number) from recall_private.revisions r where r.project_id=p.id and r.status='confirmed' and r.id<>p.current_revision_id),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'message',e.message,'createdAt',e.created_at,'actorId',e.actor_id,'revisionId',e.revision_id) order by e.created_at,e.id) from recall_private.events e where e.project_id=p.id),'[]'::jsonb),
 'itemStatuses',coalesce((select jsonb_object_agg(s.item_id,s.status) from recall_private.item_statuses s where s.project_id=p.id),'{}'::jsonb),'isDemo',false)
 from recall_private.projects p where p.id=p_id
$$;
create function recall_private.envelope(p_id text) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('project',recall_private.project_json(id),'version',version) from recall_private.projects where id=p_id
$$;
create function recall_private.validate_items(p_items jsonb,p_allow_empty boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare i jsonb; result jsonb:='[]'; seen text[]:='{}'; v_due text; v_amount numeric;
begin
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>100 or (not p_allow_empty and jsonb_array_length(p_items)=0) then raise exception using errcode='22023',message='Provide one to one hundred plan items.'; end if;
 for i in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(i) is distinct from 'object' or coalesce(i->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$' or (i->>'id')=any(seen)
    or jsonb_typeof(i->'title') is distinct from 'string' or length(btrim(i->>'title')) not between 1 and 500
    or (i ? 'details' and jsonb_typeof(i->'details') is distinct from 'string') or length(coalesce(i->>'details',''))>10000
    or coalesce(i->>'ownerId','you') not in ('you','client') or coalesce(i->>'currency','USD') !~ '^[A-Z]{3}$' then
   raise exception using errcode='22023',message='Invalid item identity, title, owner, details or currency.';
  end if;
  v_amount:=null;
  if i->'amountMinor' is not null and i->'amountMinor'<>'null'::jsonb then
   if jsonb_typeof(i->'amountMinor')<>'number' then raise exception using errcode='22023',message='Amounts must be nonnegative integer minor units.'; end if;
   v_amount:=(i->>'amountMinor')::numeric;
   if v_amount<0 or v_amount<>trunc(v_amount) or v_amount>9007199254740991 then raise exception using errcode='22023',message='Amounts must be nonnegative integer minor units.'; end if;
  end if;
  v_due:=i->>'dueDate';
  if v_due is not null then
   if v_due !~ '^\d{4}-\d{2}-\d{2}(T00:00:00(\.0{1,6})?(Z|[+]00:00)?)?$' then raise exception using errcode='22023',message='Deadlines must be date-only values.'; end if;
   perform v_due::date;
   v_due:=substring(v_due from 1 for 10)||'T00:00:00.000';
  end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',i->>'id','title',btrim(i->>'title'),'details',coalesce(i->>'details',''),'ownerId',coalesce(i->>'ownerId','you'),'dueDate',v_due,'amountMinor',v_amount::bigint,'currency',coalesce(i->>'currency','USD')));
  seen:=array_append(seen,i->>'id');
 end loop;
 return result;
end $$;
create function recall_private.validate_evidence(p_evidence jsonb) returns jsonb language plpgsql set search_path='' as $$
declare e jsonb; result jsonb:='[]'; seen text[]:='{}';
begin
 if jsonb_typeof(p_evidence) is distinct from 'array' or jsonb_array_length(p_evidence) not between 1 and 20 then raise exception using errcode='22023',message='Add one to twenty original sources or personal recollections.'; end if;
 for e in select value from jsonb_array_elements(p_evidence) loop
  if jsonb_typeof(e) is distinct from 'object' or coalesce(e->>'id','') !~ '^[A-Za-z0-9_-]{1,128}$' or (e->>'id')=any(seen)
   or jsonb_typeof(e->'text') is distinct from 'string' or length(btrim(e->>'text')) not between 1 and 30000
   or jsonb_typeof(e->'language') is distinct from 'string' or length(btrim(e->>'language')) not between 1 and 80
   or coalesce(e->>'kind','') not in ('originalText','personalRecollection')
   or (e->>'attachmentPath') is not null then raise exception using errcode='22023',message='Invalid source. Local recording paths must remain on your device.'; end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',e->>'id','text',e->>'text','language',btrim(e->>'language'),'kind',e->>'kind','createdAt',now(),'attachmentPath',null));
  seen:=array_append(seen,e->>'id');
 end loop;
 return result;
end $$;
create function recall_private.changed_ids(p_revision text) returns text[] language sql stable set search_path='' as $$
 with r as(select items,base_revision_id from recall_private.revisions where id=p_revision),
 old as(select i->>'id' id,i from r join recall_private.revisions b on b.id=r.base_revision_id cross join lateral jsonb_array_elements(b.items) i),
 proposed as(select i->>'id' id,i from r cross join lateral jsonb_array_elements(r.items) i)
 select coalesce(array_agg(coalesce(o.id,n.id) order by coalesce(o.id,n.id)),'{}'::text[]) from old o full join proposed n on n.id=o.id where o.i is distinct from n.i
$$;
create function recall_private.publish(p_project text,p_revision text) returns void language plpgsql set search_path='' as $$
declare old_items jsonb; new_items jsonb;
begin
 select r.items into old_items from recall_private.projects p join recall_private.revisions r on r.id=p.current_revision_id where p.id=p_project;
 select items into new_items from recall_private.revisions where id=p_revision;
 delete from recall_private.item_statuses s where s.project_id=p_project and not exists(select 1 from jsonb_array_elements(new_items) n join jsonb_array_elements(old_items) o on o->>'id'=n->>'id' where n=o and n->>'id'=s.item_id);
 update recall_private.revisions set status='confirmed' where id=p_revision;
 update recall_private.projects set current_revision_id=p_revision where id=p_project;
end $$;

create function public.recall_list_projects() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); begin
 return coalesce((select jsonb_agg(recall_private.envelope(id) order by updated_at desc,id) from recall_private.projects where owner_id=v_owner),'[]'::jsonb);
end $$;
create function public.recall_create_project(p_title text,p_client_name text,p_category text,p_request_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); v_id text:=recall_private.new_id('project'); v_revision text:=recall_private.new_id('revision'); v_fingerprint text; v_cached recall_private.requests%rowtype; v_result jsonb;
begin
 perform recall_private.check_request(p_request_id);
 if p_title is null or length(btrim(p_title)) not between 1 and 200 or p_client_name is null or length(btrim(p_client_name)) not between 1 and 200 or p_category is null or length(btrim(p_category)) not between 1 and 80 then raise exception using errcode='22023',message='Add a project name, client name and category.'; end if;
 v_fingerprint:=encode(extensions.digest(jsonb_build_array('create',p_title,p_client_name,p_category)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(v_owner::text||p_request_id,0));
 select * into v_cached from recall_private.requests where owner_id=v_owner and request_id=p_request_id;
 if found then if v_cached.fingerprint<>v_fingerprint then raise exception using errcode='22023',message='Request ID already used for another action.'; end if; return v_cached.response; end if;
 insert into recall_private.projects(id,owner_id,title,client_name,category) values(v_id,v_owner,btrim(p_title),btrim(p_client_name),btrim(p_category));
 insert into recall_private.revisions(id,project_id,number,author_id,items,required_participant_ids,is_proposal,status,accepted_by) values(v_revision,v_id,1,'you','[]',array['you'],false,'confirmed',array['you']);
 update recall_private.projects set current_revision_id=v_revision where id=v_id;
 perform recall_private.add_event(v_id,'you',v_revision,'Created a private project plan. No client confirmation recorded.');
 v_result:=recall_private.envelope(v_id);
 insert into recall_private.requests(owner_id,request_id,fingerprint,response) values(v_owner,p_request_id,v_fingerprint,v_result);
 return v_result;
end $$;
create function public.recall_mutate_project(p_project_id text,p_expected_version bigint,p_action text,p_payload jsonb,p_request_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); p recall_private.projects%rowtype; r recall_private.revisions%rowtype; current_r recall_private.revisions%rowtype; v_fingerprint text; v_cached recall_private.requests%rowtype; result jsonb; v_items jsonb; v_evidence jsonb; v_id text; v_number int; v_actor text; v_note text; v_item jsonb; v_prior text; v_new_status text; v_changed text[];
begin
 perform recall_private.check_request(p_request_id);
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>800000 then raise exception using errcode='22023',message='Invalid action payload.'; end if;
 v_fingerprint:=encode(extensions.digest(jsonb_build_array('mutate',p_project_id,p_expected_version,p_action,p_payload)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(v_owner::text||p_request_id,0));
 select * into v_cached from recall_private.requests where owner_id=v_owner and request_id=p_request_id;
 if found then if v_cached.fingerprint<>v_fingerprint then raise exception using errcode='22023',message='Request ID already used for another action.'; end if; return v_cached.response; end if;
 select * into p from recall_private.projects where id=p_project_id and owner_id=v_owner for update;
 if not found then raise exception using errcode='P0002',message='Project not found.'; end if;
 if p_expected_version is null or p.version<>p_expected_version then raise exception using errcode='40001',message='The project changed. Refresh and review the latest version.'; end if;
 select * into current_r from recall_private.revisions where id=p.current_revision_id;
 v_actor:=coalesce(p_payload->>'actorId',p_payload->>'authorId','you');
 if v_actor<>'you' then raise exception using errcode='42501',message='An owner cannot record a client response. Share a review link.'; end if;
 if p_action='add_item' then
  if current_r.required_participant_ids<>array['you'] then raise exception using errcode='22023',message='This plan is shared. Propose a change to add work.'; end if;
  v_items:=recall_private.validate_items(jsonb_build_array(p_payload->'item'));
  if exists(select 1 from jsonb_array_elements(current_r.items) i where i->>'id'=v_items->0->>'id') then raise exception using errcode='22023',message='That item already exists.'; end if;
  if jsonb_array_length(current_r.items)>=100 then raise exception using errcode='22023',message='A plan supports up to one hundred items.'; end if;
  select coalesce(max(number),0)+1 into v_number from recall_private.revisions where project_id=p.id;
  v_id:=recall_private.new_id('revision');
  insert into recall_private.revisions(id,project_id,number,base_revision_id,author_id,items,required_participant_ids,is_proposal,status,accepted_by) values(v_id,p.id,v_number,current_r.id,'you',current_r.items||v_items,array['you'],false,'confirmed',array['you']);
  update recall_private.projects set current_revision_id=v_id where id=p.id;
  perform recall_private.add_event(p.id,'you',v_id,'Added an item to your private plan. No client confirmation recorded.');
 elsif p_action='propose_change' then
  v_items:=recall_private.validate_items(p_payload->'items');
  v_evidence:=recall_private.validate_evidence(p_payload->'evidence');
  if v_items=current_r.items then raise exception using errcode='22023',message='The proposal must change at least one plan item.'; end if;
  if p_payload ? 'requiredParticipantIds' and p_payload->'requiredParticipantIds'<>'["you","client"]'::jsonb then raise exception using errcode='22023',message='Both project participants must review shared changes.'; end if;
  select coalesce(max(number),0)+1 into v_number from recall_private.revisions where project_id=p.id;
  v_id:=recall_private.new_id('revision');
  insert into recall_private.revisions(id,project_id,number,base_revision_id,author_id,items,required_participant_ids,evidence,is_proposal,status,accepted_by) values(v_id,p.id,v_number,current_r.id,'you',v_items,array['you','client'],v_evidence,true,'proposed',array['you']);
  v_changed:=recall_private.changed_ids(v_id);
  insert into recall_private.confirmations(revision_id,participant_id,item_id) select v_id,'you',unnest(v_changed);
  perform recall_private.add_event(p.id,'you',v_id,'Proposed version '||v_number||'. The current plan stays unchanged.');
 elsif p_action in ('confirm','correction') then
  select * into r from recall_private.revisions where id=p_payload->>'revisionId' and project_id=p.id and is_proposal;
  if not found then raise exception using errcode='P0002',message='Proposal not found.'; end if;
  if r.status<>'proposed' or r.base_revision_id<>p.current_revision_id then raise exception using errcode='40001',message='This proposal is closed or stale. Create a new proposal.'; end if;
  if p_action='correction' then
   v_note:=btrim(p_payload->>'note');
   if v_note is null or length(v_note) not between 1 and 2000 then raise exception using errcode='22023',message='Describe the correction within 2,000 characters.'; end if;
   update recall_private.revisions set status='correctionRequested',accepted_by='{}',correction_note=v_note where id=r.id;
   delete from recall_private.confirmations where revision_id=r.id;
   perform recall_private.add_event(p.id,'you',r.id,'Correction requested: '||v_note);
  else
   -- Authors have already reviewed their immutable proposal. Never forge client acceptance.
   if not ('you'=any(r.accepted_by)) then
    update recall_private.revisions set accepted_by=array_append(accepted_by,'you') where id=r.id;
    insert into recall_private.confirmations select r.id,'you',unnest(recall_private.changed_ids(r.id)) on conflict do nothing;
   end if;
  end if;
 elsif p_action='set_status' then
  select i into v_item from jsonb_array_elements(current_r.items) i where i->>'id'=p_payload->>'itemId';
  if v_item is null then raise exception using errcode='22023',message='That item is not in the current plan.'; end if;
  v_new_status:=p_payload->>'status';
  select status into v_prior from recall_private.item_statuses where project_id=p.id and item_id=v_item->>'id';
  v_prior:=coalesce(v_prior,'open');
  if v_new_status is null or v_new_status not in ('open','inProgress','delivered','accepted') then raise exception using errcode='22023',message='Invalid progress status.'; end if;
  if v_new_status='accepted' and (v_prior<>'delivered' or v_item->>'ownerId'='you') then raise exception using errcode='42501',message='Only the recipient can accept an item after delivery.'; end if;
  if v_new_status<>'accepted' and v_item->>'ownerId'<>'you' then raise exception using errcode='42501',message='Only the item owner can record progress.'; end if;
  insert into recall_private.item_statuses(project_id,item_id,status) values(p.id,v_item->>'id',v_new_status) on conflict(project_id,item_id) do update set status=excluded.status;
  perform recall_private.add_event(p.id,'you',null,'Item progress: '||v_new_status||'. This does not record payment.');
 elsif p_action='delete' then
  -- Keep replay tombstones, while removing cached project content on deletion.
  update recall_private.requests set response=jsonb_build_object('project',null,'version',p.version+1,'deleted',true,'projectId',p.id) where owner_id=v_owner and response->'project'->>'id'=p.id;
  delete from recall_private.projects where id=p.id;
  result:=jsonb_build_object('project',null,'version',p.version+1,'deleted',true,'projectId',p.id);
 else raise exception using errcode='22023',message='Unsupported project action.';
 end if;
 if p_action<>'delete' then
  update recall_private.projects set version=version+1,updated_at=now() where id=p.id;
  result:=recall_private.envelope(p.id);
 end if;
 insert into recall_private.requests(owner_id,request_id,fingerprint,response) values(v_owner,p_request_id,v_fingerprint,result);
 return result;
end $$;

create function public.recall_create_review_link(p_project_id text,p_revision_id text,p_participant_id text,p_item_ids text[] default null,p_ttl_seconds int default 86400) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); p recall_private.projects%rowtype; r recall_private.revisions%rowtype; v_changed text[]; v_selected text[]; v_id text:=recall_private.new_id('link'); v_token text:=encode(extensions.gen_random_bytes(32),'hex'); v_expires timestamptz;
begin
 select * into p from recall_private.projects where id=p_project_id and owner_id=v_owner for update;
 if not found then raise exception using errcode='P0002',message='Project not found.'; end if;
 select * into r from recall_private.revisions where id=p_revision_id and project_id=p.id and is_proposal;
 if not found then raise exception using errcode='P0002',message='Proposal not found.'; end if;
 if r.status<>'proposed' or r.base_revision_id<>p.current_revision_id then raise exception using errcode='40001',message='This proposal is closed or stale. Create a new proposal.'; end if;
 if p_participant_id is distinct from 'client' or not (p_participant_id=any(r.required_participant_ids)) then raise exception using errcode='22023',message='Choose the client participant for this review link.'; end if;
 if p_ttl_seconds is null or p_ttl_seconds not between 60 and 604800 then raise exception using errcode='22023',message='Review links expire between one minute and seven days.'; end if;
 v_changed:=recall_private.changed_ids(r.id);
 v_selected:=coalesce(p_item_ids,v_changed);
 if cardinality(v_selected)=0 or not (v_selected<@v_changed) or array_position(v_selected,null) is not null or cardinality(v_selected)<>(select count(distinct x) from unnest(v_selected) x) then raise exception using errcode='22023',message='Select unique changed item IDs for this review link.'; end if;
 v_expires:=now()+make_interval(secs=>p_ttl_seconds);
 insert into recall_private.review_links(id,project_id,revision_id,participant_id,item_ids,token_hash,expires_at) values(v_id,p.id,r.id,p_participant_id,v_selected,encode(extensions.digest(v_token,'sha256'),'hex'),v_expires);
 return jsonb_build_object('id',v_id,'token',v_token,'expires',v_expires,'revisionId',r.id,'participantId',p_participant_id,'itemIds',to_jsonb(v_selected),'identity','link-holder response; identity not verified');
end $$;
create function public.recall_list_review_links(p_project_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); begin
 if not exists(select 1 from recall_private.projects where id=p_project_id and owner_id=v_owner) then raise exception using errcode='P0002',message='Project not found.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'revisionId',l.revision_id,'participantId',l.participant_id,'itemIds',to_jsonb(l.item_ids),'expires',l.expires_at,'revoked',l.revoked_at is not null,'responded',exists(select 1 from recall_private.response_events e where e.link_id=l.id)) order by l.created_at,l.id) from recall_private.review_links l where l.project_id=p_project_id),'[]'::jsonb);
end $$;
create function public.recall_revoke_review_link(p_link_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=recall_private.require_owner(); v_project text;
begin
 select p.id into v_project from recall_private.review_links l join recall_private.projects p on p.id=l.project_id where l.id=p_link_id and p.owner_id=v_owner;
 if v_project is null then raise exception using errcode='P0002',message='Review link not found.'; end if;
 perform 1 from recall_private.projects where id=v_project for update;
 update recall_private.review_links set revoked_at=coalesce(revoked_at,now()) where id=p_link_id;
 return jsonb_build_object('id',p_link_id,'revoked',true);
end $$;
create function recall_private.get_link(p_token text) returns recall_private.review_links language plpgsql stable set search_path='' as $$
declare l recall_private.review_links%rowtype; begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception using errcode='P0002',message='Review link unavailable.'; end if;
 select * into l from recall_private.review_links where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found or l.revoked_at is not null or l.expires_at<=now() then raise exception using errcode='P0002',message='Review link unavailable or expired. Ask the sender for a new link.'; end if;
 return l;
end $$;
create function public.recall_review_link(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare l recall_private.review_links%rowtype:=recall_private.get_link(p_token); p recall_private.projects%rowtype; r recall_private.revisions%rowtype; v_base_items jsonb; v_response jsonb; v_changes jsonb; v_status text; v_full_scope boolean;
begin
 select * into p from recall_private.projects where id=l.project_id;
 select * into r from recall_private.revisions where id=l.revision_id;
 select items into v_base_items from recall_private.revisions where id=r.base_revision_id;
 select jsonb_build_object('receiptId',id,'action',action,'note',note,'identity','link-holder response; identity not verified') into v_response from recall_private.response_events where link_id=l.id;
 select jsonb_agg(jsonb_build_object('itemId',item_id,'previous',(select i from jsonb_array_elements(v_base_items) i where i->>'id'=item_id),'proposed',(select i from jsonb_array_elements(r.items) i where i->>'id'=item_id)) order by ord) into v_changes from unnest(l.item_ids) with ordinality as x(item_id,ord);
 v_status:=case when r.status='proposed' and r.base_revision_id<>p.current_revision_id then 'stale' else r.status end;
 v_full_scope:=recall_private.changed_ids(r.id)<@l.item_ids;
 return jsonb_build_object('projectTitle',p.title,'participantName',p.client_name,'revisionId',r.id,'version',r.number,'baseRevisionId',r.base_revision_id,'currentRevisionId',p.current_revision_id,'status',v_status,'changes',v_changes,'evidence',case when v_full_scope then r.evidence else '[]'::jsonb end,'evidenceOmitted',not v_full_scope,'canRespond',v_status='proposed' and v_response is null,'response',v_response,'identity','link-holder response; identity not verified');
end $$;
create function public.recall_respond_review(p_token text,p_action text,p_note text,p_request_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare l recall_private.review_links%rowtype; p recall_private.projects%rowtype; r recall_private.revisions%rowtype; e recall_private.response_events%rowtype; v_payload_hash text; v_receipt jsonb; v_id text:=recall_private.new_id('receipt'); v_changed text[]; v_accepted text[]; v_status text; v_note text:=btrim(coalesce(p_note,''));
begin
 perform recall_private.check_request(p_request_id);
 if p_action is null or p_action not in ('confirm','correction','decline') or length(v_note)>2000 or (p_action='correction' and length(v_note)=0) then raise exception using errcode='22023',message='Choose confirm, correction or decline and describe any correction within 2,000 characters.'; end if;
 l:=recall_private.get_link(p_token);
 -- A single project row serializes responses, publication, correction and owner CAS changes.
 select * into p from recall_private.projects where id=l.project_id for update;
 l:=recall_private.get_link(p_token);
 v_payload_hash:=encode(extensions.digest(jsonb_build_array(l.revision_id,p_action,v_note)::text,'sha256'),'hex');
 select * into e from recall_private.response_events where link_id=l.id;
 if found then
  if e.request_id<>p_request_id or e.payload_hash<>v_payload_hash then raise exception using errcode='40001',message='A response is already recorded for this link. Request a new proposal to change it.'; end if;
  return e.receipt;
 end if;
 select * into r from recall_private.revisions where id=l.revision_id;
 if r.status<>'proposed' or r.base_revision_id<>p.current_revision_id then raise exception using errcode='40001',message='This proposal is closed or stale. Request a new proposal.'; end if;
 v_changed:=recall_private.changed_ids(r.id);
 v_status:=r.status;
 if p_action in ('correction','decline') then
  v_status:=case when p_action='correction' then 'correctionRequested' else 'rejected' end;
  update recall_private.revisions set status=v_status,accepted_by='{}',correction_note=nullif(v_note,'') where id=r.id;
  delete from recall_private.confirmations where revision_id=r.id;
 else
  insert into recall_private.confirmations(revision_id,participant_id,item_id) select r.id,l.participant_id,unnest(l.item_ids) on conflict do nothing;
  select coalesce(array_agg(a order by case when a='you' then 0 else 1 end),'{}'::text[]) into v_accepted from unnest(r.required_participant_ids) a where not exists(select 1 from unnest(v_changed) c where not exists(select 1 from recall_private.confirmations f where f.revision_id=r.id and f.participant_id=a and f.item_id=c));
  update recall_private.revisions set accepted_by=v_accepted where id=r.id;
  if r.required_participant_ids<@v_accepted then
   perform recall_private.publish(p.id,r.id);
   v_status:='confirmed';
  end if;
 end if;
 update recall_private.projects set version=version+1,updated_at=now() where id=p.id;
 perform recall_private.add_event(p.id,l.participant_id,r.id,case when v_status='confirmed' then 'All required participants confirmed version '||r.number||'. Client response was by a review link holder; identity not verified.' when p_action='confirm' then 'A review link holder confirmed selected changes in version '||r.number||'. Identity not verified.' else 'A review link holder requested '||p_action||' for version '||r.number||'. Identity not verified.' end);
 v_receipt:=jsonb_build_object('receiptId',v_id,'revisionId',r.id,'version',r.number,'action',p_action,'status',v_status,'identity','link-holder response; identity not verified');
 insert into recall_private.response_events(id,link_id,revision_id,participant_id,action,note,request_id,payload_hash,receipt) values(v_id,l.id,r.id,l.participant_id,p_action,v_note,p_request_id,v_payload_hash,v_receipt);
 return v_receipt;
end $$;

-- Explicit grants: default PUBLIC function execution is revoked for every API/helper.
revoke all on all tables in schema recall_private from public,anon,authenticated;
revoke all on all functions in schema recall_private from public,anon,authenticated;
revoke all on function public.recall_list_projects() from public,anon,authenticated;
revoke all on function public.recall_create_project(text,text,text,text) from public,anon,authenticated;
revoke all on function public.recall_mutate_project(text,bigint,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.recall_create_review_link(text,text,text,text[],int) from public,anon,authenticated;
revoke all on function public.recall_list_review_links(text) from public,anon,authenticated;
revoke all on function public.recall_revoke_review_link(text) from public,anon,authenticated;
revoke all on function public.recall_review_link(text) from public,anon,authenticated;
revoke all on function public.recall_respond_review(text,text,text,text) from public,anon,authenticated;
grant execute on function public.recall_list_projects() to authenticated;
grant execute on function public.recall_create_project(text,text,text,text) to authenticated;
grant execute on function public.recall_mutate_project(text,bigint,text,jsonb,text) to authenticated;
grant execute on function public.recall_create_review_link(text,text,text,text[],int) to authenticated;
grant execute on function public.recall_list_review_links(text) to authenticated;
grant execute on function public.recall_revoke_review_link(text) to authenticated;
grant execute on function public.recall_review_link(text) to anon,authenticated;
grant execute on function public.recall_respond_review(text,text,text,text) to anon,authenticated;
alter default privileges in schema recall_private revoke execute on functions from public;
alter default privileges in schema recall_private revoke all on tables from public,anon,authenticated;
