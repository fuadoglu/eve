-- Local PostgreSQL structure/tenant smoke, not Supabase auth/RLS integration.
-- Requires empty DB with auth.users stub, anon/authenticated roles and migration.
do $$
declare
  owner_a uuid := gen_random_uuid();
  owner_b uuid := gen_random_uuid();
  manager_id uuid := gen_random_uuid();
  account_a uuid;
  account_b uuid;
  property_a uuid;
  block_a uuid;
  block_b uuid;
begin
  insert into auth.users(id) values (owner_a), (owner_b), (manager_id);
  insert into app_private.owner_accounts(owner_user_id) values (owner_a) returning id into account_a;
  insert into app_private.owner_accounts(owner_user_id) values (owner_b) returning id into account_b;
  insert into app_private.properties(owner_account_id,name,area)
    values (account_a,'A evi','Bakı') returning id into property_a;
  insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by)
    values (account_a,property_a,manager_id,'daily',owner_a);

  begin
    insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by)
      values (account_b,property_a,owner_b,'full',owner_b);
    raise exception 'cross-owner membership unexpectedly accepted';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into app_private.properties(owner_account_id,name,area,nightly_rate_minor)
      values (account_a,'X','Bakı',-1);
    raise exception 'negative rate unexpectedly accepted';
  exception when check_violation then null;
  end;

  begin
    insert into app_private.properties(owner_account_id,name,area,settings)
      values (account_a,'Y','Bakı','[]'::jsonb);
    raise exception 'non-object settings unexpectedly accepted';
  exception when check_violation then null;
  end;

  insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out)
    values (account_a,property_a,'2027-01-01','2027-01-04') returning id into block_a;
  insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out)
    values (account_a,property_a,'2027-01-03','2027-01-05') returning id into block_b;
  insert into app_private.occupancy(owner_account_id,property_id,manual_block_id,date_range)
    values (account_a,property_a,block_a,daterange('2027-01-01','2027-01-04','[)'));
  begin
    insert into app_private.occupancy(owner_account_id,property_id,manual_block_id,date_range)
      values (account_a,property_a,block_b,daterange('2027-01-03','2027-01-05','[)'));
    raise exception 'overlapping occupancy unexpectedly accepted';
  exception when exclusion_violation then null;
  end;

  begin
    insert into app_private.manual_blocks(owner_account_id,property_id,check_in,check_out)
      values (account_b,property_a,'2027-02-01','2027-02-02');
    raise exception 'cross-owner block unexpectedly accepted';
  exception when foreign_key_violation then null;
  end;

  if has_schema_privilege('authenticated','app_private','USAGE')
     or has_table_privilege('authenticated','app_private.properties','SELECT')
     or has_schema_privilege('anon','app_private','USAGE') then
    raise exception 'base schema or table leaked to client roles';
  end if;

  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='app_private' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity) <> 52 then
    raise exception 'all 52 dictionary tables must FORCE RLS';
  end if;
end $$;
