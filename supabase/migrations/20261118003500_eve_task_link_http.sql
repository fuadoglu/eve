-- EVE-017.3: task link creation, revocation and safe scoped read.
-- Raw bearer tokens stay in the server response only. The database stores hashes.

grant app_executor to current_user with set true, inherit false;

alter table app_private.access_links
  add column idempotency_key_hash varchar(64),
  add column request_hash varchar(64);
alter table app_private.access_links
  add constraint task_link_request_hashes check (
    (idempotency_key_hash is null and request_hash is null)
    or (kind='task' and created_by is not null
      and idempotency_key_hash ~ '^[0-9a-f]{64}$'
      and request_hash ~ '^[0-9a-f]{64}$')
  );
create unique index access_links_task_request_once
  on app_private.access_links(created_by,task_id,idempotency_key_hash)
  where kind='task' and idempotency_key_hash is not null;
grant insert on app_private.access_links to app_executor;
create policy access_links_task_create_internal on app_private.access_links
  for insert to app_executor with check (
    kind='task' and task_id is not null and created_by=app_private.current_actor_id()
    and scopes='["task.read","task.accept","task.report_done"]'::jsonb
    and idempotency_key_hash is not null and request_hash is not null
  );

grant create on schema api to app_executor;
create function api.create_task_link(
  p_task_id uuid,p_token_hash text,p_idempotency_key_hash text,
  p_request_hash text,p_expires_at timestamptz default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_actor uuid := app_private.current_actor_id();
  v_task app_private.tasks%rowtype; v_existing app_private.access_links%rowtype;
  v_now timestamptz := statement_timestamp(); v_expiry timestamptz;
begin
  if v_actor is null then raise exception using errcode='42501',message='task_manager_required'; end if;
  if p_task_id is null or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
    or p_idempotency_key_hash is null or p_idempotency_key_hash !~ '^[0-9a-f]{64}$'
    or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='invalid_task_link_input';
  end if;
  select * into v_task from app_private.tasks where id=p_task_id for update;
  if not found then raise exception using errcode='P0002',message='task_not_found'; end if;
  if v_task.state in ('completed','cancelled') or not app_private.can_manage_task(v_task.property_id,v_task.owner_account_id) then
    raise exception using errcode='42501',message='task_manage_required';
  end if;
  select * into v_existing from app_private.access_links
    where kind='task' and task_id=p_task_id and created_by=v_actor
      and idempotency_key_hash=p_idempotency_key_hash for update;
  if found then
    if v_existing.request_hash<>p_request_hash or v_existing.token_hash<>p_token_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_mismatch';
    end if;
    if v_existing.revoked_at is not null or v_existing.expires_at<=v_now then
      raise exception using errcode='23505',message='task_link_no_longer_active';
    end if;
    return jsonb_build_object('link_id',v_existing.id,'expires_at',v_existing.expires_at,'replayed',true);
  end if;
  v_expiry := coalesce(p_expires_at,least(v_now+interval '7 days',v_task.due_at+interval '48 hours'));
  if v_expiry<=v_now or v_expiry>v_now+interval '30 days'
    or v_expiry>v_task.due_at+interval '48 hours' then
    raise exception using errcode='22023',message='invalid_task_link_expiry';
  end if;
  insert into app_private.access_links(owner_account_id,property_id,token_hash,kind,task_id,
    scopes,expires_at,created_by,idempotency_key_hash,request_hash)
  values(v_task.owner_account_id,v_task.property_id,p_token_hash,'task',p_task_id,
    '["task.read","task.accept","task.report_done"]'::jsonb,
    v_expiry,v_actor,p_idempotency_key_hash,p_request_hash)
  returning * into v_existing;
  return jsonb_build_object('link_id',v_existing.id,'expires_at',v_existing.expires_at,'replayed',false);
end;
$$;
revoke all on function api.create_task_link(uuid,text,text,text,timestamptz) from public,anon,authenticated,service_role;
grant execute on function api.create_task_link(uuid,text,text,text,timestamptz) to authenticated;
alter function api.create_task_link(uuid,text,text,text,timestamptz) owner to app_executor;

create function api.revoke_task_link(p_link_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_link app_private.access_links%rowtype;
begin
  if p_link_id is null or app_private.current_actor_id() is null then
    raise exception using errcode='42501',message='owner_required';
  end if;
  select * into v_link from app_private.access_links
    where id=p_link_id and kind='task' for update;
  if not found then raise exception using errcode='P0002',message='task_link_not_found'; end if;
  if not app_private.is_owner(v_link.owner_account_id) then
    raise exception using errcode='42501',message='owner_required';
  end if;
  if v_link.revoked_at is null then
    update app_private.access_links set revoked_at=statement_timestamp(),
      updated_at=statement_timestamp(),version=version+1 where id=p_link_id;
  end if;
  return jsonb_build_object('accepted',true);
end;
$$;
revoke all on function api.revoke_task_link(uuid) from public,anon,authenticated,service_role;
grant execute on function api.revoke_task_link(uuid) to authenticated;
alter function api.revoke_task_link(uuid) owner to app_executor;

-- app_executor is internal and NOLOGIN. The bridge has no anonymous grant.
grant select on app_private.properties to app_executor;
create policy properties_task_link_internal_read on app_private.properties
  for select to app_executor using (true);
create function api.read_scoped_task_for_server(p_link_token_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_link app_private.access_links%rowtype; v_task app_private.tasks%rowtype;
  v_label text; v_address text;
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  if p_link_token_hash is null or p_link_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P0002',message='task_link_not_found';
  end if;
  select * into v_link from app_private.access_links
    where token_hash=p_link_token_hash and kind='task';
  if not found then raise exception using errcode='P0002',message='task_link_not_found'; end if;
  if v_link.revoked_at is not null or v_link.expires_at<=statement_timestamp() then
    raise exception using errcode='P4100',message='task_link_expired';
  end if;
  if not (v_link.scopes ? 'task.read') then
    raise exception using errcode='P0002',message='task_link_not_found';
  end if;
  select * into v_task from app_private.tasks
    where id=v_link.task_id and property_id=v_link.property_id
      and owner_account_id=v_link.owner_account_id;
  if not found or v_task.state='cancelled' then
    raise exception using errcode='P4100',message='task_link_expired';
  end if;
  select p.name,p.private_address into v_label,v_address from app_private.properties p
    where p.id=v_link.property_id and p.owner_account_id=v_link.owner_account_id;
  if not found then raise exception using errcode='P0002',message='task_link_not_found'; end if;
  return jsonb_build_object('task_id',v_task.id,'property_label',v_label,
    'address',v_address,'title',v_task.title,'due_at',v_task.due_at,
    'state',v_task.state,'version',v_task.version);
end;
$$;
revoke all on function api.read_scoped_task_for_server(text) from public,anon,authenticated,service_role;
grant execute on function api.read_scoped_task_for_server(text) to service_role;
alter function api.read_scoped_task_for_server(text) owner to app_executor;

create function api.transition_scoped_task_for_server(
  p_link_token_hash text,p_expected_version integer,p_action text,
  p_idempotency_key text,p_claimed_name text,p_note text default null,
  p_media_ids uuid[] default array[]::uuid[]
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_link app_private.access_links%rowtype; v_ack jsonb;
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  if p_link_token_hash is null or p_link_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='P0002',message='task_link_not_found';
  end if;
  select * into v_link from app_private.access_links
    where token_hash=p_link_token_hash and kind='task';
  if not found then raise exception using errcode='P0002',message='task_link_not_found'; end if;
  v_ack := api.transition_task(v_link.task_id,p_expected_version,p_action,
    p_idempotency_key,p_note,p_claimed_name,p_media_ids,p_link_token_hash);
  return api.read_scoped_task_for_server(p_link_token_hash);
end;
$$;
revoke all on function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[])
  from public,anon,authenticated,service_role;
grant execute on function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[])
  to service_role;
alter function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[]) owner to app_executor;
revoke create on schema api from app_executor;
revoke app_executor from current_user;
