-- EVE-019.3: transaction-scoped inventory copy and verified-row import core.
-- File parsing and Storage byte verification remain server adapter concerns.
create or replace function app_private.has_property_capability(
  p_property_id uuid, p_owner_account_id uuid, p_capability text
)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select case
    when (select app_private.current_actor_id()) is null
      or p_property_id is null or p_owner_account_id is null then false
    when p_capability is null
      or p_capability not in ('property.read','reservation.read','finance.read',
                              'inventory.read','inventory.manage','import.manage') then false
    when app_private.is_owner(p_owner_account_id) then true
    else exists (
      select 1 from app_private.property_memberships m
      where m.property_id=p_property_id and m.owner_account_id=p_owner_account_id
        and m.user_id=(select app_private.current_actor_id()) and m.revoked_at is null
        and (p_capability <> 'finance.read' or m.permission='full')
    )
  end;
$$;
revoke all on function app_private.has_property_capability(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function app_private.has_property_capability(uuid,uuid,text) to app_executor;

create function api.copy_inventory(
  p_property_id uuid, p_source_property_id uuid, p_include_media boolean default false
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_target_owner uuid;
  v_source_owner uuid;
  v_target_room uuid;
  v_room record;
  v_item record;
begin
  if p_property_id is null or p_source_property_id is null
     or p_property_id = p_source_property_id or p_include_media is null then
    raise exception using errcode='22023', message='invalid_inventory_copy';
  end if;
  -- SQL cannot clone Storage bytes and must never attach a source property's
  -- private media ID to the destination. A server copy workflow is required.
  if p_include_media then
    raise exception using errcode='0A000', message='inventory_media_copy_requires_server';
  end if;

  v_target_owner := app_private.inventory_write_owner(p_property_id);
  select p.owner_account_id into v_source_owner
  from app_private.properties p
  where p.id=p_source_property_id
    and app_private.has_property_capability(p.id,p.owner_account_id,'inventory.read');
  if v_source_owner is null then
    raise exception using errcode='P0002', message='source_property_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('inventory-copy:'||p_property_id::text,0));
  for v_room in
    select r.id,r.name,r.position
    from app_private.rooms r
    where r.property_id=p_source_property_id and r.owner_account_id=v_source_owner
      and r.archived_at is null
    order by r.position,r.id
  loop
    select r.id into v_target_room from app_private.rooms r
    where r.property_id=p_property_id and r.owner_account_id=v_target_owner
      and r.archived_at is null and lower(btrim(r.name))=lower(btrim(v_room.name))
    order by r.id limit 1;
    if v_target_room is null then
      insert into app_private.rooms(owner_account_id,property_id,name,position)
      values(v_target_owner,p_property_id,v_room.name,v_room.position)
      returning id into v_target_room;
    end if;
    for v_item in
      select i.name,i.quantity,i.unit,i.state,i.consumable,i.min_stock
      from app_private.inventory_items i
      where i.property_id=p_source_property_id and i.owner_account_id=v_source_owner
        and i.room_id=v_room.id and i.archived_at is null
      order by i.id
    loop
      if not exists (
        select 1 from app_private.inventory_items i
        where i.property_id=p_property_id and i.owner_account_id=v_target_owner
          and i.room_id=v_target_room and i.archived_at is null
          and lower(btrim(i.name))=lower(btrim(v_item.name))
      ) then
        insert into app_private.inventory_items(
          owner_account_id,property_id,room_id,name,quantity,unit,state,consumable,min_stock
        ) values (
          v_target_owner,p_property_id,v_target_room,v_item.name,v_item.quantity,
          v_item.unit,v_item.state,v_item.consumable,v_item.min_stock
        );
      end if;
    end loop;
    v_target_room := null;
  end loop;

  return api.get_inventory(p_property_id);
end;
$$;

revoke all on function api.copy_inventory(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function api.copy_inventory(uuid,uuid,boolean) to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.copy_inventory(uuid,uuid,boolean) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

-- The parser supplies normalized rows only after checking the uploaded file's
-- bytes. These private functions are deliberately absent from the Data API.
grant select,insert,update on app_private.import_jobs to app_executor;
grant select,insert on app_private.import_rows to app_executor;
create policy import_jobs_inventory_read on app_private.import_jobs
  for select to app_executor using (
    kind='inventory' and requested_by=(select app_private.current_actor_id())
    and app_private.has_property_capability(
      (preview->>'property_id')::uuid,owner_account_id,'import.manage'));
create policy import_jobs_inventory_insert on app_private.import_jobs
  for insert to app_executor with check (
    kind='inventory' and requested_by=(select app_private.current_actor_id())
    and app_private.has_property_capability(
      (preview->>'property_id')::uuid,owner_account_id,'import.manage'));
create policy import_jobs_inventory_update on app_private.import_jobs
  for update to app_executor using (
    kind='inventory' and requested_by=(select app_private.current_actor_id())
    and app_private.has_property_capability(
      (preview->>'property_id')::uuid,owner_account_id,'import.manage'))
  with check (
    kind='inventory' and requested_by=(select app_private.current_actor_id())
    and app_private.has_property_capability(
      (preview->>'property_id')::uuid,owner_account_id,'import.manage'));
create policy import_rows_inventory_read on app_private.import_rows
  for select to app_executor using (
    app_private.has_property_capability(property_id,owner_account_id,'import.manage'));
create policy import_rows_inventory_insert on app_private.import_rows
  for insert to app_executor with check (
    app_private.has_property_capability(property_id,owner_account_id,'import.manage'));

create function app_private.preview_inventory_rows(
  p_property_id uuid,p_file_hash text,p_rows jsonb
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_owner uuid;
  v_actor uuid := app_private.current_actor_id();
  v_job app_private.import_jobs%rowtype;
  v_errors jsonb := '[]'::jsonb;
  v_error_count integer := 0;
  v_error_field text;
  v_error_message text;
  v_duplicates text[];
  v_row jsonb;
  v_index integer;
  v_key text;
  v_name text;
  v_room text;
  v_quantity text;
  v_hash text;
begin
  if p_file_hash is null or p_file_hash !~ '^[a-f0-9]{64}$'
     or p_rows is null or jsonb_typeof(p_rows)<>'array'
     or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>10000 then
    raise exception using errcode='22023',message='invalid_inventory_import_input';
  end if;
  v_owner := app_private.inventory_write_owner(p_property_id);
  if not app_private.has_property_capability(p_property_id,v_owner,'import.manage') then
    raise exception using errcode='42501',message='import_capability_required';
  end if;
  select array_agg(k) into v_duplicates from (
    select x.value->>'source_row_key' as k
    from jsonb_array_elements(p_rows) x
    group by 1 having count(*)>1
  ) duplicates;
  for v_row,v_index in
    select x.value,x.ordinality::integer
    from jsonb_array_elements(p_rows) with ordinality x(value,ordinality)
  loop
    v_error_field := null;
    v_error_message := null;
    v_key := v_row->>'source_row_key';
    v_room := v_row->>'room_name';
    v_name := v_row->>'name';
    v_quantity := v_row->>'quantity';
    if jsonb_typeof(v_row)<>'object' then
      v_error_field := 'row'; v_error_message := 'invalid_row';
    elsif exists (select 1 from jsonb_object_keys(v_row) k
      where k not in ('source_row_key','room_name','name','quantity','unit','condition')) then
      v_error_field := 'row'; v_error_message := 'unknown_field';
    elsif v_key is null or length(v_key)<1 or length(v_key)>160
       or v_key ~ '[[:cntrl:]]' then
      v_error_field := 'source_row_key'; v_error_message := 'invalid_source_row_key';
    elsif v_room is null or length(btrim(v_room))<1 or length(v_room)>100 then
      v_error_field := 'room_name'; v_error_message := 'invalid_room_name';
    elsif v_name is null or length(btrim(v_name))<1 or length(v_name)>160 then
      v_error_field := 'name'; v_error_message := 'invalid_item_name';
    elsif v_quantity is null or v_quantity !~ '^[0-9]{1,9}(\.[0-9]{1,3})?$'
       or (v_quantity ~ '^[0-9]{1,9}(\.[0-9]{1,3})?$'
         and v_quantity::numeric > 999999999.999) then
      v_error_field := 'quantity'; v_error_message := 'invalid_quantity';
    elsif coalesce(v_row->>'unit','piece') not in ('piece','set','liter','kg','pack') then
      v_error_field := 'unit'; v_error_message := 'invalid_unit';
    elsif coalesce(v_row->>'condition','ok') not in ('ok','needs_repair','damaged','missing') then
      v_error_field := 'condition'; v_error_message := 'invalid_condition';
    elsif exists (select 1 from app_private.import_rows ir
      where ir.owner_account_id=v_owner and ir.source_row_key=v_key) then
      v_error_field := 'source_row_key'; v_error_message := 'already_imported';
    elsif v_key=any(v_duplicates) then
      v_error_field := 'source_row_key'; v_error_message := 'duplicate_source_row_key';
    end if;
    if v_error_field is not null then
      v_error_count := v_error_count+1;
      if v_error_count<=1000 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'row',v_index,'field',v_error_field,'message',v_error_message));
      end if;
    end if;
  end loop;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'property_id',p_property_id,'file_hash',p_file_hash,'rows',p_rows)::text,'UTF8'),'sha256'),'hex');
  insert into app_private.import_jobs(
    owner_account_id,requested_by,kind,state,file_hash,preview_hash,preview,row_count
  ) values (
    v_owner,v_actor,'inventory',
    case when v_error_count=0 then 'preview_ready'::app_private.import_state
      else 'invalid'::app_private.import_state end,
    p_file_hash,v_hash,jsonb_build_object('property_id',p_property_id,
      'rows',case when v_error_count=0 then p_rows else '[]'::jsonb end,
      'errors',v_errors,'error_count',v_error_count,'errors_truncated',v_error_count>1000),
    jsonb_array_length(p_rows)
  ) returning * into v_job;
  return jsonb_build_object('id',v_job.id,'property_id',p_property_id,'kind','inventory',
    'state',v_job.state::text,'preview_hash',v_hash,'row_count',v_job.row_count,
    'errors',v_errors,'error_count',v_error_count,'errors_truncated',v_error_count>1000,
    'version',v_job.version,'created_at',v_job.created_at,
    'updated_at',v_job.updated_at);
