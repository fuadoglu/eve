-- Local PostgreSQL Storage stub smoke, not a Supabase Storage API/signed URL test.
-- Harness must create storage.buckets/storage.objects with RLS and permissive
-- anon/authenticated test policy BEFORE migration 003 is applied.
do $$
begin
  if not exists (
    select 1 from pg_policy p
    where p.polrelid='storage.objects'::regclass
      and p.polname='eve_media_direct_client_deny' and not p.polpermissive
  ) then raise exception 'restrictive Storage policy missing'; end if;
  if (
    select count(*) from storage.buckets b
    where b.id in (
      'eve-public-property', 'eve-public-guide', 'eve-private-guest',
      'eve-private-receipt', 'eve-private-inspection', 'eve-private-task'
    ) and not b.public
  ) <> 6 then raise exception 'all six Eve buckets must be provisioned private'; end if;
end $$;

insert into auth.users(id) values ('77777777-7777-7777-7777-777777777777');
insert into app_private.owner_accounts(id,owner_user_id)
  values ('88888888-8888-8888-8888-888888888888','77777777-7777-7777-7777-777777777777');
insert into app_private.properties(id,owner_account_id,name,area)
  values ('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888','Storage test','Bakı');
insert into app_private.media_assets(
  owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes
) values (
  '88888888-8888-8888-8888-888888888888',
  '99999999-9999-9999-9999-999999999999',
  'private_inspection','eve-private-inspection','test/one.jpg','image/jpeg',1024
);
do $$ begin
  begin
    insert into app_private.media_assets(
      owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes
    ) values (
      '88888888-8888-8888-8888-888888888888',
      '99999999-9999-9999-9999-999999999999',
      'private_receipt','eve-public-property','test/two.jpg','image/jpeg',1024
    );
    raise exception 'cross-class bucket mapping unexpectedly accepted';
  exception when check_violation then null;
  end;
end $$;

insert into storage.objects(id,bucket_id,name) values
 ('aaaaaaaa-7777-7777-7777-777777777777','eve-private-inspection','test/one.jpg'),
 ('bbbbbbbb-7777-7777-7777-777777777777','unrelated-bucket','other.jpg');

begin;
set local role authenticated;
do $$ begin
  if (select count(*) from storage.objects where bucket_id='eve-private-inspection') <> 0
    or (select count(*) from storage.objects where bucket_id='unrelated-bucket') <> 1 then
    raise exception 'authenticated Storage visibility mismatch';
  end if;
  begin
    insert into storage.objects(id,bucket_id,name)
      values ('cccccccc-7777-7777-7777-777777777777','eve-private-task','task.jpg');
    raise exception 'authenticated direct upload unexpectedly accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role anon;
do $$ begin
  if (select count(*) from storage.objects where bucket_id='eve-private-inspection') <> 0 then
    raise exception 'anon private object visible';
  end if;
  begin
    insert into storage.objects(id,bucket_id,name)
      values ('dddddddd-7777-7777-7777-777777777777','eve-public-property','public.jpg');
    raise exception 'anon direct upload unexpectedly accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
