-- EVE-026.3: verified-order period application on synthetic PostgreSQL only.
do $$
begin
  if has_function_privilege('anon','api.apply_verified_billing_order_for_server(uuid)','EXECUTE')
     or has_function_privilege('authenticated','api.apply_verified_billing_order_for_server(uuid)','EXECUTE')
     or not has_function_privilege('service_role','api.apply_verified_billing_order_for_server(uuid)','EXECUTE')
     or has_function_privilege('authenticated','app_private.apply_verified_billing_order(uuid)','EXECUTE')
     or not has_function_privilege('app_executor','app_private.apply_verified_billing_order(uuid)','EXECUTE')
     or not has_function_privilege('billing_executor','app_private.apply_verified_billing_order(uuid)','EXECUTE') then
    raise exception 'billing period apply RPC grant boundary is unsafe';
  end if;
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
        or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.apply_verified_billing_order_for_server(uuid)'::regprocedure)
     or (select p.proowner<>'billing_executor'::regrole or not p.prosecdef
        or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='app_private.apply_verified_billing_order(uuid)'::regprocedure) then
    raise exception 'billing period apply RPC owner/security configuration is unsafe';
  end if;
end $$;

insert into auth.users(id) values ('a0240000-0000-4000-8000-000000000001') on conflict do nothing;
begin;
set local request.jwt.claim.sub='a0240000-0000-4000-8000-000000000001';
do $$
declare
  p record;
  result jsonb;
  replay jsonb;
  sub app_private.subscriptions%rowtype;
  p_monthly record;
  monthly_result jsonb;
  monthly_order uuid := 'a0240000-0000-4000-8000-000000000015';
  monthly_line uuid := 'a0240000-0000-4000-8000-000000000025';
  next_month_order uuid := 'a0240000-0000-4000-8000-000000000016';
  next_month_line uuid := 'a0240000-0000-4000-8000-000000000026';
  multi_order uuid := 'a0240000-0000-4000-8000-000000000017';
  multi_line_one uuid := 'a0240000-0000-4000-8000-000000000027';
  multi_line_two uuid := 'a0240000-0000-4000-8000-000000000028';
  line_id uuid := 'a0240000-0000-4000-8000-000000000021';
  order_id uuid := 'a0240000-0000-4000-8000-000000000011';
