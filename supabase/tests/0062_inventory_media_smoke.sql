-- D34 / EVE-019.1: classification and direct Storage denial in local SQL stub.
begin;
do $$
begin
  if (select count(*) from storage.buckets
      where id='eve-private-inventory' and not public) <> 1 then
    raise exception 'private inventory bucket was not provisioned';
  end if;
  if not exists (select 1 from pg_policy
      where polrelid='storage.objects'::regclass
        and polname='eve_inventory_media_direct_deny' and not polpermissive) then
    raise exception 'private inventory direct Storage deny policy missing';
  end if;
end $$;

insert into auth.users(id) values ('aaaaaaaa-1415-0001-0000-000000000001')
on conflict (id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id)
values ('aaaaaaaa-1415-0002-0000-000000000001','aaaaaaaa-1415-0001-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area)
values ('aaaaaaaa-1415-0003-0000-000000000001','aaaaaaaa-1415-0002-0000-000000000001','Media test','Bakı');
insert into app_private.media_assets(owner_account_id,property_id,classification,bucket,
  object_key,mime,size_bytes,state)
values ('aaaaaaaa-1415-0002-0000-000000000001','aaaaaaaa-1415-0003-0000-000000000001',
  'private_inventory','eve-private-inventory','test/inventory-1415.jpg','image/jpeg',1024,'validated');
insert into storage.objects(id,bucket_id,name)
values ('aaaaaaaa-1415-0004-0000-000000000001','eve-private-inventory','test/inventory-1415.jpg');

do $$ begin
  begin
    insert into app_private.media_assets(owner_account_id,property_id,classification,bucket,
      object_key,mime,size_bytes)
    values ('aaaaaaaa-1415-0002-0000-000000000001','aaaaaaaa-1415-0003-0000-000000000001',
      'private_inventory','eve-private-task','test/wrong-bucket.jpg','image/jpeg',1024);
    raise exception 'private inventory media accepted wrong bucket';
  exception when check_violation then null;
  end;
end $$;

savepoint inventory_media_authenticated;
set local role authenticated;
set local request.jwt.claim.sub = 'aaaaaaaa-1415-0001-0000-000000000001';
do $$ begin
  if exists(select 1 from storage.objects where bucket_id='eve-private-inventory') then
    raise exception 'authenticated direct inventory media read unexpectedly worked';
  end if;
  begin
    insert into storage.objects(id,bucket_id,name)
    values ('aaaaaaaa-1415-0005-0000-000000000001','eve-private-inventory','test/forged.jpg');
    raise exception 'authenticated direct inventory media upload unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback to savepoint inventory_media_authenticated;

rollback;
