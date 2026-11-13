-- EVE-019.1: property-scoped room/item writes and the standard apartment template.
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
                              'inventory.read','inventory.manage') then false
    when app_private.is_owner(p_owner_account_id) then true
    else exists (
      select 1 from app_private.property_memberships m
      where m.property_id=p_property_id
        and m.owner_account_id=p_owner_account_id
        and m.user_id=(select app_private.current_actor_id())
        and m.revoked_at is null
        and (p_capability <> 'finance.read' or m.permission='full')
    )
  end;
$$;
revoke all on function app_private.has_property_capability(uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function app_private.has_property_capability(uuid,uuid,text) to app_executor;

grant select on app_private.subscriptions, app_private.rooms, app_private.inventory_items to app_executor;
grant insert on app_private.rooms, app_private.inventory_items to app_executor;
grant select on app_private.media_assets, app_private.media_bindings to app_executor;
grant insert on app_private.media_bindings to app_executor;

create policy subscriptions_inventory_read on app_private.subscriptions
  for select to app_executor
  using (app_private.has_property_capability(property_id,owner_account_id,'inventory.read'));
create policy rooms_inventory_read on app_private.rooms
  for select to app_executor
  using (app_private.has_property_capability(property_id,owner_account_id,'inventory.read'));
create policy rooms_inventory_create on app_private.rooms
  for insert to app_executor
  with check (app_private.has_property_capability(property_id,owner_account_id,'inventory.manage'));
create policy inventory_items_inventory_read on app_private.inventory_items
  for select to app_executor
  using (app_private.has_property_capability(property_id,owner_account_id,'inventory.read'));
create policy inventory_items_inventory_create on app_private.inventory_items
  for insert to app_executor
  with check (app_private.has_property_capability(property_id,owner_account_id,'inventory.manage'));
create policy media_assets_inventory_read on app_private.media_assets
  for select to app_executor
  using (app_private.has_property_capability(property_id,owner_account_id,'inventory.manage')
    and classification='private_inventory' and state='validated' and deleted_at is null);
create policy media_bindings_inventory_read on app_private.media_bindings
  for select to app_executor
  using (inventory_item_id is not null
    and app_private.has_property_capability(property_id,owner_account_id,'inventory.read'));
create policy media_bindings_inventory_create on app_private.media_bindings
  for insert to app_executor
  with check (inventory_item_id is not null
    and app_private.has_property_capability(property_id,owner_account_id,'inventory.manage')
    and exists (select 1 from app_private.media_assets a
      where a.id=media_bindings.media_asset_id and a.property_id=media_bindings.property_id
        and a.owner_account_id=media_bindings.owner_account_id and a.classification='private_inventory'
        and a.state='validated' and a.deleted_at is null));

create function app_private.inventory_write_owner(p_property_id uuid)
returns uuid
language plpgsql stable security invoker set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_owner uuid;
begin
  if v_actor is null then
    raise exception using errcode='28000', message='authentication_required';
  end if;
  select p.owner_account_id into v_owner
  from app_private.properties p
  where p.id=p_property_id
    and app_private.has_property_capability(p.id,p.owner_account_id,'inventory.manage');
  if v_owner is null then
    raise exception using errcode='P0002', message='property_not_found';
  end if;
  if not exists (
    select 1 from app_private.subscriptions s
    where s.property_id=p_property_id and s.owner_account_id=v_owner
      and s.state in ('trialing','active') and s.current_end > statement_timestamp()
  ) then
    raise exception using errcode='42501', message='active_entitlement_required';
  end if;
  return v_owner;
end;
$$;
revoke all on function app_private.inventory_write_owner(uuid) from public, anon, authenticated;
grant execute on function app_private.inventory_write_owner(uuid) to app_executor;

create function api.get_inventory(p_property_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_owner uuid; v_rooms jsonb; v_items jsonb;
begin
  select p.owner_account_id into v_owner
  from app_private.properties p
  where p.id=p_property_id
    and app_private.has_property_capability(p.id,p.owner_account_id,'inventory.read');
  if v_owner is null then
    raise exception using errcode='P0002', message='property_not_found';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'property_id',r.property_id,'name',r.name,'position',r.position,
    'version',r.version,'created_at',r.created_at,'updated_at',r.updated_at
  ) order by r.position,r.id),'[]'::jsonb) into v_rooms
  from app_private.rooms r
  where r.property_id=p_property_id and r.owner_account_id=v_owner and r.archived_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',i.id,'property_id',i.property_id,'room_id',i.room_id,'name',i.name,
      'quantity',i.quantity,'unit',i.unit,'condition',i.state::text,
      'minimum_stock',i.min_stock,'purchase_minor',i.purchase_minor,
      'purchased_on',i.purchased_on,'warranty_until',i.warranty_until,
      'model',i.model,'serial_number',i.serial_number,
      'media_ids',coalesce((select jsonb_agg(b.media_asset_id order by b.created_at,b.id)
        from app_private.media_bindings b join app_private.media_assets a
          on a.id=b.media_asset_id and a.property_id=b.property_id
            and a.owner_account_id=b.owner_account_id
        where b.inventory_item_id=i.id and b.property_id=i.property_id
          and b.owner_account_id=i.owner_account_id and a.classification='private_inventory'
          and a.state='validated' and a.deleted_at is null),'[]'::jsonb),
      'version',i.version,'created_at',i.created_at,'updated_at',i.updated_at
    ) || case when i.note is null then '{}'::jsonb else jsonb_build_object('note',i.note) end
    order by r.position,r.id,i.name,i.id
  ),'[]'::jsonb) into v_items
  from app_private.inventory_items i
  join app_private.rooms r on r.id=i.room_id and r.property_id=i.property_id
    and r.owner_account_id=i.owner_account_id and r.archived_at is null
  where i.property_id=p_property_id and i.owner_account_id=v_owner and i.archived_at is null;

  return jsonb_build_object('property_id',p_property_id,'rooms',v_rooms,'items',v_items);
