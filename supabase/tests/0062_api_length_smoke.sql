-- Catalog proof for the 17 API-bound varchar limits narrowed after migration 001.
do $$
declare mismatch_count integer;
begin
  select count(*) into mismatch_count
  from (values
    ('profiles','display_name',100), ('profiles','phone',16),
    ('manager_invites','normalized_email',254), ('contacts','phone',16),
    ('reservations','guest_name',150), ('reservations','guest_phone',16),
    ('reservations','private_note',2000), ('recurring_expenses','note',160),
    ('tasks','title',160), ('tasks','description',2000),
    ('inventory_items','model',150), ('inventory_items','serial_number',150),
    ('inspection_events','handover_key',150),
    ('inspection_room_answers','reason',500),
    ('inspection_submissions','claimed_name',100),
    ('guide_versions','title',160), ('push_subscriptions','auth_key',128)
  ) as v(table_name,column_name,max_length)
  left join pg_namespace n on n.nspname='app_private'
  left join pg_class c on c.relnamespace=n.oid and c.relname=v.table_name
  left join pg_attribute a on a.attrelid=c.oid and a.attname=v.column_name
    and not a.attisdropped
  where a.atttypid is distinct from 'varchar'::regtype
     or a.atttypmod is distinct from v.max_length+4;
  if mismatch_count <> 0 then
    raise exception 'API-bound DB length mismatch: % columns',mismatch_count;
  end if;
end $$;

-- The reservation read fixture supplies a synthetic row; no real guest data.
begin;
update app_private.reservations
  set guest_name=repeat('x',150), guest_phone='+'||repeat('1',15)
  where id='40000000-0000-0000-0000-000000000001';
do $$
begin
  if not exists (select 1 from app_private.reservations
      where id='40000000-0000-0000-0000-000000000001'
        and char_length(guest_name)=150 and char_length(guest_phone)=16) then
    raise exception 'maximal API-aligned reservation values rejected';
  end if;
  begin
    update app_private.reservations set guest_name=repeat('x',151)
      where id='40000000-0000-0000-0000-000000000001';
    raise exception '151-character guest name accepted';
  exception when string_data_right_truncation then null;
  end;
  begin
    update app_private.reservations set guest_phone='+'||repeat('1',16)
      where id='40000000-0000-0000-0000-000000000001';
    raise exception '17-character guest phone accepted';
  exception when string_data_right_truncation then null;
  end;
end $$;
rollback;
