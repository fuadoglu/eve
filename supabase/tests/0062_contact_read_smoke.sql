-- Local read-only contact fixture. Not the full OpenAPI ContactPage or Data API.
do $$
begin
  if has_function_privilege('anon',
       'api.list_property_contact_summaries(uuid,uuid,integer)','EXECUTE')
     or has_table_privilege('authenticated','app_private.contacts','SELECT')
     or has_table_privilege('authenticated','app_private.contact_properties','SELECT')
     or not exists (
       select 1 from pg_proc p
       where p.oid='api.list_property_contact_summaries(uuid,uuid,integer)'::regprocedure
         and p.proowner='app_executor'::regrole and p.prosecdef
         and p.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception 'contact RPC grant/owner/search_path mismatch';
  end if;
  if pg_get_function_result('api.list_property_contact_summaries(uuid,uuid,integer)'::regprocedure)
      like '%property_ids%' then
    raise exception 'other property allocations leaked into contact result';
  end if;
end $$;

-- M's A1 membership was revoked by an earlier smoke; restore for this fixture.
update app_private.property_memberships set revoked_at=null
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
insert into app_private.contacts
  (id,owner_account_id,name,phone,service_type,private_note) values
 ('f1000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  'A shared','+994501234567','cleaner','A owner private note'),
 ('f2000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  'A2 only','+994501234567','repair','A2 owner private note'),
 ('f3000000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',
  'B1 only','+994501234567','realtor','B1 owner private note'),
 ('f4000000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',
  'B2 only','+994501234567','other','B2 owner private note');
insert into app_private.contacts
  (id,owner_account_id,name,phone,service_type,private_note,archived_at) values
 ('f5000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
  'A archived','+994501234567','other','Archived note',now());
insert into app_private.contact_properties
  (owner_account_id,property_id,contact_id) values
 ('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333',
  'f1000000-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111','55555555-5555-5555-5555-555555555555',
  'f1000000-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111','55555555-5555-5555-5555-555555555555',
  'f2000000-0000-0000-0000-000000000001'),
 ('22222222-2222-2222-2222-222222222222','44444444-4444-4444-4444-444444444444',
  'f3000000-0000-0000-0000-000000000001'),
 ('22222222-2222-2222-2222-222222222222','66666666-6666-6666-6666-666666666666',
  'f4000000-0000-0000-0000-000000000001'),
 ('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333',
  'f5000000-0000-0000-0000-000000000001');
do $$ begin
  begin
    insert into app_private.contact_properties
      (owner_account_id,property_id,contact_id) values
      ('22222222-2222-2222-2222-222222222222',
       '44444444-4444-4444-4444-444444444444',
       'f1000000-0000-0000-0000-000000000001');
    raise exception 'cross-owner contact/property link accepted';
  exception when foreign_key_violation then null;
  end;
end $$;

begin;
set local role authenticated;
set local request.jwt.claim.sub='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$
declare seen uuid[];
begin
  if (select count(*) from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333')) <> 1
     or (select private_note from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333') limit 1)
       is distinct from 'A owner private note' then
    raise exception 'owner A private note missing';
  end if;
  select coalesce(array_agg(contact_id order by contact_id),array[]::uuid[])
    into seen from api.list_property_contact_summaries(
      '55555555-5555-5555-5555-555555555555');
  if seen <> array['f1000000-0000-0000-0000-000000000001'::uuid,
                   'f2000000-0000-0000-0000-000000000001'::uuid]
     or exists (select 1 from api.list_property_contact_summaries(
       '44444444-4444-4444-4444-444444444444'))
     or (select count(*) from api.list_property_contact_summaries(
       '66666666-6666-6666-6666-666666666666')) <> 1
     or (select private_note from api.list_property_contact_summaries(
       '66666666-6666-6666-6666-666666666666') limit 1) is not null then
    raise exception 'owner A or daily-on-B2 scope mismatch: %',seen;
  end if;
  select coalesce(array_agg(contact_id order by contact_id),array[]::uuid[])
    into seen from api.list_property_contact_summaries(
      '55555555-5555-5555-5555-555555555555',null,1);
  if seen <> array['f1000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'contact first page mismatch: %',seen;
  end if;
  select coalesce(array_agg(contact_id order by contact_id),array[]::uuid[])
    into seen from api.list_property_contact_summaries(
      '55555555-5555-5555-5555-555555555555',
      'f1000000-0000-0000-0000-000000000001',1);
  if seen <> array['f2000000-0000-0000-0000-000000000001'::uuid] then
    raise exception 'contact second page mismatch: %',seen;
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$ begin
  if (select private_note from api.list_property_contact_summaries(
       '44444444-4444-4444-4444-444444444444') limit 1)
       is distinct from 'B1 owner private note'
     or exists (select 1 from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333')) then
    raise exception 'owner B contact scope mismatch';
  end if;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$ begin
  if (select count(*) from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333')) <> 1
     or (select private_note from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333') limit 1) is not null
     or exists (select 1 from api.list_property_contact_summaries(
       '55555555-5555-5555-5555-555555555555'))
     or (select private_note from api.list_property_contact_summaries(
       '44444444-4444-4444-4444-444444444444') limit 1)
       is distinct from 'B1 owner private note'
     or exists (select 1 from api.list_property_contact_summaries(
       '66666666-6666-6666-6666-666666666666')) then
    raise exception 'daily/full manager contact scope or note redaction mismatch';
  end if;
  begin
    execute 'select private_note from app_private.contacts limit 1';
    raise exception 'authenticated raw contact read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub='';
set local request.jwt.claims='';
do $$ begin
  if exists (select 1 from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333'))
     or exists (select 1 from api.list_property_contact_summaries(null))
     or exists (select 1 from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333',null,101)) then
    raise exception 'missing actor/invalid contact query returned data';
  end if;
end $$;
rollback;

update app_private.property_memberships set revoked_at=now()
where property_id='33333333-3333-3333-3333-333333333333'
  and user_id='cccccccc-cccc-cccc-cccc-cccccccccccc';
begin;
set local role authenticated;
set local request.jwt.claim.sub='cccccccc-cccc-cccc-cccc-cccccccccccc';
do $$ begin
  if exists (select 1 from api.list_property_contact_summaries(
       '33333333-3333-3333-3333-333333333333'))
     or (select count(*) from api.list_property_contact_summaries(
       '44444444-4444-4444-4444-444444444444')) <> 1 then
    raise exception 'A1 revoke failed or B1 contact access lost';
  end if;
end $$;
rollback;
