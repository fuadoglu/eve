-- EVE-027.2: synthetic normalized-verified event, inbox idempotency and atomic entitlement.
do $$
begin
  if has_function_privilege('anon','api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text)','EXECUTE')
     or has_function_privilege('authenticated','api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text)','EXECUTE')
     or not has_function_privilege('service_role','api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text)','EXECUTE')
     or has_function_privilege('service_role','app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text)','EXECUTE')
     or not has_function_privilege('app_executor','app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text)','EXECUTE')
     or not has_function_privilege('billing_executor','app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text)','EXECUTE') then
    raise exception 'verified event inbox RPC grant boundary is unsafe';
  end if;
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
        or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.reconcile_verified_billing_event_for_server(uuid,text,text,bigint,text)'::regprocedure)
     or (select p.proowner<>'billing_executor'::regrole or not p.prosecdef
        or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='app_private.reconcile_verified_billing_event(uuid,text,text,bigint,text)'::regprocedure) then
    raise exception 'verified event inbox RPC owner/security configuration is unsafe';
  end if;
end $$;

insert into auth.users(id) values ('a0272000-0000-4000-8000-000000000001') on conflict do nothing;
begin;
set local request.jwt.claim.sub='a0272000-0000-4000-8000-000000000001';
do $$
declare
  v_property record;
  v_order uuid := 'a0272000-0000-4000-8000-000000000011';
  v_line uuid := 'a0272000-0000-4000-8000-000000000021';
  v_bad_order uuid := 'a0272000-0000-4000-8000-000000000012';
  v_bad_line uuid := 'a0272000-0000-4000-8000-000000000022';
  v_expired_order uuid := 'a0272000-0000-4000-8000-000000000013';
  v_expired_line uuid := 'a0272000-0000-4000-8000-000000000023';
  v_result jsonb;
  v_replay jsonb;
  v_second_event jsonb;
  v_conflict boolean := false;
