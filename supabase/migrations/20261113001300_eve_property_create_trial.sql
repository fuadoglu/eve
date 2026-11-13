-- EVE-008.1: atomically create a property and claim the owner's first trial.
-- Actor identity comes only from the verified Data API JWT; owner IDs are never inputs.
grant insert on app_private.owner_accounts, app_private.properties,
  app_private.trial_claims, app_private.subscriptions to app_executor;

create policy owner_accounts_self_create on app_private.owner_accounts
  for insert to app_executor
  with check (owner_user_id = (select app_private.current_actor_id()));

create policy properties_owner_create on app_private.properties
  for insert to app_executor
  with check (app_private.is_owner(owner_account_id));

create policy trial_claims_owner_create on app_private.trial_claims
  for insert to app_executor
  with check (app_private.is_owner(owner_account_id));

create policy subscriptions_owner_create on app_private.subscriptions
  for insert to app_executor
  with check (app_private.is_owner(owner_account_id));

grant create on schema api to app_executor;
create function api.create_property(
  p_name text,
  p_area text,
  p_property_type text default 'apartment'
)
returns table (
  id uuid,
  owner_account_id uuid,
  name text,
  area text,
  property_type text,
  readiness text,
  subscription_state text,
  permission text,
  version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_owner uuid;
  v_property uuid;
  v_state app_private.subscription_state;
  v_started_at timestamptz := clock_timestamp();
  v_claim_inserted integer;
begin
  if v_actor is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_name is null or length(btrim(p_name)) = 0 or length(p_name) > 120
     or p_area is null or length(btrim(p_area)) = 0 or length(p_area) > 160 then
    raise exception using errcode = '22023', message = 'invalid_property_name_or_area';
  end if;
  if p_property_type is null or p_property_type not in ('apartment','house','villa','other') then
    raise exception using errcode = '22023', message = 'invalid_property_type';
  end if;

  -- Serialize first-property decisions without granting UPDATE on owner_accounts.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 0));

  insert into app_private.owner_accounts(owner_user_id)
    values (v_actor)
    on conflict (owner_user_id) do nothing;

  select a.id into strict v_owner
  from app_private.owner_accounts a
  where a.owner_user_id = v_actor;

  insert into app_private.properties(owner_account_id, name, area, property_type)
    values (v_owner, p_name, p_area, p_property_type::app_private.property_type)
    returning app_private.properties.id into v_property;

  begin
    insert into app_private.trial_claims(owner_account_id, property_id, started_at, ends_at)
      values (v_owner, v_property, v_started_at, v_started_at + interval '7 days');
    v_claim_inserted := 1;
  exception when unique_violation then
    v_claim_inserted := 0;
  end;
  v_state := case when v_claim_inserted = 1 then 'trialing'::app_private.subscription_state
    else 'draft'::app_private.subscription_state end;

  insert into app_private.subscriptions(owner_account_id, property_id, state, current_end)
    values (v_owner, v_property, v_state,
      case when v_state = 'trialing' then v_started_at + interval '7 days' else null end);

  return query
    select p.id, p.owner_account_id, p.name::text, p.area::text, p.property_type::text,
           p.readiness::text, v_state::text, 'owner'::text, p.version, p.created_at, p.updated_at
    from app_private.properties p
    where p.id = v_property;
end;
$$;
revoke all on function api.create_property(text,text,text) from public, anon, authenticated;
grant execute on function api.create_property(text,text,text) to authenticated;
grant app_executor to current_user with set true, inherit false;
alter function api.create_property(text,text,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
grant usage on schema api to authenticated;
