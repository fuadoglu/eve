-- EVE-022.2: server-validated file finalization.
-- The private mutation stays in app_private. Only the server secret role can
-- invoke the narrow api wrapper after it has validated the user session.

grant select, update on app_private.media_assets, app_private.idempotency_keys to app_executor;

create policy media_assets_finalize_update on app_private.media_assets
  for update to app_executor
  using (
    state='pending' and deleted_at is null
    and upload_expires_at > statement_timestamp()
    and app_private.can_write_media(property_id,owner_account_id,classification)
    and (classification<>'private_inventory' or
      app_private.has_property_capability(property_id,owner_account_id,'inventory.manage'))
  )
  with check (
    state='validated' and deleted_at is null and upload_expires_at is null
    and app_private.can_write_media(property_id,owner_account_id,classification)
    and (classification<>'private_inventory' or
      app_private.has_property_capability(property_id,owner_account_id,'inventory.manage'))
  );

create policy idempotency_keys_finalize_read on app_private.idempotency_keys
  for select to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':finalizeMedia'
  );
create policy idempotency_keys_finalize_create on app_private.idempotency_keys
  for insert to app_executor with check (
    actor_scope=(select app_private.current_actor_id())::text||':finalizeMedia'
  );
create policy idempotency_keys_finalize_update on app_private.idempotency_keys
  for update to app_executor
  using (actor_scope=(select app_private.current_actor_id())::text||':finalizeMedia')
  with check (actor_scope=(select app_private.current_actor_id())::text||':finalizeMedia');

create function app_private.finalize_media_upload(
  p_media_id uuid,
  p_mime text,
  p_size_bytes bigint,
  p_duration_seconds integer,
  p_sha256 text,
  p_idempotency_key text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_media app_private.media_assets%rowtype;
  v_prior app_private.idempotency_keys%rowtype;
  v_actor_scope text;
  v_request_hash text;
  v_kind text;
begin
  if v_actor is null then
    raise exception using errcode='28000',message='authentication_required';
  end if;
  if p_media_id is null or p_mime not in ('image/jpeg','image/png','image/webp','video/mp4',
      'audio/webm','audio/mp4','application/pdf')
     or p_size_bytes is null or p_size_bytes<1 or p_size_bytes>104857600
     or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
     or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$'
     or p_duration_seconds < 1 then
    raise exception using errcode='22023',message='invalid_media_finalize_input';
  end if;
  if (p_mime like 'image/%' and (p_size_bytes>15728640 or p_duration_seconds is not null))
     or (p_mime='video/mp4' and (p_duration_seconds is null or p_duration_seconds>300))
     or (p_mime in ('audio/webm','audio/mp4') and (p_duration_seconds is null or p_duration_seconds>60))
     or (p_mime='application/pdf' and p_duration_seconds is not null) then
    raise exception using errcode='22023',message='media_finalize_limit_mismatch';
  end if;

  v_actor_scope := v_actor::text||':finalizeMedia';
  v_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'media_id',p_media_id,'mime',p_mime,'size_bytes',p_size_bytes,
    'duration_seconds',p_duration_seconds,'sha256',p_sha256)::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_scope||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i
    where i.actor_scope=v_actor_scope and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>statement_timestamp() then
    if v_prior.operation_id<>'finalizeMedia' or v_prior.request_hash<>v_request_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict';
    end if;
    select * into v_media from app_private.media_assets a
      where a.id=v_prior.result_id and a.state='validated' and a.deleted_at is null;
    if not found then raise exception using errcode='23505',message='idempotency_result_unavailable'; end if;
    if not app_private.can_write_media(v_media.property_id,v_media.owner_account_id,v_media.classification)
       or (v_media.classification='private_inventory' and not app_private.has_property_capability(
         v_media.property_id,v_media.owner_account_id,'inventory.manage')) then
      raise exception using errcode='42501',message='media_capability_required';
    end if;
  else
    if found then
      update app_private.idempotency_keys set request_hash=v_request_hash,
        operation_id='finalizeMedia',response_status=null,result_id=null,
        created_at=statement_timestamp(),expires_at=statement_timestamp()+interval '24 hours'
      where id=v_prior.id;
    else
      insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,
        created_at,expires_at)
      values(v_actor_scope,p_idempotency_key,v_request_hash,'finalizeMedia',
        statement_timestamp(),statement_timestamp()+interval '24 hours');
    end if;

    select * into v_media from app_private.media_assets a
      where a.id=p_media_id and a.deleted_at is null for update;
    if not found then raise exception using errcode='P0002',message='media_not_found'; end if;
    if v_media.state<>'pending' or v_media.upload_expires_at<=statement_timestamp() then
      raise exception using errcode='55000',message='media_upload_window_closed';
    end if;
    -- Actual bytes may release reserved quota, but may never grow the amount
    -- already admitted by the serialized upload-intent quota check.
    if p_size_bytes>v_media.size_bytes then
      raise exception using errcode='22003',message='media_size_exceeds_reserved_bytes';
    end if;
    if not app_private.can_write_media(v_media.property_id,v_media.owner_account_id,v_media.classification) then
      raise exception using errcode='42501',message='media_capability_required';
    end if;
    if v_media.classification='private_inventory' and not app_private.has_property_capability(
      v_media.property_id,v_media.owner_account_id,'inventory.manage') then
      raise exception using errcode='42501',message='media_capability_required';
    end if;
    if p_mime<>v_media.mime then
      raise exception using errcode='22023',message='media_declared_mime_mismatch';
    end if;
    update app_private.media_assets set state='validated',mime=p_mime,size_bytes=p_size_bytes,
      duration_seconds=p_duration_seconds,sha256=p_sha256,upload_expires_at=null,
      updated_at=statement_timestamp(),version=version+1
    where id=p_media_id returning * into v_media;
    update app_private.idempotency_keys set response_status=200,result_id=p_media_id
      where actor_scope=v_actor_scope and key=p_idempotency_key;
  end if;

  v_kind := case when v_media.mime like 'image/%' then 'image'
    when v_media.mime='video/mp4' then 'video'
    when v_media.mime in ('audio/webm','audio/mp4') then 'audio'
    else 'document' end;
  return jsonb_build_object('id',v_media.id,'property_id',v_media.property_id,'kind',v_kind,
    'classification',v_media.classification::text,'status',v_media.state::text,
    'size_bytes',v_media.size_bytes,'version',v_media.version,
    'created_at',v_media.created_at,'updated_at',v_media.updated_at);