begin
  select * into v_property from api.create_property('Verified inbox smoke','Bakı','villa');
  insert into app_private.billing_orders(id,owner_account_id,currency,amount_minor,state,expires_at)
  values(v_order,v_property.owner_account_id,'AZN',999,'pending',statement_timestamp()+interval '1 day'),
    (v_bad_order,v_property.owner_account_id,'AZN',999,'pending',statement_timestamp()+interval '1 day'),
    (v_expired_order,v_property.owner_account_id,'AZN',999,'expired',statement_timestamp()-interval '1 hour');
  insert into app_private.billing_order_lines(id,owner_account_id,property_id,order_id,plan,price_minor)
  values(v_line,v_property.owner_account_id,v_property.id,v_order,'monthly',999),
    (v_bad_line,v_property.owner_account_id,v_property.id,v_bad_order,'monthly',999),
    (v_expired_line,v_property.owner_account_id,v_property.id,v_expired_order,'monthly',999);

  perform set_config('request.jwt.claim.role','service_role',true);
  v_result := api.reconcile_verified_billing_event_for_server(v_order,'normalized-event-001','normalized-tx-001',999,'AZN');
  if v_result->>'verification_state'<>'applied' or v_result->>'replay'<>'false'
     or v_result->>'entitlement_applied'<>'true' or v_result->>'entitlement_replay'<>'false'
     or (select state from app_private.billing_orders where id=v_order)<>'entitlement_applied'
     or (select provider_transaction_id from app_private.billing_orders where id=v_order)<>'normalized-tx-001'
     or (select verification_state from app_private.payment_events where id=(v_result->>'event_id')::uuid)<>'applied'
     or (select count(*) from app_private.subscription_periods where order_line_id=v_line)<>1 then
    raise exception 'verified paid event did not atomically persist one entitlement: %',v_result;
  end if;

  v_replay := api.reconcile_verified_billing_event_for_server(v_order,'normalized-event-001','normalized-tx-001',999,'AZN');
  if v_replay->>'event_id'<>v_result->>'event_id' or v_replay->>'replay'<>'true'
     or (select count(*) from app_private.payment_events where billing_order_id=v_order)<>1
     or (select count(*) from app_private.subscription_periods where order_line_id=v_line)<>1 then
    raise exception 'same normalized event replay created a duplicate event or entitlement: %',v_replay;
  end if;
  v_second_event := api.reconcile_verified_billing_event_for_server(v_order,'normalized-event-002','normalized-tx-001',999,'AZN');
  if v_second_event->>'verification_state'<>'applied' or v_second_event->>'entitlement_replay'<>'true'
     or (select count(*) from app_private.payment_events where billing_order_id=v_order)<>2
     or (select count(*) from app_private.subscription_periods where order_line_id=v_line)<>1 then
    raise exception 'out-of-order second event changed an already-applied entitlement: %',v_second_event;
  end if;

  begin
    perform api.reconcile_verified_billing_event_for_server(v_order,'normalized-event-001','normalized-tx-001',1000,'AZN');
  exception when unique_violation then v_conflict := true;
  end;
  if not v_conflict then raise exception 'same event key accepted a changed normalized payload'; end if;

  v_result := api.reconcile_verified_billing_event_for_server(v_bad_order,'normalized-event-bad-amount','normalized-tx-bad-amount',998,'AZN');
  if v_result->>'verification_state'<>'rejected' or v_result->>'rejection_code'<>'order_amount_currency_mismatch'
     or (select state from app_private.billing_orders where id=v_bad_order)<>'pending'
     or exists(select 1 from app_private.subscription_periods where order_line_id=v_bad_line) then
    raise exception 'amount mismatch was not rejected without entitlement: %',v_result;
  end if;
  v_result := api.reconcile_verified_billing_event_for_server(v_bad_order,'normalized-event-bad-currency','normalized-tx-bad-currency',999,'USD');
  if v_result->>'verification_state'<>'rejected' or v_result->>'rejection_code'<>'order_amount_currency_mismatch'
     or (select state from app_private.billing_orders where id=v_bad_order)<>'pending'
     or exists(select 1 from app_private.subscription_periods where order_line_id=v_bad_line) then
    raise exception 'currency mismatch was not rejected without entitlement: %',v_result;
  end if;
  v_result := api.reconcile_verified_billing_event_for_server(v_bad_order,'normalized-event-duplicate-transaction','normalized-tx-001',999,'AZN');
  if v_result->>'verification_state'<>'rejected' or v_result->>'rejection_code'<>'provider_transaction_conflict'
     or (select state from app_private.billing_orders where id=v_bad_order)<>'pending'
     or exists(select 1 from app_private.subscription_periods where order_line_id=v_bad_line) then
    raise exception 'provider transaction reused across orders was not rejected: %',v_result;
  end if;

  v_result := api.reconcile_verified_billing_event_for_server(v_expired_order,'normalized-event-expired','normalized-tx-expired',999,'AZN');
  if v_result->>'verification_state'<>'verified' or v_result->>'manual_review_required'<>'true'
     or v_result->>'entitlement_applied'<>'false'
     or (select state from app_private.billing_orders where id=v_expired_order)<>'expired'
     or exists(select 1 from app_private.subscription_periods where order_line_id=v_expired_line) then
    raise exception 'late verified event for a closed order did not require manual reconciliation: %',v_result;
  end if;
  v_replay := api.reconcile_verified_billing_event_for_server(v_expired_order,'normalized-event-expired','normalized-tx-expired',999,'AZN');
  if v_replay->>'event_id'<>v_result->>'event_id' or v_replay->>'replay'<>'true'
     or v_replay->>'manual_review_required'<>'true' then
    raise exception 'closed-order review replay changed or duplicated the verified event: %',v_replay;
  end if;
end $$;
rollback;
delete from auth.users where id='a0272000-0000-4000-8000-000000000001';

begin;
set local role authenticated;
set local request.jwt.claim.role='authenticated';
do $$
begin
  begin
    perform api.reconcile_verified_billing_event_for_server(
      'a0272000-0000-4000-8000-000000000011','untrusted-event-key','untrusted-tx',999,'AZN');
    raise exception 'authenticated caller invoked server-only verified event bridge';
  exception when insufficient_privilege then null;
  end;
  begin
    execute 'select * from app_private.payment_events';
    raise exception 'authenticated caller read the payment event inbox table';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
