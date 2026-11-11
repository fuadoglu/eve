-- EVE-006.2 catalog guard: all 52 private tables remain FORCE RLS.
-- Only the nine reviewed read tables have executor SELECT; all others deny.
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
        'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege('app_executor',c.oid,'SELECT') is distinct from
        (c.relname in ('profiles','owner_accounts','properties',
          'property_memberships','reservations','reservation_placements',
          'manual_blocks','contacts','contact_properties')));
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

  -- There is one explicit read policy per selected foundation table.
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
    ('contact_properties','contact_properties_assigned_read')
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
  if table_count <> 9 then
    raise exception 'unexpected private table policies: %',table_count;
  end if;
end $$;
