-- EVE-019.1: synthetic JWT/RLS/database smoke; not hosted Data API or production proof.
insert into auth.users(id) values
  ('aaaaaaaa-1919-0001-0000-000000000001'),
  ('aaaaaaaa-1919-0001-0000-000000000002')
on conflict (id) do nothing;

begin;
set local request.jwt.claim.sub = 'aaaaaaaa-1919-0001-0000-000000000001';
do $$
declare
  v_property uuid;
  v_draft uuid;
  v_room uuid;
  v_media uuid := 'aaaaaaaa-1919-0001-0000-000000000099';
  v_other_media uuid := 'aaaaaaaa-1919-0001-0000-000000000098';
  v_result jsonb;
  v_inventory jsonb;
begin
  select id into v_property from api.create_property('Inventar ev','Bakı');
  v_inventory := api.apply_inventory_template(v_property,'standard_apartment','append_non_duplicate');
  if jsonb_array_length(v_inventory->'rooms') <> 4
     or jsonb_array_length(v_inventory->'items') <> 11 then
    raise exception 'standard template fixture mismatch: %',v_inventory;
  end if;
  update app_private.inventory_items set quantity=9
    where property_id=v_property and name='Stəkan';
  v_inventory := api.apply_inventory_template(v_property,'standard_apartment','append_non_duplicate');
  if jsonb_array_length(v_inventory->'rooms') <> 4
     or jsonb_array_length(v_inventory->'items') <> 11
     or (select quantity from app_private.inventory_items
         where property_id=v_property and name='Stəkan') <> 9 then
    raise exception 'template reapply duplicated or overwrote inventory';
  end if;

  v_result := api.create_room(v_property,'Əlavə otaq');
  v_room := (v_result->>'id')::uuid;
  insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,
    object_key,mime,size_bytes,state)
  select v_media,p.owner_account_id,v_property,'private_inventory','eve-private-inventory',
    'test/inventory.jpg','image/jpeg',1024,'validated'
  from app_private.properties p where p.id=v_property;
  v_result := api.create_inventory_item(v_property,v_room,'Soyuducu',1,'piece','ok',
    null,null,null,null,null,null,null,array[v_media]);
  if v_result->>'name' <> 'Soyuducu' or v_result->>'condition' <> 'ok'
     or (v_result->>'room_id')::uuid <> v_room
     or v_result->'media_ids' <> jsonb_build_array(v_media) then
    raise exception 'created inventory item DTO mismatch: %',v_result;
  end if;
  v_inventory := api.get_inventory(v_property);
  if not exists(select 1 from jsonb_array_elements(v_inventory->'items') x
      where x->>'name'='Soyuducu' and x->'media_ids'=jsonb_build_array(v_media)) then
    raise exception 'bound inventory media was absent from read DTO';
  end if;
  begin
    perform api.create_inventory_item(v_property,v_room,'Media yoxlama',1,'piece','ok',
      null,null,null,null,null,null,null,array['aaaaaaaa-1919-0001-0000-000000000097'::uuid]);
    raise exception 'unbound media id accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.apply_inventory_template(v_property,'unknown','append_non_duplicate');
    raise exception 'unknown template accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_room(v_property,'   ');
    raise exception 'blank room name accepted';
  exception when invalid_parameter_value then null;
  end;

  select id into v_draft from api.create_property('Draft ev','Gəncə');
  insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,
    object_key,mime,size_bytes,state)
  select v_other_media,p.owner_account_id,v_draft,'private_inventory','eve-private-inventory',
    'test/other-property.jpg','image/jpeg',1024,'validated'
  from app_private.properties p where p.id=v_draft;
  begin
    perform api.create_inventory_item(v_property,v_room,'Başqa əmlak mediası',1,'piece','ok',
      null,null,null,null,null,null,null,array[v_other_media]);
    raise exception 'cross-property media id accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.create_room(v_draft,'Yazılmamalıdır');
    raise exception 'draft property accepted inventory write';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub','aaaaaaaa-1919-0001-0000-000000000002',true);
  begin
    perform api.get_inventory(v_property);
    raise exception 'cross-tenant inventory read accepted';
  exception when no_data_found then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-1919-0001-0000-000000000002';
do $$
begin
  begin
    execute 'select id from app_private.inventory_items limit 1';
    raise exception 'authenticated direct inventory read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

delete from auth.users where id in
  ('aaaaaaaa-1919-0001-0000-000000000001','aaaaaaaa-1919-0001-0000-000000000002');
