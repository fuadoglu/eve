-- EVE-006.2 catalog guard: all 52 private tables remain FORCE RLS.
-- Only the reviewed read allowlist has executor SELECT; all other tables deny.
do $$
declare
  table_count integer;
  bad_count integer;
begin
  select count(*) into table_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='app_private' and c.relkind='r';
  if table_count <> 52 then
    raise exception 'private table inventory changed: %',table_count;
  end if;

  select count(*) into bad_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='app_private' and c.relkind='r'
    and (not c.relrowsecurity or not c.relforcerowsecurity
      or c.relowner='app_executor'::regrole
      or has_table_privilege('anon',c.oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege('authenticated',c.oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege('app_executor',c.oid,
        'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege('app_executor',c.oid,'INSERT') is distinct from
        (c.relname in ('owner_accounts','properties','trial_claims','subscriptions','rooms','inventory_items','media_bindings'))
      or has_table_privilege('app_executor',c.oid,'SELECT') is distinct from
        (c.relname in ('profiles','owner_accounts','properties',
          'property_memberships','reservations','reservation_placements',
          'manual_blocks','contacts','contact_properties','rent_entries','subscriptions','rooms','inventory_items','media_assets','media_bindings')));
  if bad_count <> 0 then
    raise exception 'private RLS/grant allowlist mismatch: % tables',bad_count;
  end if;

  select count(*) into bad_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='app_private' and c.relkind in ('v','m','f');
  if bad_count <> 0 then
    raise exception 'unreviewed private view or foreign table: %',bad_count;
  end if;

  if has_schema_privilege('anon','app_private','USAGE')
     or has_schema_privilege('authenticated','app_private','USAGE') then
    raise exception 'client role can access private schema';
  end if;

  -- Read policies are explicitly allowlisted by table and role.
  select count(*) into bad_count
  from (values
    ('profiles','profiles_self_read'),
    ('owner_accounts','owner_accounts_self_read'),
    ('properties','properties_scoped_read'),
    ('property_memberships','property_memberships_self_or_owner_read'),
    ('reservations','reservations_current_property_read'),
    ('reservation_placements','reservation_placements_current_read'),
    ('manual_blocks','manual_blocks_property_read'),
    ('contacts','contacts_linked_or_owner_read'),
    ('contact_properties','contact_properties_assigned_read'),
    ('rent_entries','rent_entries_current_or_finance_read'),
    ('subscriptions','subscriptions_inventory_read'),
    ('rooms','rooms_inventory_read'),
    ('inventory_items','inventory_items_inventory_read'),
    ('media_assets','media_assets_inventory_read'),
    ('media_bindings','media_bindings_inventory_read')
  ) as expected(table_name,policy_name)
  left join pg_class c on c.relname=expected.table_name
    and c.relnamespace='app_private'::regnamespace
  left join pg_policy p on p.polrelid=c.oid and p.polname=expected.policy_name
  where p.oid is null or p.polcmd <> 'r'
     or p.polroles <> array['app_executor'::regrole::oid];
  if bad_count <> 0 then
    raise exception 'expected executor SELECT policies missing or mis-scoped: %',bad_count;
  end if;
  select count(*) into table_count
  from pg_policy p join pg_class c on c.oid=p.polrelid
  where c.relnamespace='app_private'::regnamespace;
  if table_count <> 25 then
    raise exception 'unexpected private table policies: %',table_count;
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.owner_accounts'::regclass
      and polname='owner_accounts_self_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.properties'::regclass
      and polname='properties_owner_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.trial_claims'::regclass
      and polname='trial_claims_owner_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.subscriptions'::regclass
      and polname='subscriptions_owner_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.rooms'::regclass
      and polname='rooms_inventory_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.inventory_items'::regclass
      and polname='inventory_items_inventory_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.media_bindings'::regclass
      and polname='media_bindings_inventory_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'owner/inventory scoped insert policies missing';
  end if;
  if not exists (
    select 1 from pg_policy p
    where p.polrelid='app_private.profiles'::regclass
      and p.polname='profiles_session_reader_self'
      and p.polcmd='r'
      and p.polroles=array['app_session_reader'::regrole::oid]
  ) then
    raise exception 'session reader profile policy missing or mis-scoped';
  end if;
  if not exists (
    select 1 from pg_policy p
    where p.polrelid='app_private.profiles'::regclass
      and p.polname='profiles_self_session_insert'
      and p.polcmd='a'
      and p.polroles=array['app_executor'::regrole::oid]
  ) or not exists (
    select 1 from pg_policy p
    where p.polrelid='app_private.profiles'::regclass
      and p.polname='profiles_self_session_update'
      and p.polcmd='w'
      and p.polroles=array['app_executor'::regrole::oid]
  ) then
    raise exception 'session executor profile write policies missing or mis-scoped';
  end if;
end $$;
