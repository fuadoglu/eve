-- EVE-022.1: reserve declared upload bytes atomically before Storage URL issuance.
-- Pending intents count toward the property's quota until finalize/reject/expiry.
alter table app_private.media_assets
  add column upload_expires_at timestamptz,
  add constraint media_upload_expiry_state
    check (upload_expires_at is null or state='pending');

grant select on app_private.properties, app_private.property_memberships,
  app_private.subscriptions, app_private.media_assets, app_private.idempotency_keys to app_executor;
grant insert on app_private.media_assets, app_private.idempotency_keys to app_executor;
grant update on app_private.idempotency_keys to app_executor;
grant usage on schema extensions to app_executor;

create function app_private.can_write_media(
  p_property_id uuid, p_owner_account_id uuid, p_classification app_private.media_classification
)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select (select app_private.current_actor_id()) is not null
    and p_property_id is not null and p_owner_account_id is not null
    and p_classification is not null
    and (
      app_private.is_owner(p_owner_account_id)
      or exists (
        select 1 from app_private.property_memberships m
        where m.property_id=p_property_id and m.owner_account_id=p_owner_account_id
          and m.user_id=(select app_private.current_actor_id()) and m.revoked_at is null
          and (p_classification <> 'private_receipt' or m.permission='full')
      )
    );
$$;
revoke all on function app_private.can_write_media(uuid,uuid,app_private.media_classification)
  from public, anon, authenticated;
grant execute on function app_private.can_write_media(uuid,uuid,app_private.media_classification)
  to app_executor;

create policy subscriptions_media_upload_read on app_private.subscriptions
  for select to app_executor using (
    app_private.can_write_media(property_id,owner_account_id,'public_property')
  );
create policy media_assets_upload_quota_read on app_private.media_assets
  for select to app_executor using (
    app_private.is_owner(owner_account_id)
    or exists (select 1 from app_private.property_memberships m
      where m.property_id=media_assets.property_id
        and m.owner_account_id=media_assets.owner_account_id
        and m.user_id=(select app_private.current_actor_id()) and m.revoked_at is null)
  );
create policy media_assets_upload_create on app_private.media_assets
  for insert to app_executor with check (
    state='pending' and deleted_at is null
    and upload_expires_at > statement_timestamp()
    and app_private.can_write_media(property_id,owner_account_id,classification)
    and (classification<>'private_inventory'
      or app_private.has_property_capability(property_id,owner_account_id,'inventory.manage'))
  );
create policy idempotency_keys_upload_read on app_private.idempotency_keys
  for select to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':createUploadIntent'
  );
create policy idempotency_keys_upload_create on app_private.idempotency_keys
  for insert to app_executor with check (
    actor_scope=(select app_private.current_actor_id())::text||':createUploadIntent'
  );
create policy idempotency_keys_upload_update on app_private.idempotency_keys
  for update to app_executor using (
    actor_scope=(select app_private.current_actor_id())::text||':createUploadIntent'
  ) with check (
    actor_scope=(select app_private.current_actor_id())::text||':createUploadIntent'
  );

