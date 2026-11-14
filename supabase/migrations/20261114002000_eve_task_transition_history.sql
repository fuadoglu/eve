-- EVE-017.1: append-only task transition records and idempotent state writes.
-- Browser/HTTP routing is separate; scoped actions present only the stored token hash.

create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to app_executor;
grant select on app_private.tasks, app_private.property_memberships,
  app_private.owner_accounts, app_private.subscriptions,
  app_private.access_links, app_private.media_assets,
  app_private.inspection_submissions, app_private.inspection_snapshot_rooms,
  app_private.inspection_room_answers to app_executor;
grant update on app_private.tasks, app_private.access_links to app_executor;

create table app_private.task_transition_events (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  task_id uuid not null,
  action varchar(20) not null,
  from_state app_private.task_state not null,
  to_state app_private.task_state not null,
  actor_user_id uuid,
  access_link_id uuid,
  claimed_name varchar(100),
  note varchar(2000),
  idempotency_scope varchar(80) not null,
  idempotency_key varchar(128) not null,
  request_hash varchar(64) not null,
  expected_version integer not null,
  resulting_version integer not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (id, property_id, owner_account_id),
  unique (idempotency_scope, idempotency_key),
  check (action in ('accept','report_done','confirm','request_rework','cancel')),
  check ((actor_user_id is null) <> (access_link_id is null)),
  check (claimed_name is null or length(trim(claimed_name)) between 1 and 100),
  check (note is null or length(note)<=2000),
  check (idempotency_scope ~ '^(user|link):[0-9a-f-]{36}:(accept|report_done|confirm|request_rework|cancel)$'),
  check (idempotency_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  check (request_hash ~ '^[0-9a-f]{64}$'),
  check (expected_version>=1 and resulting_version=expected_version+1),
  check (
    (action='accept' and from_state='open' and to_state='accepted'
      and ((claimed_name is not null and access_link_id is not null and actor_user_id is null)
        or (claimed_name is null and access_link_id is null and actor_user_id is not null)))
    or (action='report_done' and from_state in ('open','accepted') and to_state='reported_done'
      and ((claimed_name is not null and access_link_id is not null and actor_user_id is null)
        or (claimed_name is null and access_link_id is null and actor_user_id is not null)))
    or (action='confirm' and from_state='reported_done' and to_state='completed' and actor_user_id is not null)
    or (action='request_rework' and from_state='reported_done' and to_state='accepted' and note is not null and actor_user_id is not null)
    or (action='cancel' and from_state in ('open','accepted','reported_done') and to_state='cancelled' and actor_user_id is not null)
  ),
  foreign key (task_id, property_id, owner_account_id)
    references app_private.tasks(id, property_id, owner_account_id) on delete restrict,
  foreign key (actor_user_id) references auth.users(id) on delete restrict,
  foreign key (access_link_id, property_id, owner_account_id)
    references app_private.access_links(id, property_id, owner_account_id) on delete restrict
);
alter table app_private.task_transition_events enable row level security;
alter table app_private.task_transition_events force row level security;

create table app_private.task_transition_media (
  id uuid not null default gen_random_uuid(),
  owner_account_id uuid not null,
  property_id uuid not null,
  transition_event_id uuid not null,
  media_asset_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (id),
  unique (transition_event_id, media_asset_id),
  foreign key (transition_event_id, property_id, owner_account_id)
    references app_private.task_transition_events(id, property_id, owner_account_id) on delete restrict,
  foreign key (media_asset_id, property_id, owner_account_id)
    references app_private.media_assets(id, property_id, owner_account_id) on delete restrict
);
alter table app_private.task_transition_media enable row level security;
alter table app_private.task_transition_media force row level security;
grant insert, select on app_private.task_transition_events,
  app_private.task_transition_media to app_executor;

create function app_private.can_manage_task(p_property_id uuid, p_owner_account_id uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select (select app_private.current_actor_id()) is not null
    and p_property_id is not null and p_owner_account_id is not null
    and exists (select 1 from app_private.subscriptions s
      where s.property_id=p_property_id and s.owner_account_id=p_owner_account_id
        and s.state in ('trialing','active') and s.current_end>statement_timestamp())
    and (app_private.is_owner(p_owner_account_id) or exists (
      select 1 from app_private.property_memberships m
      where m.property_id=p_property_id and m.owner_account_id=p_owner_account_id
        and m.user_id=(select app_private.current_actor_id())
        and m.revoked_at is null and m.permission in ('daily','full')
    ));
$$;
revoke all on function app_private.can_manage_task(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.can_manage_task(uuid,uuid) to app_executor;

-- app_executor is NOLOGIN/NOBYPASSRLS and receives no direct API table grants.
-- These policies permit only the narrow security-definer command below to operate.
create policy tasks_transition_internal_read on app_private.tasks
  for select to app_executor using (true);
create policy tasks_transition_internal_update on app_private.tasks
  for update to app_executor using (true) with check (true);
create policy access_links_task_transition_internal_read on app_private.access_links
  for select to app_executor using (true);
create policy access_links_task_transition_internal_update on app_private.access_links
  for update to app_executor using (true) with check (true);
create policy subscriptions_task_transition_internal_read on app_private.subscriptions
  for select to app_executor using (true);
create policy inspection_submissions_task_transition_internal_read on app_private.inspection_submissions
  for select to app_executor using (true);
create policy inspection_snapshot_rooms_task_transition_internal_read on app_private.inspection_snapshot_rooms
  for select to app_executor using (true);
create policy inspection_room_answers_task_transition_internal_read on app_private.inspection_room_answers
  for select to app_executor using (true);
create policy task_transition_events_internal_read on app_private.task_transition_events
  for select to app_executor using (true);
create policy task_transition_events_internal_insert on app_private.task_transition_events
  for insert to app_executor with check (true);
create policy task_transition_media_internal_read on app_private.task_transition_media
  for select to app_executor using (true);
create policy task_transition_media_internal_insert on app_private.task_transition_media
  for insert to app_executor with check (true);
create policy media_assets_task_transition_internal_read on app_private.media_assets
  for select to app_executor using (classification='private_task');
create policy outbox_task_transition_create on app_private.outbox
  for insert to app_executor with check (
    event_kind='task.reported_done' and property_id is not null and owner_account_id is not null
    and exists (select 1 from app_private.task_transition_events e
      where e.id=(payload->>'transition_event_id')::uuid and e.action='report_done'
        and e.property_id=outbox.property_id and e.owner_account_id=outbox.owner_account_id)
  );

create function app_private.reject_task_history_mutation()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  raise exception using errcode='23000',message='task_transition_history_is_immutable';
end;
$$;
create trigger task_transition_events_immutable
  before update or delete on app_private.task_transition_events
  for each row execute function app_private.reject_task_history_mutation();
create trigger task_transition_media_immutable
  before update or delete on app_private.task_transition_media
  for each row execute function app_private.reject_task_history_mutation();

grant create on schema api to app_executor;
create function api.transition_task(
  p_task_id uuid,
  p_expected_version integer,
  p_action text,
  p_idempotency_key text,
  p_note text default null,
  p_claimed_name text default null,
  p_media_ids uuid[] default array[]::uuid[],
  p_link_token_hash text default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_task app_private.tasks%rowtype;
  v_link app_private.access_links%rowtype;
  v_scope text;
  v_hash text;
  v_existing app_private.task_transition_events%rowtype;
  v_from app_private.task_state;
  v_to app_private.task_state;
  v_event_id uuid := gen_random_uuid();
  v_now timestamptz := statement_timestamp();
  v_media uuid;
  v_capability text;
  v_ack jsonb;
begin
  if p_task_id is null or p_expected_version is null or p_expected_version<1
     or p_action is null or p_action not in ('accept','report_done','confirm','request_rework','cancel')
     or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$'
     or (p_note is not null and length(p_note)>2000)
     or (p_claimed_name is not null and (length(trim(p_claimed_name))<1 or length(p_claimed_name)>100))
     or p_media_ids is null or cardinality(p_media_ids)>20
     or cardinality(p_media_ids)<>(select count(distinct x) from unnest(p_media_ids) x) then
    raise exception using errcode='22023',message='invalid_task_transition_input';
  end if;
  if p_link_token_hash is not null then
    if p_action not in ('accept','report_done') or p_link_token_hash !~ '^[0-9a-f]{64}$' or v_actor is not null then
      raise exception using errcode='42501',message='scoped_task_link_required';
    end if;
    select * into v_link from app_private.access_links l
    where l.token_hash=p_link_token_hash and l.kind='task'
      and l.revoked_at is null and l.expires_at>v_now
      and l.expires_at<=l.created_at+interval '30 days'
    for share;
    if not found then raise exception using errcode='42501',message='scoped_task_link_invalid'; end if;
    if not (v_link.scopes ? (case p_action when 'accept' then 'task.accept' else 'task.report_done' end)) then
      raise exception using errcode='42501',message='scoped_task_action_denied';
    end if;
    v_scope := 'link:'||v_link.id::text||':'||p_action;
  else
    if v_actor is null then
      raise exception using errcode='42501',message='authenticated_task_manager_required';
    end if;
    v_scope := 'user:'||v_actor::text||':'||p_action;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_scope||':'||p_idempotency_key,0));

  select * into v_task from app_private.tasks t where t.id=p_task_id for update;
  if not found then raise exception using errcode='P0002',message='task_not_found'; end if;
  if p_link_token_hash is not null then
    if v_link.task_id<>v_task.id or v_link.property_id<>v_task.property_id
       or v_link.owner_account_id<>v_task.owner_account_id
       or v_link.expires_at>v_task.due_at+interval '48 hours' then
      raise exception using errcode='42501',message='scoped_task_link_scope_mismatch';
    end if;
  elsif not app_private.can_manage_task(v_task.property_id,v_task.owner_account_id) then
    raise exception using errcode='42501',message='task_manage_required';
  end if;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'task_id',p_task_id,'expected_version',p_expected_version,'action',p_action,
    'note',p_note,'claimed_name',p_claimed_name,'media_ids',to_jsonb(p_media_ids)
  )::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from app_private.task_transition_events e
  where e.idempotency_scope=v_scope and e.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_mismatch';
    end if;
    return jsonb_build_object('event_id',v_existing.id,'task_id',v_existing.task_id,
      'state',v_existing.to_state,'version',v_existing.resulting_version,'replayed',true);
  end if;
  if v_task.version<>p_expected_version then
    raise exception using errcode='40001',message='task_version_conflict';
  end if;
  if p_link_token_hash is not null and p_claimed_name is null then
    raise exception using errcode='22023',message='claimed_name_required';
  end if;
  if p_link_token_hash is null and p_claimed_name is not null then
    raise exception using errcode='22023',message='claimed_name_only_for_scoped_actor';
  end if;
  if p_action='request_rework' and (p_note is null or length(trim(p_note))=0) then
    raise exception using errcode='22023',message='rework_reason_required';
  end if;
  v_from := v_task.state;
  v_to := case p_action
    when 'accept' then 'accepted'::app_private.task_state
    when 'report_done' then 'reported_done'::app_private.task_state
    when 'confirm' then 'completed'::app_private.task_state
    when 'request_rework' then 'accepted'::app_private.task_state
    when 'cancel' then 'cancelled'::app_private.task_state
  end;
  if not ((p_action='accept' and v_from='open')
    or (p_action='report_done' and v_from in ('open','accepted'))
    or (p_action='confirm' and v_from='reported_done')
    or (p_action='request_rework' and v_from='reported_done')
    or (p_action='cancel' and v_from in ('open','accepted','reported_done'))) then
    raise exception using errcode='22023',message='invalid_task_transition';
  end if;
  if p_action='report_done' and v_task.required_for_readiness and (
      v_task.inspection_event_id is null or not exists (
        select 1 from app_private.inspection_submissions s
        where s.event_id=v_task.inspection_event_id and s.property_id=v_task.property_id
          and s.owner_account_id=v_task.owner_account_id and s.state='completed'
          and s.completed_at is not null
          and not exists (
            select 1 from app_private.inspection_snapshot_rooms sr
            where sr.snapshot_id=s.snapshot_id and sr.property_id=s.property_id
              and sr.owner_account_id=s.owner_account_id
              and not exists (
                select 1 from app_private.inspection_room_answers ra
                where ra.submission_id=s.id and ra.snapshot_room_id=sr.id
                  and ra.property_id=s.property_id and ra.owner_account_id=s.owner_account_id
              )
          )
      )
    ) then
    raise exception using errcode='22023',message='required_inspection_not_answered';
  end if;
  if cardinality(p_media_ids)>0 and exists (
    select 1 from unnest(p_media_ids) requested(id)
    left join app_private.media_assets a on a.id=requested.id
      and a.property_id=v_task.property_id and a.owner_account_id=v_task.owner_account_id
      and a.classification='private_task' and a.deleted_at is null and a.state='validated'
    where a.id is null
  ) then
    raise exception using errcode='42501',message='task_media_scope_invalid';
  end if;

  insert into app_private.task_transition_events(
    id,owner_account_id,property_id,task_id,action,from_state,to_state,
    actor_user_id,access_link_id,claimed_name,note,idempotency_scope,idempotency_key,
    request_hash,expected_version,resulting_version,created_at
  ) values (
    v_event_id,v_task.owner_account_id,v_task.property_id,v_task.id,p_action,v_from,v_to,
    v_actor,case when p_link_token_hash is not null then v_link.id end,
    nullif(trim(p_claimed_name),''),nullif(trim(p_note),''),v_scope,p_idempotency_key,
    v_hash,p_expected_version,p_expected_version+1,v_now
  );
  foreach v_media in array p_media_ids loop
    insert into app_private.task_transition_media(owner_account_id,property_id,transition_event_id,media_asset_id)
    values (v_task.owner_account_id,v_task.property_id,v_event_id,v_media);
  end loop;
  update app_private.tasks set state=v_to,version=version+1,updated_at=v_now,
    accepted_at=case when p_action='accept' then v_now when p_action='request_rework' then v_task.accepted_at else accepted_at end,
    reported_done_at=case when p_action='report_done' then v_now else reported_done_at end,
    confirmed_at=case when p_action='confirm' then v_now else confirmed_at end,
    confirmed_by=case when p_action='confirm' then v_actor else confirmed_by end
  where id=v_task.id;
  if p_action='report_done' then
    insert into app_private.outbox(event_kind,dedupe_key,property_id,owner_account_id,payload,next_attempt_at)
    values ('task.reported_done','task.reported_done:'||v_event_id::text,
      v_task.property_id,v_task.owner_account_id,
      jsonb_build_object('task_id',v_task.id,'transition_event_id',v_event_id),v_now);
  end if;
  v_ack := jsonb_build_object('event_id',v_event_id,'task_id',v_task.id,'state',v_to,
    'version',p_expected_version+1,'replayed',false);
  return v_ack;
end;
$$;
revoke all on function api.transition_task(uuid,integer,text,text,text,text,uuid[],text) from public,anon,authenticated;
grant execute on function api.transition_task(uuid,integer,text,text,text,text,uuid[],text) to authenticated,service_role;
grant usage on schema api to service_role;
grant app_executor to current_user with set true, inherit false;
alter function api.transition_task(uuid,integer,text,text,text,text,uuid[],text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

revoke all on app_private.task_transition_events,app_private.task_transition_media from public,anon,authenticated;
revoke all on app_private.tasks from anon,authenticated;