end;
$$;
revoke all on function app_private.finalize_media_upload(uuid,text,bigint,integer,text,text)
  from public,anon,authenticated,service_role;
grant execute on function app_private.finalize_media_upload(uuid,text,bigint,integer,text,text)
  to app_executor;

-- Service-role only bridge for the authenticated server adapter. The private
-- mutation is not exposed to anon/authenticated Data API callers.
grant usage,create on schema api to app_executor;
create function api.finalize_media_upload_for_server(
  p_actor_user_id uuid,p_media_id uuid,p_mime text,p_size_bytes bigint,
  p_duration_seconds integer,p_sha256 text,p_idempotency_key text
)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
     or p_actor_user_id is null then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  perform pg_catalog.set_config('request.jwt.claim.sub',p_actor_user_id::text,true);
  return app_private.finalize_media_upload(p_media_id,p_mime,p_size_bytes,
    p_duration_seconds,p_sha256,p_idempotency_key);
end;
$$;
revoke all on function api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)
  from public,anon,authenticated,service_role;
grant execute on function api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)
  to service_role;

create function api.get_media_finalize_source_for_server(
  p_actor_user_id uuid,p_media_id uuid,p_idempotency_key text
)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_media app_private.media_assets%rowtype;
  v_prior app_private.idempotency_keys%rowtype;
  v_kind text;
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
     or p_actor_user_id is null or p_media_id is null
     or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  perform pg_catalog.set_config('request.jwt.claim.sub',p_actor_user_id::text,true);

  select * into v_prior from app_private.idempotency_keys i
  where i.actor_scope=p_actor_user_id::text||':finalizeMedia' and i.key=p_idempotency_key;
  if found and v_prior.expires_at>statement_timestamp() then
    if v_prior.operation_id<>'finalizeMedia' or v_prior.result_id is distinct from p_media_id then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict';
    end if;
    select * into v_media from app_private.media_assets a
    where a.id=p_media_id and a.state='validated' and a.deleted_at is null
      and app_private.can_write_media(a.property_id,a.owner_account_id,a.classification)
      and (a.classification<>'private_inventory' or
        app_private.has_property_capability(a.property_id,a.owner_account_id,'inventory.manage'));
    if not found then raise exception using errcode='42501',message='media_capability_required'; end if;
    v_kind := case when v_media.mime like 'image/%' then 'image'
      when v_media.mime='video/mp4' then 'video'
      when v_media.mime in ('audio/webm','audio/mp4') then 'audio'
      else 'document' end;
    return jsonb_build_object('replay',true,'result',jsonb_build_object(
      'id',v_media.id,'property_id',v_media.property_id,'kind',v_kind,
      'classification',v_media.classification::text,'status',v_media.state::text,
      'size_bytes',v_media.size_bytes,'version',v_media.version,
      'created_at',v_media.created_at,'updated_at',v_media.updated_at));
  end if;

  select * into v_media from app_private.media_assets a
  where a.id=p_media_id and a.state='pending' and a.deleted_at is null
    and a.upload_expires_at>statement_timestamp()
    and app_private.can_write_media(a.property_id,a.owner_account_id,a.classification)
    and (a.classification<>'private_inventory' or
      app_private.has_property_capability(a.property_id,a.owner_account_id,'inventory.manage'));
  if not found then raise exception using errcode='P0002',message='media_not_found'; end if;
  return jsonb_build_object('replay',false,'id',v_media.id,'classification',v_media.classification::text,
    'bucket',v_media.bucket,'object_key',v_media.object_key,'mime',v_media.mime,
    'max_size_bytes',v_media.size_bytes,'duration_seconds',v_media.duration_seconds);
end;
$$;
revoke all on function api.get_media_finalize_source_for_server(uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function api.get_media_finalize_source_for_server(uuid,uuid,text)
  to service_role;
grant app_executor to current_user with set true, inherit false;
alter function api.get_media_finalize_source_for_server(uuid,uuid,text)
  owner to app_executor;
alter function api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)
  owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
