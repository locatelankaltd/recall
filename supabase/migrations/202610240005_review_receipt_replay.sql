-- Do not report a failed response when an identical request already committed.
create or replace function public.recall_respond_review(p_token text,p_action text,p_note text,p_request_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare l recall_private.review_links%rowtype; p recall_private.projects%rowtype; r recall_private.revisions%rowtype; e recall_private.response_events%rowtype; v_payload_hash text; v_receipt jsonb; v_id text:=recall_private.new_id('receipt'); v_changed text[]; v_accepted text[]; v_status text; v_note text:=btrim(coalesce(p_note,''));
begin
 perform recall_private.check_request(p_request_id);
 if p_action is null or p_action not in ('confirm','correction','decline') or length(v_note)>2000 or (p_action='correction' and length(v_note)=0) then raise exception using errcode='22023',message='Choose confirm, correction or decline and describe any correction within 2,000 characters.'; end if;
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception using errcode='P0002',message='Review link unavailable.'; end if;
 select * into l from recall_private.review_links where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found then raise exception using errcode='P0002',message='Review link unavailable.'; end if;
 -- A single project row serializes responses, publication, correction and owner CAS changes.
 select * into p from recall_private.projects where id=l.project_id for update;
 select * into l from recall_private.review_links where id=l.id;
 if not found then raise exception using errcode='P0002',message='Review link unavailable.'; end if;
 v_payload_hash:=encode(extensions.digest(jsonb_build_array(l.revision_id,p_action,v_note)::text,'sha256'),'hex');
 select * into e from recall_private.response_events where link_id=l.id;
 if found then
  if e.request_id<>p_request_id or e.payload_hash<>v_payload_hash then raise exception using errcode='40001',message='A response is already recorded for this link. Request a new proposal to change it.'; end if;
  return e.receipt;
 end if;
 -- Identical committed retries may retrieve only their minimal receipt after
 -- link expiry/revocation. Uncommitted closed links remain unusable.
 if l.revoked_at is not null or l.expires_at<=now() then raise exception using errcode='P0002',message='Review link unavailable or expired. Ask the sender for a new link.'; end if;
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

revoke all on function public.recall_respond_review(text,text,text,text) from public,anon,authenticated;
grant execute on function public.recall_respond_review(text,text,text,text) to anon,authenticated;
