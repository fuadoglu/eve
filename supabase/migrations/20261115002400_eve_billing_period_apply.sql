-- EVE-026.3: apply a server-verified initial single-property order exactly once.
-- Provider verification is a prerequisite and remains owned by the Payriff task.
do $$
begin
  if not exists (select 1 from pg_roles where rolname='billing_executor') then
    create role billing_executor nologin nobypassrls noinherit;
  end if;
  if exists (select 1 from pg_roles where rolname='billing_executor'
      and (rolcanlogin or rolsuper or rolcreaterole or rolcreatedb or rolreplication
        or rolbypassrls or rolinherit))
     or exists (select 1 from pg_auth_members m
       where m.member='billing_executor'::regrole
          or (m.roleid='billing_executor'::regrole and m.member in (
            'anon'::regrole,'authenticated'::regrole,'service_role'::regrole,
            'authenticator'::regrole,'app_executor'::regrole))) then
    raise exception 'billing_executor role attributes or memberships are unsafe';
  end if;
end $$;

grant select on app_private.billing_orders, app_private.billing_order_lines,
  app_private.properties, app_private.subscription_periods,
  app_private.subscriptions to billing_executor;
grant update on app_private.billing_orders, app_private.billing_order_lines,
  app_private.subscriptions to billing_executor;
grant update (archived_at) on app_private.properties to billing_executor;
grant insert on app_private.subscription_periods to billing_executor;

create policy billing_orders_apply_read on app_private.billing_orders
  for select to billing_executor using (true);
create policy properties_billing_apply_read on app_private.properties
  for select to billing_executor using (true);
create policy properties_billing_apply_lock on app_private.properties
  for update to billing_executor using (true) with check (true);
create policy subscriptions_billing_apply_read on app_private.subscriptions
  for select to billing_executor using (true);
create policy billing_orders_apply_update on app_private.billing_orders
  for update to billing_executor using (true) with check (true);
create policy billing_order_lines_apply_read on app_private.billing_order_lines
  for select to billing_executor using (true);
create policy billing_order_lines_apply_update on app_private.billing_order_lines
  for update to billing_executor using (true) with check (true);
create policy subscription_periods_apply_read on app_private.subscription_periods
  for select to billing_executor using (true);
create policy subscription_periods_apply_insert on app_private.subscription_periods
  for insert to billing_executor with check (true);
create policy subscriptions_apply_update on app_private.subscriptions
  for update to billing_executor using (true) with check (true);