end;
$$;

create function app_private.commit_inventory_rows(
  p_job_id uuid,p_expected_version integer,p_preview_hash text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_job app_private.import_jobs%rowtype;
  v_owner uuid;
  v_property uuid;
  v_row jsonb;
  v_index integer;
  v_room_id uuid;
  v_item_id uuid;
  v_key text;
begin
  if p_job_id is null or p_expected_version is null or p_expected_version<1
     or p_preview_hash is null or p_preview_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode='22023',message='invalid_inventory_commit_input';
  end if;
  select * into v_job from app_private.import_jobs j where j.id=p_job_id for update;
  if not found or v_job.kind<>'inventory' then
    raise exception using errcode='P0002',message='import_job_not_found';
  end if;
  v_property := (v_job.preview->>'property_id')::uuid;
  v_owner := app_private.inventory_write_owner(v_property);
  if v_owner<>v_job.owner_account_id or v_job.requested_by<>app_private.current_actor_id()
     or not app_private.has_property_capability(v_property,v_owner,'import.manage') then
    raise exception using errcode='P0002',message='import_job_not_found';
  end if;
  if v_job.preview_hash<>p_preview_hash then
    raise exception using errcode='40001',message='import_preview_hash_mismatch';
  end if;
  if v_job.state='completed' then
    return jsonb_build_object('id',v_job.id,'property_id',v_property,'kind','inventory',
      'state','completed','preview_hash',v_job.preview_hash,'row_count',v_job.row_count,
      'errors','[]'::jsonb,'error_count',0,'errors_truncated',false,
      'version',v_job.version,'created_at',v_job.created_at,
      'updated_at',v_job.updated_at);
  end if;
  if v_job.state<>'preview_ready' or v_job.version<>p_expected_version
     or jsonb_array_length(v_job.preview->'errors')<>0 then
    raise exception using errcode='40001',message='import_preview_stale_or_invalid';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('inventory-import:'||v_property::text,0));
  for v_row,v_index in
    select x.value,x.ordinality::integer
    from jsonb_array_elements(v_job.preview->'rows') with ordinality x(value,ordinality)
  loop
    v_key := v_row->>'source_row_key';
    if exists (select 1 from app_private.import_rows ir
      where ir.owner_account_id=v_owner and ir.source_row_key=v_key) then
      raise exception using errcode='23505',message='inventory_import_source_duplicate';
    end if;
    select id into v_room_id from app_private.rooms r
    where r.property_id=v_property and r.owner_account_id=v_owner and r.archived_at is null
      and lower(btrim(r.name))=lower(btrim(v_row->>'room_name'))
    order by r.id limit 1;
    if v_room_id is null then
      insert into app_private.rooms(owner_account_id,property_id,name,position)
      values(v_owner,v_property,v_row->>'room_name',v_index)
      returning id into v_room_id;
    end if;
    if exists (select 1 from app_private.inventory_items i
      where i.property_id=v_property and i.owner_account_id=v_owner
        and i.room_id=v_room_id and i.archived_at is null
        and lower(btrim(i.name))=lower(btrim(v_row->>'name'))) then
      raise exception using errcode='23505',message='inventory_import_existing_item';
    end if;
    insert into app_private.inventory_items(
      owner_account_id,property_id,room_id,name,quantity,unit,state
    ) values (
      v_owner,v_property,v_room_id,v_row->>'name',(v_row->>'quantity')::numeric,
      coalesce(v_row->>'unit','piece'),
      coalesce(v_row->>'condition','ok')::app_private.inventory_state
    ) returning id into v_item_id;
    insert into app_private.import_rows(
      owner_account_id,property_id,import_job_id,source_row_key,row_number,created_inventory_item_id
    ) values (v_owner,v_property,v_job.id,v_key,v_index,v_item_id);
    v_room_id := null;
  end loop;
  update app_private.import_jobs set state='completed',committed_at=statement_timestamp(),
    updated_at=statement_timestamp(),version=version+1
  where id=v_job.id returning * into v_job;
  return jsonb_build_object('id',v_job.id,'property_id',v_property,'kind','inventory',
    'state','completed','preview_hash',v_job.preview_hash,'row_count',v_job.row_count,
    'errors','[]'::jsonb,'error_count',0,'errors_truncated',false,
    'version',v_job.version,'created_at',v_job.created_at,
    'updated_at',v_job.updated_at);
end;
$$;

revoke all on function app_private.preview_inventory_rows(uuid,text,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function app_private.commit_inventory_rows(uuid,integer,text)
  from public,anon,authenticated,service_role;
grant execute on function app_private.preview_inventory_rows(uuid,text,jsonb) to app_executor;
grant execute on function app_private.commit_inventory_rows(uuid,integer,text) to app_executor;
grant create on schema app_private to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function app_private.preview_inventory_rows(uuid,text,jsonb) owner to app_executor;
alter function app_private.commit_inventory_rows(uuid,integer,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema app_private from app_executor;