begin
  select * into p from api.create_property('Billing integration','Bakı','villa');
  update app_private.subscriptions set current_end='2024-02-28 20:00:00.123456+00',state='trialing'
    where property_id=p.id;
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values(order_id,p.owner_account_id,'AZN',9999,'verified_paid','2024-02-01 12:00:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values(line_id,p.owner_account_id,p.id,order_id,'yearly',9999);

  perform set_config('request.jwt.claim.role','service_role',true);
  result := api.apply_verified_billing_order_for_server(order_id);
  if result->>'replay'<>'false'
     or (result#>>'{period,starts_at}')::timestamptz<>'2024-02-28 20:00:00.123456+00'::timestamptz
     or (result#>>'{period,ends_at}')::timestamptz<>'2025-02-27 20:00:00.123456+00'::timestamptz
     or result#>>'{period,anchor_day}'<>'29' or result#>>'{period,anchor_month}'<>'2' then
    raise exception 'trial purchase or leap-year application mismatch: %',result;
  end if;
  replay := api.apply_verified_billing_order_for_server(order_id);
  if replay->>'replay'<>'true' or replay#>>'{period,id}'<>result#>>'{period,id}'
     or (select count(*) from app_private.subscription_periods where order_line_id=line_id)<>1 then
    raise exception 'duplicate application created a second period: %',replay;
  end if;
  select * into sub from app_private.subscriptions where property_id=p.id;
  if sub.state<>'active' or sub.current_end<>'2025-02-27 20:00:00.123456+00'::timestamptz
     or sub.anchor_day<>29 or sub.anchor_month<>2 or sub.anchor_time<>'00:00:00.123456'::time
     or sub.anchor_timezone<>'Asia/Baku'
     or (select state from app_private.billing_orders where id=order_id)<>'entitlement_applied'
     or (select entitlement_applied_at from app_private.billing_order_lines where id=line_id) is null then
    raise exception 'subscription/order/line state was not applied atomically: %',row_to_json(sub);
  end if;

  -- An early renewal starts after the saved paid boundary and retains Feb-29.
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values('a0240000-0000-4000-8000-000000000012',p.owner_account_id,'AZN',9999,'verified_paid','2024-11-15 09:30:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values('a0240000-0000-4000-8000-000000000022',p.owner_account_id,p.id,
    'a0240000-0000-4000-8000-000000000012','yearly',9999);
  result := api.apply_verified_billing_order_for_server('a0240000-0000-4000-8000-000000000012');
  if (result#>>'{period,starts_at}')::timestamptz<>'2025-02-27 20:00:00.123456+00'::timestamptz
     or (result#>>'{period,ends_at}')::timestamptz<>'2026-02-27 20:00:00.123456+00'::timestamptz then
    raise exception 'early annual renewal mismatch: %',result;
  end if;

  -- Annual-to-monthly switch applies at the annual boundary, preserving day/time.
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values('a0240000-0000-4000-8000-000000000013',p.owner_account_id,'AZN',999,'verified_paid','2025-12-01 00:00:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values('a0240000-0000-4000-8000-000000000023',p.owner_account_id,p.id,
    'a0240000-0000-4000-8000-000000000013','monthly',999);
  result := api.apply_verified_billing_order_for_server('a0240000-0000-4000-8000-000000000013');
  if (result#>>'{period,starts_at}')::timestamptz<>'2026-02-27 20:00:00.123456+00'::timestamptz
     or (result#>>'{period,ends_at}')::timestamptz<>'2026-03-28 20:00:00.123456+00'::timestamptz
     or result#>>'{period,anchor_day}'<>'29' or result#>>'{period,anchor_month}'<>'2' then
    raise exception 'queued monthly plan switch mismatch: %',result;
  end if;

  -- Database-backed Jan-31 -> Feb clamp -> March restoration.
  select * into p_monthly from api.create_property('Monthly anchor','Bakı','villa');
  update app_private.subscriptions set state='active',current_end='2025-01-30 20:00:00+00',
    anchor_day=31,anchor_month=1,anchor_time='00:00:00',anchor_timezone='Asia/Baku'
    where property_id=p_monthly.id;
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values('a0240000-0000-4000-8000-000000000030',p_monthly.owner_account_id,'AZN',999,'entitlement_applied','2024-12-01 00:00:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor,entitlement_applied_at)
  values('a0240000-0000-4000-8000-000000000040',p_monthly.owner_account_id,p_monthly.id,
    'a0240000-0000-4000-8000-000000000030','monthly',999,statement_timestamp());
  insert into app_private.subscription_periods(owner_account_id,property_id,order_line_id,plan,
    starts_at,ends_at,anchor_day,anchor_month)
  values(p_monthly.owner_account_id,p_monthly.id,'a0240000-0000-4000-8000-000000000040','monthly',
    '2024-12-30 20:00:00+00','2025-01-30 20:00:00+00',31,1);
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values(monthly_order,p_monthly.owner_account_id,'AZN',999,'verified_paid','2025-01-01 00:00:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values(monthly_line,p_monthly.owner_account_id,p_monthly.id,monthly_order,'monthly',999);
  monthly_result := api.apply_verified_billing_order_for_server(monthly_order);
  if (monthly_result#>>'{period,starts_at}')::timestamptz<>'2025-01-30 20:00:00+00'::timestamptz
     or (monthly_result#>>'{period,ends_at}')::timestamptz<>'2025-02-27 20:00:00+00'::timestamptz
     or monthly_result#>>'{period,anchor_day}'<>'31' then
    raise exception 'Jan-31 to February clamp mismatch: %',monthly_result;
  end if;
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values(next_month_order,p_monthly.owner_account_id,'AZN',999,'verified_paid','2025-02-01 00:00:00+00');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values(next_month_line,p_monthly.owner_account_id,p_monthly.id,next_month_order,'monthly',999);
  monthly_result := api.apply_verified_billing_order_for_server(next_month_order);
  if (monthly_result#>>'{period,starts_at}')::timestamptz<>'2025-02-27 20:00:00+00'::timestamptz
     or (monthly_result#>>'{period,ends_at}')::timestamptz<>'2025-03-30 20:00:00+00'::timestamptz
     or monthly_result#>>'{period,anchor_day}'<>'31' then
    raise exception 'February clamp did not restore day 31 in March: %',monthly_result;
  end if;

  -- Initial checkout is still single-property; reject multi-line atomically.
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,verified_paid_at)
  values(multi_order,p.owner_account_id,'AZN',1998,'verified_paid',statement_timestamp());
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values(multi_line_one,p.owner_account_id,p.id,multi_order,'monthly',999),
    (multi_line_two,p_monthly.owner_account_id,p_monthly.id,multi_order,'monthly',999);
  begin
    perform api.apply_verified_billing_order_for_server(multi_order);
    raise exception 'multi-property checkout exceeded the initial product scope';
  exception when sqlstate '55000' then null;
  end;
  if exists(select 1 from app_private.subscription_periods where order_line_id in(multi_line_one,multi_line_two))
     or (select state from app_private.billing_orders where id=multi_order)<>'verified_paid' then
    raise exception 'rejected multi-property order left partial writes';
  end if;

  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state)
  values('a0240000-0000-4000-8000-000000000014',p.owner_account_id,'AZN',999,'created');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values('a0240000-0000-4000-8000-000000000024',p.owner_account_id,p.id,
    'a0240000-0000-4000-8000-000000000014','monthly',999);
  begin
    perform api.apply_verified_billing_order_for_server('a0240000-0000-4000-8000-000000000014');
    raise exception 'unverified order was applied';
  exception when sqlstate '55000' then null;
  end;
  update app_private.billing_orders set state='verified_paid',verified_paid_at=statement_timestamp(),amount_minor=1000
    where id='a0240000-0000-4000-8000-000000000014';
  begin
    perform api.apply_verified_billing_order_for_server('a0240000-0000-4000-8000-000000000014');
    raise exception 'mismatched total was applied';
  exception when sqlstate '55000' then null;
  end;
  if (select state from app_private.billing_orders where id='a0240000-0000-4000-8000-000000000014')<>'verified_paid'
     or (select entitlement_applied_at from app_private.billing_order_lines where id='a0240000-0000-4000-8000-000000000024') is not null
     or exists(select 1 from app_private.subscription_periods where order_line_id='a0240000-0000-4000-8000-000000000024') then
    raise exception 'failed order application left partial writes';
  end if;
end $$;
rollback;

delete from auth.users where id='a0240000-0000-4000-8000-000000000001';

begin;
set local role authenticated;
do $$
begin
  begin
    perform api.apply_verified_billing_order_for_server('a0240000-0000-4000-8000-000000000011');
    raise exception 'authenticated caller invoked server-only billing bridge';
  exception when insufficient_privilege then null;
  end;
  begin
    execute 'select * from app_private.subscription_periods';
    raise exception 'authenticated caller read base billing periods';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