end;
$$;

create function api.create_room(p_property_id uuid,p_name text,p_position integer default 0)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_owner uuid; v_room app_private.rooms%rowtype;
begin
  if p_name is null or length(btrim(p_name))=0 or length(p_name)>100
     or p_position is null or p_position<0 or p_position>1000000 then
    raise exception using errcode='22023', message='invalid_room';
  end if;
  v_owner := app_private.inventory_write_owner(p_property_id);
  insert into app_private.rooms(owner_account_id,property_id,name,position)
    values(v_owner,p_property_id,p_name,p_position) returning * into v_room;
  return jsonb_build_object('id',v_room.id,'property_id',v_room.property_id,
    'name',v_room.name,'position',v_room.position,'version',v_room.version,
    'created_at',v_room.created_at,'updated_at',v_room.updated_at);
end;
$$;

create function api.create_inventory_item(
  p_property_id uuid,p_room_id uuid,p_name text,p_quantity numeric,
  p_unit text default 'piece',p_condition text default 'ok',p_minimum_stock numeric default null,
  p_purchase_minor bigint default null,p_purchased_on date default null,
  p_warranty_until date default null,p_model text default null,
  p_serial_number text default null,p_note text default null,
  p_media_ids uuid[] default null
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_owner uuid; v_item app_private.inventory_items%rowtype; v_media_inserted integer;
begin
  if p_name is null or length(btrim(p_name))=0 or length(p_name)>160
     or p_quantity is null or p_quantity<0 or p_quantity>1000000
     or p_quantity<>round(p_quantity,3)
     or p_unit is null or p_unit not in ('piece','set','liter','kg','pack')
     or p_condition is null or p_condition not in ('ok','needs_repair','damaged','missing')
     or (p_minimum_stock is not null and (p_minimum_stock<0 or p_minimum_stock>1000000
         or p_minimum_stock<>round(p_minimum_stock,3)))
     or (p_purchase_minor is not null and (p_purchase_minor<0 or p_purchase_minor>9007199254740991))
     or (p_model is not null and length(p_model)>150)
     or (p_serial_number is not null and length(p_serial_number)>150)
     or (p_note is not null and length(p_note)>1000)
     or (p_media_ids is not null and cardinality(p_media_ids)>10)
     or (p_media_ids is not null and cardinality(p_media_ids) <> cardinality(
          array(select distinct x from unnest(p_media_ids) x where x is not null)))
     or (p_media_ids is not null and array_position(p_media_ids,null) is not null) then
    raise exception using errcode='22023', message='invalid_inventory_item';
  end if;
  v_owner := app_private.inventory_write_owner(p_property_id);
  if not exists(select 1 from app_private.rooms r where r.id=p_room_id
      and r.property_id=p_property_id and r.owner_account_id=v_owner and r.archived_at is null) then
    raise exception using errcode='P0002', message='room_not_found';
  end if;
  insert into app_private.inventory_items(owner_account_id,property_id,room_id,name,
      quantity,unit,state,min_stock,purchase_minor,purchased_on,warranty_until,
      model,serial_number,note)
    values(v_owner,p_property_id,p_room_id,p_name,p_quantity,p_unit,
      p_condition::app_private.inventory_state,p_minimum_stock,p_purchase_minor,
      p_purchased_on,p_warranty_until,p_model,p_serial_number,p_note)
    returning * into v_item;
  if coalesce(cardinality(p_media_ids),0)>0 then
    insert into app_private.media_bindings(owner_account_id,property_id,media_asset_id,inventory_item_id)
    select v_owner,p_property_id,m.id,v_item.id
    from unnest(p_media_ids) with ordinality input(media_id,ordinality)
    join app_private.media_assets m on m.id=input.media_id
      and m.owner_account_id=v_owner and m.property_id=p_property_id
      and m.classification='private_inventory' and m.state='validated' and m.deleted_at is null
    order by input.ordinality;
    get diagnostics v_media_inserted = row_count;
    if v_media_inserted <> cardinality(p_media_ids) then
      raise exception using errcode='22023', message='invalid_inventory_media';
    end if;
  end if;
  return jsonb_build_object('id',v_item.id,'property_id',v_item.property_id,
    'room_id',v_item.room_id,'name',v_item.name,'quantity',v_item.quantity,
    'unit',v_item.unit,'condition',v_item.state::text,'minimum_stock',v_item.min_stock,
    'purchase_minor',v_item.purchase_minor,'purchased_on',v_item.purchased_on,
    'warranty_until',v_item.warranty_until,'model',v_item.model,
    'serial_number',v_item.serial_number,'media_ids',coalesce((
      select jsonb_agg(b.media_asset_id order by b.created_at,b.id)
      from app_private.media_bindings b join app_private.media_assets a
        on a.id=b.media_asset_id and a.property_id=b.property_id
          and a.owner_account_id=b.owner_account_id
      where b.inventory_item_id=v_item.id and a.classification='private_inventory'
        and a.state='validated' and a.deleted_at is null),'[]'::jsonb),
    'version',v_item.version,'created_at',v_item.created_at,'updated_at',v_item.updated_at)
    || case when v_item.note is null then '{}'::jsonb else jsonb_build_object('note',v_item.note) end;
end;
$$;

create function api.apply_inventory_template(
  p_property_id uuid,p_template_key text,p_strategy text
)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_owner uuid;
  v_room_id uuid;
  v_room_name text;
  v_pos integer;
  r record;
  i record;
begin
  if p_template_key is distinct from 'standard_apartment'
     or p_strategy is distinct from 'append_non_duplicate' then
    raise exception using errcode='22023', message='unsupported_inventory_template';
  end if;
  v_owner := app_private.inventory_write_owner(p_property_id);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('inventory-template:'||p_property_id::text,0));

  for r in select x.room_name,x.items from jsonb_to_recordset(
    '[{"room_name":"Qonaq otağı","items":[{"name":"Televizor","quantity":1,"unit":"piece"},{"name":"Pult","quantity":1,"unit":"piece"},{"name":"Divan","quantity":1,"unit":"piece"}]},
      {"room_name":"Mətbəx","items":[{"name":"Stəkan","quantity":6,"unit":"piece"},{"name":"Boşqab","quantity":6,"unit":"piece"},{"name":"Çaydan","quantity":1,"unit":"piece"}]},
      {"room_name":"Yataq otağı","items":[{"name":"Yastıq","quantity":4,"unit":"piece"},{"name":"Yorğan","quantity":2,"unit":"piece"},{"name":"Yataq dəsti","quantity":2,"unit":"set"}]},
      {"room_name":"Hamam","items":[{"name":"Fen","quantity":1,"unit":"piece"},{"name":"Dəsmal","quantity":4,"unit":"piece"}]}]'::jsonb
  ) as x(room_name text,items jsonb) loop
    v_room_name := r.room_name;
    select x.id into v_room_id from app_private.rooms x
    where x.property_id=p_property_id and x.owner_account_id=v_owner
      and x.archived_at is null and lower(btrim(x.name))=lower(btrim(v_room_name))
    order by x.id limit 1;
    if v_room_id is null then
      select coalesce(max(x.position),-1)+1 into v_pos
      from app_private.rooms x where x.property_id=p_property_id
        and x.owner_account_id=v_owner and x.archived_at is null;
      insert into app_private.rooms(owner_account_id,property_id,name,position)
        values(v_owner,p_property_id,v_room_name,v_pos) returning id into v_room_id;
    end if;
    for i in select x.name,x.quantity,x.unit from jsonb_to_recordset(r.items)
      as x(name text,quantity numeric,unit text) loop
      if not exists(select 1 from app_private.inventory_items x
          where x.property_id=p_property_id and x.owner_account_id=v_owner
            and x.room_id=v_room_id and x.archived_at is null
            and lower(btrim(x.name))=lower(btrim(i.name))) then
        insert into app_private.inventory_items(owner_account_id,property_id,room_id,
          name,quantity,unit,state)
        values(v_owner,p_property_id,v_room_id,i.name,i.quantity,i.unit,
          'ok'::app_private.inventory_state);
      end if;
    end loop;
    v_room_id := null;
  end loop;

  return api.get_inventory(p_property_id);
end;
$$;

-- Each RPC has a fixed owner/search_path and an explicit authenticated grant.
revoke all on function api.get_inventory(uuid) from public,anon,authenticated;
revoke all on function api.create_room(uuid,text,integer) from public,anon,authenticated;
revoke all on function api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[])
  from public,anon,authenticated;
revoke all on function api.apply_inventory_template(uuid,text,text) from public,anon,authenticated;
grant execute on function api.get_inventory(uuid) to authenticated;
grant execute on function api.get_inventory(uuid) to app_executor;
grant execute on function api.create_room(uuid,text,integer) to authenticated;
grant execute on function api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[])
  to authenticated;
grant execute on function api.apply_inventory_template(uuid,text,text) to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.get_inventory(uuid) owner to app_executor;
alter function api.create_room(uuid,text,integer) owner to app_executor;
alter function api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[]) owner to app_executor;
alter function api.apply_inventory_template(uuid,text,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant usage on schema api to authenticated;
