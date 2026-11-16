-- EVE-006.2 catalog guard: all 56 private tables remain FORCE RLS.
-- Only the reviewed scoped RPC allowlists have executor grants; all other tables deny.
do $$
declare
  table_count integer;
  bad_count integer;
begin
  select count(*) into table_count
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='app_private' and c.relkind='r';
  if table_count <> 56 then
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
        'TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege('app_executor',c.oid,'DELETE') is distinct from (c.relname='realtor_accounts')
      or has_table_privilege('app_executor',c.oid,'UPDATE') is distinct from
        (c.relname in ('manager_invites','property_memberships','idempotency_keys','tasks','access_links','media_assets','link_session_rate_limits','reservations','reservation_placements','occupancy','realtor_accounts'))
      or has_table_privilege('app_executor',c.oid,'INSERT') is distinct from
        (c.relname in ('owner_accounts','properties','trial_claims','subscriptions','rooms','inventory_items','media_bindings','media_assets','manager_invites','invite_properties','property_memberships','manager_invite_accept_context','reservations','reservation_placements','occupancy','rent_entries','realtor_accounts','outbox','audit_events','idempotency_keys','task_transition_events','task_transition_media','link_session_rate_limits','tasks','reservation_attribution_transfers','inspection_days','inspection_events'))
      or has_table_privilege('app_executor',c.oid,'SELECT') is distinct from
        (c.relname in ('profiles','owner_accounts','properties','occupancy',
          'property_memberships','reservations','reservation_placements',
          'manual_blocks','contacts','contact_properties','rent_entries','subscriptions','rooms','inventory_items','media_assets','media_bindings','idempotency_keys',
          'manager_invites','invite_properties','tasks','access_links','inspection_submissions',
          'inspection_snapshot_rooms','inspection_room_answers','task_transition_events','task_transition_media',
          'expenses','expense_allocations','inspection_answers','inspection_events','inspection_days','guides','guide_versions','link_session_rate_limits','realtor_accounts','realtor_settlements','reservation_attribution_transfers')));
  if bad_count <> 0 then
    raise exception 'private RLS/grant allowlist mismatch: % tables',bad_count;
  end if;

  if not exists (select 1 from pg_roles where rolname='billing_executor'
       and not rolcanlogin and not rolsuper and not rolcreaterole and not rolcreatedb
       and not rolreplication and not rolbypassrls and not rolinherit)
     or exists (select 1 from pg_auth_members m
       where m.member='billing_executor'::regrole
          or (m.roleid='billing_executor'::regrole and m.member in (
            select oid from pg_roles where rolname in
              ('anon','authenticated','service_role','authenticator','app_executor'))))
     or has_table_privilege('billing_executor','app_private.properties','UPDATE')
     or has_table_privilege('billing_executor','app_private.properties','INSERT')
     or not has_column_privilege('billing_executor','app_private.properties','archived_at','UPDATE')
     or has_table_privilege('billing_executor','app_private.billing_orders','DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('billing_executor','app_private.billing_order_lines','DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('billing_executor','app_private.subscriptions','DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('billing_executor','app_private.subscription_periods','DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or has_table_privilege('billing_executor','app_private.properties','DELETE,TRUNCATE,REFERENCES,TRIGGER') then
    raise exception 'billing executor role boundary is unsafe';
  end if;
  if exists (select 1 from pg_class c
       where c.relnamespace='app_private'::regnamespace and c.relkind='r'
         and c.relname not in ('billing_orders','billing_order_lines','properties','subscriptions','subscription_periods')
         and (has_table_privilege('billing_executor',c.oid,'SELECT')
           or has_table_privilege('billing_executor',c.oid,'INSERT')
           or has_table_privilege('billing_executor',c.oid,'UPDATE')
           or has_table_privilege('billing_executor',c.oid,'DELETE')
           or has_table_privilege('billing_executor',c.oid,'TRUNCATE')
           or has_table_privilege('billing_executor',c.oid,'REFERENCES')
           or has_table_privilege('billing_executor',c.oid,'TRIGGER')))
     or (select count(*) from pg_class c
       join pg_namespace n on n.oid=c.relnamespace
       join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
       cross join lateral aclexplode(a.attacl) acl
       where n.nspname='app_private' and acl.grantee='billing_executor'::regrole::oid) <> 1
     or not exists (select 1 from pg_class c
       join pg_namespace n on n.oid=c.relnamespace
       join pg_attribute a on a.attrelid=c.oid and a.attname='archived_at'
       cross join lateral aclexplode(a.attacl) acl
       where n.nspname='app_private' and c.relname='properties'
         and acl.grantee='billing_executor'::regrole::oid and acl.privilege_type='UPDATE')
     or not has_table_privilege('billing_executor','app_private.billing_orders','SELECT')
     or not has_table_privilege('billing_executor','app_private.billing_orders','UPDATE')
     or has_table_privilege('billing_executor','app_private.billing_orders','INSERT')
     or not has_table_privilege('billing_executor','app_private.billing_order_lines','SELECT')
     or not has_table_privilege('billing_executor','app_private.billing_order_lines','UPDATE')
     or has_table_privilege('billing_executor','app_private.billing_order_lines','INSERT')
     or not has_table_privilege('billing_executor','app_private.properties','SELECT')
     or not has_table_privilege('billing_executor','app_private.subscriptions','SELECT')
     or not has_table_privilege('billing_executor','app_private.subscriptions','UPDATE')
     or has_table_privilege('billing_executor','app_private.subscriptions','INSERT')
     or not has_table_privilege('billing_executor','app_private.subscription_periods','SELECT')
     or not has_table_privilege('billing_executor','app_private.subscription_periods','INSERT')
     or has_table_privilege('billing_executor','app_private.subscription_periods','UPDATE')
     or has_table_privilege('app_executor','app_private.billing_orders','SELECT')
     or has_table_privilege('app_executor','app_private.billing_orders','UPDATE')
     or has_table_privilege('app_executor','app_private.billing_order_lines','SELECT')
     or has_table_privilege('app_executor','app_private.billing_order_lines','UPDATE')
     or has_table_privilege('app_executor','app_private.subscription_periods','SELECT')
     or has_table_privilege('app_executor','app_private.subscription_periods','INSERT') then
    raise exception 'billing executor table grants differ from the reviewed allowlist';
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
    ('properties','properties_matching_invite_read'),
    ('property_memberships','property_memberships_self_or_owner_read'),
    ('reservations','reservations_current_property_read'),
    ('reservation_placements','reservation_placements_current_read'),
    ('occupancy','occupancy_move_internal_read'),
    ('reservation_attribution_transfers','reservation_attribution_move_read'),
    ('realtor_accounts','realtor_accounts_current_reservation_read'),
    ('manual_blocks','manual_blocks_property_read'),
    ('contacts','contacts_linked_or_owner_read'),
    ('contacts','contacts_reservation_write_read'),
    ('contact_properties','contact_properties_assigned_read'),
    ('rent_entries','rent_entries_current_or_finance_read'),
    ('subscriptions','subscriptions_inventory_read'),
    ('subscriptions','subscriptions_media_upload_read'),
    ('subscriptions','subscriptions_reservation_write_read'),
    ('subscriptions','subscriptions_owner_invite_read'),
    ('subscriptions','subscriptions_matching_invite_read'),
    ('manager_invites','manager_invites_owner_read'),
    ('manager_invites','manager_invites_matching_email_read'),
    ('invite_properties','invite_properties_owner_read'),
    ('invite_properties','invite_properties_matching_email_read'),
    ('rooms','rooms_inventory_read'),
    ('inventory_items','inventory_items_inventory_read'),
    ('media_assets','media_assets_inventory_read'),
    ('media_assets','media_assets_upload_quota_read'),
    ('media_bindings','media_bindings_inventory_read'),
    ('idempotency_keys','idempotency_keys_reservation_read'),
    ('idempotency_keys','idempotency_keys_upload_read'),
    ('idempotency_keys','idempotency_keys_finalize_read'),
    ('tasks','tasks_transition_internal_read'),
    ('access_links','access_links_task_transition_internal_read'),
    ('subscriptions','subscriptions_task_transition_internal_read'),
    ('inspection_submissions','inspection_submissions_task_transition_internal_read'),
    ('inspection_snapshot_rooms','inspection_snapshot_rooms_task_transition_internal_read'),
    ('inspection_room_answers','inspection_room_answers_task_transition_internal_read'),
    ('media_assets','media_assets_task_transition_internal_read'),
    ('task_transition_events','task_transition_events_internal_read'),
    ('task_transition_media','task_transition_media_internal_read'),
    ('media_assets','media_assets_proxy_internal_read'),
    ('media_bindings','media_bindings_proxy_internal_read'),
    ('access_links','access_links_media_internal_read'),
    ('tasks','tasks_media_internal_read'),
    ('task_transition_events','task_transition_events_media_internal_read'),
    ('task_transition_media','task_transition_media_proxy_internal_read'),
    ('expenses','expenses_media_internal_read'),
    ('expense_allocations','expense_allocations_media_internal_read'),
    ('inspection_answers','inspection_answers_media_internal_read'),
    ('inspection_submissions','inspection_submissions_media_internal_read'),
    ('inspection_events','inspection_events_media_internal_read'),
    ('reservations','reservations_media_internal_read'),
    ('reservations','reservations_at10_read'),
    ('reservation_placements','reservation_placements_media_internal_read'),
    ('reservation_placements','placements_at10_read'),
    ('occupancy','occupancy_at10_read'),
    ('idempotency_keys','at10_idempotency_read'),
    ('tasks','at10_task_read'),
    ('task_transition_events','at10_task_event_read'),
    ('access_links','at10_access_link_read'),
    ('realtor_accounts','at10_realtor_read'),
    ('realtor_settlements','at10_settlement_read'),
    ('inspection_days','at10_inspection_day_read'),
    ('inspection_events','at10_inspection_event_read'),
    ('guides','guides_media_internal_read'),
    ('guide_versions','guide_versions_media_internal_read')
  ) as expected(table_name,policy_name)
  left join pg_class c on c.relname=expected.table_name
    and c.relnamespace='app_private'::regnamespace
  left join pg_policy p on p.polrelid=c.oid and p.polname=expected.policy_name
  where p.oid is null or p.polcmd <> 'r'
     or p.polroles <> array['app_executor'::regrole::oid];
  if bad_count <> 0 then
    raise exception 'expected executor SELECT policies missing or mis-scoped: %',bad_count;
  end if;
  if (select count(*) from pg_policy where polroles=array['billing_executor'::regrole::oid]) <> 10
     or not exists (select 1 from pg_policy where polrelid='app_private.billing_orders'::regclass
       and polname='billing_orders_apply_read' and polcmd='r' and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.billing_order_lines'::regclass
       and polname='billing_order_lines_apply_read' and polcmd='r' and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.properties'::regclass
       and polname='properties_billing_apply_read' and polcmd='r' and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.subscriptions'::regclass
       and polname='subscriptions_billing_apply_read' and polcmd='r' and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.subscription_periods'::regclass
       and polname='subscription_periods_apply_read' and polcmd='r' and polroles=array['billing_executor'::regrole::oid]) then
    raise exception 'billing executor read policies missing or mis-scoped';
  end if;
  select count(*) into table_count
  from pg_policy p join pg_class c on c.oid=p.polrelid
  where c.relnamespace='app_private'::regnamespace;
  if table_count <> 140 then
    raise exception 'unexpected private table policies: %',table_count;
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.link_session_rate_limits'::regclass
      and polname='link_session_rate_limits_internal' and polcmd='*'
      and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'link session rate limit policy missing or mis-scoped';
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.manager_invite_accept_context'::regclass
      and polname='manager_invite_accept_context_insert' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'manager invite accept context INSERT policy missing or mis-scoped';
  end if;
  if (select count(*) from pg_policy where polroles=array['app_executor'::regrole::oid]
      and polcmd='a' and polname in ('reservations_create','reservation_placements_create',
        'occupancy_reservation_create','rent_entries_reservation_create',
        'media_assets_upload_create','idempotency_keys_upload_create','tasks_move_insert','reservation_attribution_move_insert','idempotency_keys_move_create',
        'realtor_accounts_reservation_create','idempotency_keys_reservation_create',
        'outbox_reservation_create','audit_events_reservation_create','task_transition_events_internal_insert','task_transition_media_internal_insert','outbox_task_transition_create',
        'placements_at10_insert','occupancy_at10_insert','at10_idempotency_insert','at10_task_event_insert','at10_rent_insert',
        'at10_audit_insert','at10_outbox_insert','at10_inspection_day_insert','at10_inspection_event_insert')) <> 25
     or not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
       and polname='idempotency_keys_reservation_update' and polcmd='w'
       and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
       and polname='idempotency_keys_upload_update' and polcmd='w'
       and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
       and polname='idempotency_keys_finalize_update' and polcmd='w'
       and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
       and polname='idempotency_keys_move_update' and polcmd='w'
       and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.reservations'::regclass
       and polname='reservations_at10_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.reservation_placements'::regclass
       and polname='placements_at10_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.occupancy'::regclass
       and polname='occupancy_at10_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
       and polname='at10_idempotency_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.tasks'::regclass
       and polname='at10_task_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.access_links'::regclass
       and polname='at10_access_link_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.realtor_accounts'::regclass
       and polname='at10_realtor_update' and polcmd='w' and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'reservation write/idempotency policies missing or mis-scoped';
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.realtor_accounts'::regclass
      and polname='at10_realtor_delete' and polcmd='d' and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'reservation realtor delete policy missing or mis-scoped';
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.idempotency_keys'::regclass
      and polname='idempotency_keys_finalize_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'media finalize idempotency policy missing or mis-scoped';
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
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.manager_invites'::regclass
      and polname='manager_invites_owner_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.invite_properties'::regclass
      and polname='invite_properties_owner_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.property_memberships'::regclass
      and polname='property_memberships_invite_create' and polcmd='a'
      and polroles=array['app_executor'::regrole::oid]) then
    raise exception 'owner/inventory/invite scoped insert policies missing';
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.manager_invites'::regclass
      and polname='manager_invites_owner_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.manager_invites'::regclass
      and polname='manager_invites_matching_email_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.property_memberships'::regclass
      and polname='property_memberships_invite_reactivate' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.tasks'::regclass
      and polname='tasks_transition_internal_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.access_links'::regclass
      and polname='access_links_task_transition_internal_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.reservations'::regclass
      and polname='reservations_move_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.reservation_placements'::regclass
      and polname='reservation_placements_move_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.occupancy'::regclass
      and polname='occupancy_move_update' and polcmd='w'
      and polroles=array['app_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.billing_orders'::regclass
      and polname='billing_orders_apply_update' and polcmd='w'
      and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.billing_order_lines'::regclass
      and polname='billing_order_lines_apply_update' and polcmd='w'
      and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.subscriptions'::regclass
      and polname='subscriptions_apply_update' and polcmd='w'
      and polroles=array['billing_executor'::regrole::oid])
     or not exists (select 1 from pg_policy where polrelid='app_private.properties'::regclass
      and polname='properties_billing_apply_lock' and polcmd='w'
      and polroles=array['billing_executor'::regrole::oid]) then
    raise exception 'manager invite update policies missing';
  end if;
  if not exists (select 1 from pg_policy where polrelid='app_private.subscription_periods'::regclass
      and polname='subscription_periods_apply_insert' and polcmd='a'
      and polroles=array['billing_executor'::regrole::oid]) then
    raise exception 'billing executor period insert policy missing or mis-scoped';
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
