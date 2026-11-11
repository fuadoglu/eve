-- Enum-like varchar contracts and the canonical inventory unit default.
do $$
declare missing_count integer;
declare unit_default text;
begin
  select count(*) into missing_count
  from (values
    ('contacts','contacts_service_type_allowed'),
    ('inventory_items','inventory_items_unit_allowed'),
    ('inspection_room_answers','room_result'),
    ('media_assets','media_assets_mime_allowed'),
    ('support_requests','support_requests_category_allowed')
  ) as e(table_name,constraint_name)
  left join pg_class c on c.relname=e.table_name
    and c.relnamespace='app_private'::regnamespace
  left join pg_constraint k on k.conrelid=c.oid and k.conname=e.constraint_name
  where k.oid is null or not k.convalidated or k.contype <> 'c';
  if missing_count <> 0 then
    raise exception 'API enum DB constraints missing: %',missing_count;
  end if;
  select pg_get_expr(d.adbin,d.adrelid) into unit_default
  from pg_attrdef d join pg_attribute a
    on a.attrelid=d.adrelid and a.attnum=d.adnum
  where d.adrelid='app_private.inventory_items'::regclass
    and a.attname='unit';
  if coalesce(unit_default,'') not like '%piece%' then
    raise exception 'inventory unit default is not canonical piece: %',unit_default;
  end if;
end $$;

begin;
insert into app_private.contacts
  (id,owner_account_id,name,phone,service_type) values
  ('e1000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111','Synthetic worker',
   '+994501234567','cleaner');
insert into app_private.rooms(id,owner_account_id,property_id,name) values
  ('e2000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333333','Synthetic room');
insert into app_private.inventory_items
  (id,owner_account_id,property_id,room_id,name) values
  ('e3000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333333',
   'e2000000-0000-0000-0000-000000000001','Synthetic item');
insert into app_private.support_requests
  (id,user_id,category,message) values
  ('e4000000-0000-0000-0000-000000000001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','usage','Synthetic request');
do $$
begin
  if (select unit from app_private.inventory_items
      where id='e3000000-0000-0000-0000-000000000001') <> 'piece' then
    raise exception 'inventory default did not write piece';
  end if;
  begin
    update app_private.contacts set service_type='unknown'
      where id='e1000000-0000-0000-0000-000000000001';
    raise exception 'invalid contact service type accepted';
  exception when check_violation then null;
  end;
  begin
    update app_private.inventory_items set unit='ədəd'
      where id='e3000000-0000-0000-0000-000000000001';
    raise exception 'noncanonical inventory unit accepted';
  exception when check_violation then null;
  end;
  begin
    update app_private.media_assets set mime='text/html'
      where object_key='test/one.jpg';
    raise exception 'invalid media MIME accepted';
  exception when check_violation then null;
  end;
  begin
    update app_private.support_requests set category='unknown'
      where id='e4000000-0000-0000-0000-000000000001';
    raise exception 'invalid support category accepted';
  exception when check_violation then null;
  end;
end $$;
rollback;
