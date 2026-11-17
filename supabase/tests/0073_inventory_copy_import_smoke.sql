-- EVE-019.3 / AT35: synthetic DB acceptance for tenant-safe inventory copy.
insert into auth.users(id) values
  ('aaaaaaaa-1930-0001-0000-000000000001'),
  ('aaaaaaaa-1930-0001-0000-000000000002')
on conflict (id) do nothing;

begin;
set local request.jwt.claim.sub = 'aaaaaaaa-1930-0001-0000-000000000001';
do $$
declare
  v_source uuid;
  v_target uuid;
  v_draft uuid;
  v_foreign uuid;
  v_room uuid;
  v_result jsonb;
  v_preview jsonb;
  v_valid jsonb;
  v_invalid jsonb;
  v_hash text := repeat('a',64);
  v_many_rows jsonb;
  v_owner uuid;
begin
  select id into v_source from api.create_property('Mənbə ev','Bakı');
  select id into v_target from api.create_property('Hədəf ev','Bakı');
  select id into v_draft from api.create_property('Draft ev','Bakı');
  -- Synthetic fixture: a second subscribed property. No billing claim is made.
  update app_private.subscriptions set state='active',current_end=statement_timestamp()+interval '30 days'
  where property_id=v_target;
  v_result := api.create_room(v_source,'Mətbəx');
  v_room := (v_result->>'id')::uuid;
  perform api.create_inventory_item(v_source,v_room,'Stəkan',6,'piece','ok',
    null,2500,null,null,'Model-7','secret-code','Məxfi qeyd',null);

  v_result := api.copy_inventory(v_target,v_source,false);
  if jsonb_array_length(v_result->'rooms') <> 1
     or jsonb_array_length(v_result->'items') <> 1
     or v_result->'items'->0->>'name' <> 'Stəkan'
     or (v_result->'items'->0->>'quantity')::numeric <> 6
     or v_result->'items'->0 ? 'note'
     or v_result->'items'->0->>'model' is not null
     or v_result->'items'->0->>'serial_number' is not null
     or v_result->'items'->0->>'purchase_minor' is not null then
    raise exception 'inventory copy payload mismatch or sensitive field leaked: %',v_result;
  end if;
  v_result := api.copy_inventory(v_target,v_source,false);
  if jsonb_array_length(v_result->'rooms') <> 1 or jsonb_array_length(v_result->'items') <> 1 then
    raise exception 'repeat copy duplicated inventory: %',v_result;
  end if;

  begin
    perform api.copy_inventory(v_target,v_source,true);
    raise exception 'media copy without byte clone accepted';
  exception when feature_not_supported then null;
  end;
  begin
    perform api.copy_inventory(v_target,v_target,false);
    raise exception 'same-property copy accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.copy_inventory(v_draft,v_source,false);
    raise exception 'draft target accepted';
  exception when insufficient_privilege then null;
  end;

  v_invalid := app_private.preview_inventory_rows(v_source,v_hash,
    '[{"source_row_key":"bad-1","room_name":"Mətbəx","name":"Qaşıq","quantity":"oops"}]'::jsonb);
  if v_invalid->>'state'<>'invalid'
     or v_invalid->'errors'->0->>'field'<>'quantity'
     or (v_invalid->'errors'->0->>'row')::integer<>1 then
    raise exception 'row-specific import preview error missing: %',v_invalid;
  end if;
  if (select j.preview->'rows' from app_private.import_jobs j
      where j.id=(v_invalid->>'id')::uuid)<>'[]'::jsonb then
    raise exception 'invalid raw import rows were retained';
  end if;
  select jsonb_agg(jsonb_build_object('source_row_key','overflow-'||n,
    'room_name','Mətbəx','name','Qaşıq-'||n,'quantity','bad') order by n)
    into v_many_rows from generate_series(1,1001) n;
  v_invalid := app_private.preview_inventory_rows(v_source,v_hash,v_many_rows);
  if v_invalid->>'state'<>'invalid'
     or (v_invalid->>'error_count')::integer<>1001
     or jsonb_array_length(v_invalid->'errors')<>1000
     or (v_invalid->>'errors_truncated')::boolean is not true then
    raise exception 'overflow errors misreported: %',v_invalid;
  end if;
  select jsonb_agg(jsonb_build_object('source_row_key','limit-'||n,
    'room_name','Mətbəx','name','Qaşıq-'||n,'quantity','1') order by n)
    into v_many_rows from generate_series(1,10001) n;
  begin
    perform app_private.preview_inventory_rows(v_source,v_hash,v_many_rows);
    raise exception '10001-row import accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform app_private.commit_inventory_rows((v_invalid->>'id')::uuid,1,v_invalid->>'preview_hash');
    raise exception 'invalid preview committed';
  exception when serialization_failure then null;
  end;

  v_valid := app_private.preview_inventory_rows(v_source,v_hash,
    '[{"source_row_key":"source-1","room_name":"Mətbəx","name":"Qaşıq","quantity":"4","unit":"piece"}]'::jsonb);
  if v_valid->>'state'<>'preview_ready' or jsonb_array_length(v_valid->'errors')<>0 then
    raise exception 'valid import preview rejected: %',v_valid;
  end if;
  begin
    perform app_private.commit_inventory_rows((v_valid->>'id')::uuid,1,repeat('b',64));
    raise exception 'wrong preview hash committed';
  exception when serialization_failure then null;
  end;
  begin
    perform app_private.commit_inventory_rows((v_valid->>'id')::uuid,2,v_valid->>'preview_hash');
    raise exception 'stale preview version committed';
  exception when serialization_failure then null;
  end;
  v_preview := app_private.commit_inventory_rows((v_valid->>'id')::uuid,1,v_valid->>'preview_hash');
  if v_preview->>'state'<>'completed' or (v_preview->>'version')::integer<>2
     or (select count(*) from app_private.inventory_items
         where property_id=v_source and name='Qaşıq')<>1 then
    raise exception 'import commit did not create one item: %',v_preview;
  end if;
  v_preview := app_private.commit_inventory_rows((v_valid->>'id')::uuid,1,v_valid->>'preview_hash');
  if v_preview->>'state'<>'completed'
     or (select count(*) from app_private.inventory_items
         where property_id=v_source and name='Qaşıq')<>1 then
    raise exception 'same-job replay duplicated item';
  end if;
  v_preview := app_private.preview_inventory_rows(v_source,v_hash,
    '[{"source_row_key":"source-1","room_name":"Mətbəx","name":"Qaşıq","quantity":"4"}]'::jsonb);
  if v_preview->>'state'<>'invalid'
     or v_preview->'errors'->0->>'message'<>'already_imported' then
    raise exception 'second import duplicate source key not reported: %',v_preview;
  end if;

  perform set_config('request.jwt.claim.sub','aaaaaaaa-1930-0001-0000-000000000002',true);
  select id into v_foreign from api.create_property('Yad ev','Gəncə');
  begin
    perform api.copy_inventory(v_foreign,v_source,false);
    raise exception 'cross-tenant source copied';
  exception when no_data_found then null;
  end;
  begin
    perform api.copy_inventory(v_target,v_foreign,false);
    raise exception 'cross-tenant target copied';
  exception when no_data_found then null;
  end;
  begin
    perform app_private.preview_inventory_rows(v_source,v_hash,
      '[{"source_row_key":"foreign-1","room_name":"Mətbəx","name":"Çəngəl","quantity":"2"}]'::jsonb);
    raise exception 'cross-tenant import preview accepted';
  exception when no_data_found then null;
  end;
  begin
    perform app_private.commit_inventory_rows((v_valid->>'id')::uuid,1,v_valid->>'preview_hash');
    raise exception 'cross-tenant import commit accepted';
  exception when no_data_found then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-1930-0001-0000-000000000001';
do $$
begin
  if not has_function_privilege('authenticated','api.copy_inventory(uuid,uuid,boolean)','EXECUTE')
     or has_function_privilege('anon','api.copy_inventory(uuid,uuid,boolean)','EXECUTE') then
    raise exception 'copy RPC grant boundary changed';
  end if;
  begin
    execute 'select id from app_private.inventory_items limit 1';
    raise exception 'authenticated direct inventory read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

do $$
begin
  if has_function_privilege('authenticated','app_private.preview_inventory_rows(uuid,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','app_private.commit_inventory_rows(uuid,integer,text)','EXECUTE')
     or has_function_privilege('anon','app_private.preview_inventory_rows(uuid,text,jsonb)','EXECUTE') then
    raise exception 'raw import rows leaked to Data API roles';
  end if;
end $$;

delete from auth.users where id in
  ('aaaaaaaa-1930-0001-0000-000000000001','aaaaaaaa-1930-0001-0000-000000000002');