create function app_private.apply_verified_billing_order(p_order_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_order app_private.billing_orders%rowtype;
  v_line app_private.billing_order_lines%rowtype;
  v_property_owner uuid;
  v_subscription app_private.subscriptions%rowtype;
  v_previous_plan app_private.billing_plan;
  v_previous_end timestamptz;
  v_start_at timestamptz;
  v_start_local timestamp without time zone;
  v_anchor_day integer;
  v_anchor_month integer;
  v_anchor_time time without time zone;
  v_target_month date;
  v_end_date date;
  v_end_at timestamptz;
  v_line_count integer;
  v_total_minor bigint;
  v_existing_period app_private.subscription_periods%rowtype;
begin
  if p_order_id is null then
    raise exception using errcode='22023',message='billing_order_required';
  end if;

  -- The order row is the first lock in the documented order -> property sequence.
  select * into v_order from app_private.billing_orders o
    where o.id=p_order_id for update;
  if not found then raise exception using errcode='P0002',message='billing_order_not_found'; end if;

  select count(*),coalesce(sum(l.price_minor),0) into v_line_count,v_total_minor
    from app_private.billing_order_lines l where l.order_id=v_order.id;

  if v_order.state='entitlement_applied' then
    if v_line_count<>1 then
      raise exception using errcode='55000',message='billing_entitlement_replay_inconsistent';
    end if;
    select * into v_line from app_private.billing_order_lines l
      where l.order_id=v_order.id and l.owner_account_id=v_order.owner_account_id for update;
    select * into v_existing_period from app_private.subscription_periods p
      where p.order_line_id=v_line.id;
    if not found or v_line.entitlement_applied_at is null then
      raise exception using errcode='55000',message='billing_entitlement_replay_inconsistent';
    end if;
    return jsonb_build_object('replay',true,'order_id',v_order.id,
      'period',jsonb_build_object('id',v_existing_period.id,'order_line_id',v_line.id,
        'property_id',v_existing_period.property_id,'plan',v_existing_period.plan,
        'starts_at',v_existing_period.starts_at,'ends_at',v_existing_period.ends_at,
        'anchor_day',v_existing_period.anchor_day,'anchor_month',v_existing_period.anchor_month));
  end if;

  if v_order.state<>'verified_paid' or v_order.verified_paid_at is null
     or v_order.currency<>'AZN' or v_line_count<>1 or v_total_minor<>v_order.amount_minor then
    raise exception using errcode='55000',message='billing_order_not_applicable';
  end if;

  select * into v_line from app_private.billing_order_lines l
    where l.order_id=v_order.id and l.owner_account_id=v_order.owner_account_id for update;
  if not found or v_line.entitlement_applied_at is not null then
    raise exception using errcode='55000',message='billing_order_line_not_applicable';
  end if;

  select p.owner_account_id into v_property_owner from app_private.properties p
    where p.id=v_line.property_id for update;
  if not found or v_property_owner<>v_order.owner_account_id
     or v_line.owner_account_id<>v_order.owner_account_id then
    raise exception using errcode='42501',message='billing_property_owner_mismatch';
  end if;

  select * into v_subscription from app_private.subscriptions s
    where s.property_id=v_line.property_id and s.owner_account_id=v_order.owner_account_id
    for update;
  if not found then raise exception using errcode='P0002',message='billing_subscription_not_found'; end if;
  if v_subscription.anchor_timezone is distinct from 'Asia/Baku' then
    raise exception using errcode='22023',message='billing_anchor_timezone_invalid';
  end if;

  select p.plan,p.ends_at into v_previous_plan,v_previous_end
    from app_private.subscription_periods p
    where p.property_id=v_line.property_id and p.owner_account_id=v_order.owner_account_id
    order by p.ends_at desc,p.id desc limit 1;

  v_start_at := greatest(v_order.verified_paid_at,v_subscription.current_end,v_previous_end);
  v_start_local := v_start_at at time zone 'Asia/Baku';

  if (v_subscription.anchor_day is null and (v_subscription.anchor_month is not null or v_subscription.anchor_time is not null))
     or (v_subscription.anchor_day is not null and (v_subscription.anchor_month is null or v_subscription.anchor_time is null)) then
    raise exception using errcode='22023',message='billing_anchor_incomplete';
  end if;
  v_anchor_day := coalesce(v_subscription.anchor_day,extract(day from v_start_local)::integer);
  v_anchor_month := coalesce(v_subscription.anchor_month,extract(month from v_start_local)::integer);
  v_anchor_time := coalesce(v_subscription.anchor_time,v_start_local::time);
  if v_anchor_day not between 1 and 31 or v_anchor_month not between 1 and 12 then
    raise exception using errcode='22023',message='billing_anchor_invalid';
  end if;

  -- A plan switch becomes effective at the existing boundary. The month of
  -- that boundary is the new annual anchor; the original day and local time stay.
  if v_previous_plan is not null and v_previous_plan<>v_line.plan then
    v_anchor_month := extract(month from v_start_local)::integer;
  end if;

  if v_line.plan='monthly' then
    v_target_month := (date_trunc('month',v_start_local)+interval '1 month')::date;
  else
    v_target_month := make_date(extract(year from v_start_local)::integer+1,v_anchor_month,1);
  end if;
  v_end_date := v_target_month + least(v_anchor_day,
    extract(day from (v_target_month+interval '1 month'-interval '1 day'))::integer)-1;
  v_end_at := ((v_end_date+v_anchor_time) at time zone 'Asia/Baku');
  if v_end_at<=v_start_at then
    raise exception using errcode='22023',message='billing_period_range_invalid';
  end if;

  insert into app_private.subscription_periods(
    owner_account_id,property_id,order_line_id,plan,starts_at,ends_at,anchor_day,anchor_month
  ) values(
    v_order.owner_account_id,v_line.property_id,v_line.id,v_line.plan,
    v_start_at,v_end_at,v_anchor_day,v_anchor_month
  ) returning * into v_existing_period;

  update app_private.subscriptions set state='active',current_end=v_end_at,
    anchor_day=v_anchor_day,anchor_month=v_anchor_month,anchor_time=v_anchor_time,
    anchor_timezone='Asia/Baku',updated_at=statement_timestamp(),version=version+1
    where id=v_subscription.id;
  update app_private.billing_order_lines set entitlement_applied_at=statement_timestamp()
    where id=v_line.id;
  update app_private.billing_orders set state='entitlement_applied',
    updated_at=statement_timestamp(),version=version+1 where id=v_order.id;

  return jsonb_build_object('replay',false,'order_id',v_order.id,
    'period',jsonb_build_object('id',v_existing_period.id,'order_line_id',v_line.id,
      'property_id',v_existing_period.property_id,'plan',v_existing_period.plan,
      'starts_at',v_existing_period.starts_at,'ends_at',v_existing_period.ends_at,
      'anchor_day',v_existing_period.anchor_day,'anchor_month',v_existing_period.anchor_month));
end;
$$;
revoke all on function app_private.apply_verified_billing_order(uuid) from public,anon,authenticated,service_role;
grant execute on function app_private.apply_verified_billing_order(uuid) to app_executor;
grant usage on schema app_private to billing_executor;

grant usage,create on schema api to app_executor;
create function api.apply_verified_billing_order_for_server(p_order_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  return app_private.apply_verified_billing_order(p_order_id);
end;
$$;
revoke all on function api.apply_verified_billing_order_for_server(uuid) from public,anon,authenticated,service_role;
grant execute on function api.apply_verified_billing_order_for_server(uuid) to service_role;

grant app_executor to current_user with set true,inherit false;
grant usage,create on schema app_private to billing_executor;
do $$
declare
  temporary_membership boolean;
begin
  temporary_membership := not exists (
    select 1 from pg_auth_members
    where roleid='billing_executor'::regrole and member=current_user::regrole
  );
  if temporary_membership then
    execute format('grant billing_executor to %I with set true,inherit false',current_user);
  end if;
  execute 'alter function app_private.apply_verified_billing_order(uuid) owner to billing_executor';
  if temporary_membership then
    execute format('revoke billing_executor from %I',current_user);
  end if;
end $$;
alter function api.apply_verified_billing_order_for_server(uuid) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema app_private from billing_executor;
revoke create on schema api from app_executor;