-- Internal-only primitive. An authenticated server adapter must resolve the
-- exact media classification from its validated capability/resource scope.
-- This function intentionally is not exposed through the Data API.
create function app_private.reserve_media_upload(
  p_property_id uuid,
  p_kind text,
  p_classification text,
  p_filename text,
  p_mime text,
  p_size_bytes bigint,
  p_duration_seconds integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_owner uuid;
  v_class app_private.media_classification;
  v_bucket text;
  v_limit_bytes bigint := 1073741824;
  v_reserved_bytes bigint;
  v_media_id uuid := gen_random_uuid();
  v_object_key text;
  v_expires_at timestamptz := statement_timestamp() + interval '15 minutes';
  v_request_hash text;
  v_actor_scope text;
  v_prior app_private.idempotency_keys%rowtype;
  v_replay boolean := false;
begin
  if v_actor is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  if p_property_id is null or p_kind is null or p_kind not in ('image','video','audio','document')
    or p_classification is null or p_filename is null or p_mime is null
    or length(p_filename) not between 1 and 200
    or p_mime not in ('image/jpeg','image/png','image/webp','video/mp4',
                      'audio/webm','audio/mp4','application/pdf')
    or p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > 104857600
    or p_duration_seconds < 1
    or p_idempotency_key is null or length(p_idempotency_key) not between 1 and 128 then
    raise exception using errcode='22023', message='invalid_upload_input';
  end if;
  if (p_kind='image' and (p_mime not like 'image/%' or p_size_bytes>15728640 or p_duration_seconds is not null))
    or (p_kind='video' and (p_mime <> 'video/mp4' or p_duration_seconds is null or p_duration_seconds>300))
    or (p_kind='audio' and (p_mime not like 'audio/%' or p_duration_seconds is null or p_duration_seconds>60))
    or (p_kind='document' and (p_mime <> 'application/pdf' or p_duration_seconds is not null)) then
    raise exception using errcode='22023', message='upload_kind_limit_mismatch';
  end if;
  begin
    v_class := p_classification::app_private.media_classification;
  exception when invalid_text_representation then
    raise exception using errcode='22023', message='invalid_media_classification';
  end;
  v_bucket := case v_class
    when 'public_property' then 'eve-public-property'
    when 'public_guide' then 'eve-public-guide'
    when 'private_guest' then 'eve-private-guest'
    when 'private_receipt' then 'eve-private-receipt'
    when 'private_inspection' then 'eve-private-inspection'
    when 'private_task' then 'eve-private-task'
    when 'private_inventory' then 'eve-private-inventory'
  end;

  select p.owner_account_id into v_owner
  from app_private.properties p
  where p.id=p_property_id
    and app_private.can_write_media(p.id,p.owner_account_id,v_class);
  if v_owner is null then
    raise exception using errcode='P0002', message='property_not_found';
  end if;
  if v_class='private_inventory'
    and not app_private.has_property_capability(p_property_id,v_owner,'inventory.manage') then
    raise exception using errcode='42501', message='media_capability_required';
  end if;
  if not exists (
    select 1 from app_private.subscriptions s
    where s.property_id=p_property_id and s.owner_account_id=v_owner
      and s.state in ('trialing','active') and s.current_end > statement_timestamp()
  ) then
    raise exception using errcode='42501', message='active_entitlement_required';
  end if;

  v_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'property_id',p_property_id,'kind',p_kind,'classification',v_class::text,
    'filename',p_filename,'mime',p_mime,'size_bytes',p_size_bytes,
    'duration_seconds',p_duration_seconds)::text,'UTF8'),'sha256'),'hex');
  v_actor_scope := v_actor::text||':createUploadIntent';
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_scope||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i
  where i.actor_scope=v_actor_scope and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>statement_timestamp() then
    if v_prior.operation_id<>'createUploadIntent' or v_prior.request_hash<>v_request_hash then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict';
    end if;
    v_media_id := v_prior.result_id;
    v_replay := true;
  elsif found then
    update app_private.idempotency_keys set request_hash=v_request_hash,
      operation_id='createUploadIntent',response_status=null,result_id=null,
      created_at=statement_timestamp(),expires_at=statement_timestamp()+interval '24 hours'
    where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,
      created_at,expires_at)
    values (v_actor_scope,p_idempotency_key,v_request_hash,'createUploadIntent',
      statement_timestamp(),statement_timestamp()+interval '24 hours');
  end if;
  if v_replay then
    select a.upload_expires_at into v_expires_at from app_private.media_assets a
    where a.id=v_media_id and a.property_id=p_property_id and a.owner_account_id=v_owner;
    if not found then
      raise exception using errcode='23505',message='idempotency_result_unavailable';
    end if;
    return jsonb_build_object('media_id',v_media_id,'reserved_bytes',p_size_bytes,'expires_at',v_expires_at);
  end if;

  -- A transaction-scoped advisory lock serializes all reservations for this property.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_property_id::text,0));
  select coalesce(sum(a.size_bytes),0) into v_reserved_bytes
  from app_private.media_assets a
  where a.property_id=p_property_id and a.owner_account_id=v_owner and a.deleted_at is null
    and (a.state='validated' or (a.state='pending' and
         (a.upload_expires_at is null or a.upload_expires_at>statement_timestamp())));
  if v_reserved_bytes + p_size_bytes > v_limit_bytes then
    raise exception using errcode='22003', message='property_media_quota_exceeded';
  end if;

  v_object_key := v_media_id::text;
  insert into app_private.media_assets(
    id,owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes,
    duration_seconds,state,upload_expires_at
  ) values (
    v_media_id,v_owner,p_property_id,v_class,v_bucket,v_object_key,p_mime,p_size_bytes,
    p_duration_seconds,'pending',v_expires_at
  );
  update app_private.idempotency_keys set response_status=201,result_id=v_media_id
  where actor_scope=v_actor_scope and key=p_idempotency_key;
  return jsonb_build_object('media_id',v_media_id,'reserved_bytes',p_size_bytes,'expires_at',v_expires_at);
end;
$$;
revoke all on function app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text)
  from public, anon, authenticated;
grant app_executor to current_user with set true, inherit false;
alter function app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text) owner to app_executor;
revoke app_executor from current_user;
grant execute on function app_private.reserve_media_upload(uuid,text,text,text,text,bigint,integer,text)
  to app_executor;
