-- EVE-016.1 / AT14 component smoke. Run after the full migration chain on PostgreSQL 17.
begin;
set constraints all deferred;

do $$ begin
  if not exists(select 1 from pg_proc where oid='api.create_expense_proposal(jsonb,text)'::regprocedure
    and proowner='app_executor'::regrole and prosecdef and provolatile='v')
    or has_function_privilege('anon','api.create_expense_proposal(jsonb,text)','EXECUTE')
    or not has_function_privilege('authenticated','api.create_expense_proposal(jsonb,text)','EXECUTE')
    or has_table_privilege('authenticated','app_private.expenses','INSERT')
    or has_table_privilege('authenticated','app_private.expense_allocations','INSERT') then
    raise exception 'expense RPC privilege boundary mismatch';
  end if;
end $$;

insert into auth.users(id) values
 ('f9000000-0000-0000-0000-000000000081'),
 ('f9000000-0000-0000-0000-000000000082'),
 ('f9000000-0000-0000-0000-000000000083'),
 ('f9000000-0000-0000-0000-000000000084');
insert into auth.sessions(id,user_id,created_at) values
 ('f9100000-0000-0000-0000-000000000081','f9000000-0000-0000-0000-000000000081',now()-interval '1 hour'),
 ('f9100000-0000-0000-0000-000000000082','f9000000-0000-0000-0000-000000000082',now()-interval '1 hour'),
 ('f9100000-0000-0000-0000-000000000083','f9000000-0000-0000-0000-000000000083',now()-interval '1 hour'),
 ('f9100000-0000-0000-0000-000000000084','f9000000-0000-0000-0000-000000000084',now()-interval '1 hour');
insert into app_private.owner_accounts(id,owner_user_id) values
 ('f9200000-0000-0000-0000-000000000081','f9000000-0000-0000-0000-000000000081'),
 ('f9200000-0000-0000-0000-000000000082','f9000000-0000-0000-0000-000000000082');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('f9300000-0000-4000-8000-000000000081','f9200000-0000-0000-0000-000000000081','Expense A','Baku'),
 ('f9300000-0000-4000-8000-000000000082','f9200000-0000-0000-0000-000000000081','Expense B','Baku'),
 ('f9300000-0000-4000-8000-000000000083','f9200000-0000-0000-0000-000000000082','Other owner','Baku');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
 ('f9200000-0000-0000-0000-000000000081','f9300000-0000-4000-8000-000000000081','trialing',now()+interval '7 days'),
 ('f9200000-0000-0000-0000-000000000081','f9300000-0000-4000-8000-000000000082','trialing',now()+interval '7 days'),
 ('f9200000-0000-0000-0000-000000000082','f9300000-0000-4000-8000-000000000083','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('f9200000-0000-0000-0000-000000000081','f9300000-0000-4000-8000-000000000081','f9000000-0000-0000-0000-000000000083','full','f9000000-0000-0000-0000-000000000081'),
 ('f9200000-0000-0000-0000-000000000081','f9300000-0000-4000-8000-000000000081','f9000000-0000-0000-0000-000000000084','daily','f9000000-0000-0000-0000-000000000081');

set local role authenticated;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000081","session_id":"f9100000-0000-0000-0000-000000000081","iat":1800000000}';
do $$
declare v_result jsonb; v_failed boolean;
begin
  v_result := api.create_expense_proposal('{"category":"cleaning","amount_minor":1001,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":501},{"property_id":"f9300000-0000-4000-8000-000000000082","amount_minor":500}],"occurred_on":"2026-11-18"}', 'expense-smoke-key-0001');
  if v_result->>'approval'<>'approved' or v_result->>'payment_status'<>'unpaid'
    or (v_result->>'paid_minor')::integer<>0 or jsonb_array_length(v_result->'allocations')<>2 then
    raise exception 'owner expense did not remain unpaid with two allocations'; end if;
  perform set_config('eve.test.expense_id',v_result->>'id',true);
  if api.create_expense_proposal('{"category":"cleaning","amount_minor":1001,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":501},{"property_id":"f9300000-0000-4000-8000-000000000082","amount_minor":500}],"occurred_on":"2026-11-18"}', 'expense-smoke-key-0001')->>'id' is distinct from v_result->>'id' then
    raise exception 'same-key expense replay duplicated expense'; end if;
  v_failed:=false;
  begin
    perform api.create_expense_proposal('{"category":"cleaning","amount_minor":1002,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":501},{"property_id":"f9300000-0000-4000-8000-000000000082","amount_minor":500}],"occurred_on":"2026-11-18"}', 'expense-smoke-key-0002');
  exception when sqlstate '22023' then v_failed:=true; end;
  if not v_failed then raise exception 'allocation mismatch accepted'; end if;
  v_failed:=false;
  begin
    perform api.create_expense_proposal('{"category":"cleaning","amount_minor":1001,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":501},{"property_id":"f9300000-0000-4000-8000-000000000083","amount_minor":500}],"occurred_on":"2026-11-18"}', 'expense-smoke-key-0003');
  exception when insufficient_privilege then v_failed:=true; end;
  if not v_failed then raise exception 'cross-owner allocation accepted'; end if;
  v_failed:=false;
  begin
    perform api.create_expense_proposal('{"category":"cleaning","amount_minor":1,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":1}],"occurred_on":"2026-11-18","mark_paid":true}', 'expense-smoke-key-0004');
  exception when sqlstate '22023' then v_failed:=true; end;
  if not v_failed then raise exception 'proposed expense was paid'; end if;
end $$;
reset role;
do $$
declare v_other uuid := gen_random_uuid(); v_failed boolean := false; v_message text;
begin
  insert into app_private.expenses(id,owner_account_id,category,total_minor,approval,payment_status,
    expense_date,submitted_by,approved_by)
  values(v_other,'f9200000-0000-0000-0000-000000000081','cleaning',100,'approved','unpaid',
    date '2026-11-18','f9000000-0000-0000-0000-000000000081','f9000000-0000-0000-0000-000000000081');
  insert into app_private.expense_allocations(owner_account_id,property_id,expense_id,amount_minor)
  values('f9200000-0000-0000-0000-000000000081','f9300000-0000-4000-8000-000000000081',v_other,100);
  begin
    update app_private.expense_allocations set expense_id=v_other
      where expense_id=current_setting('eve.test.expense_id')::uuid
        and property_id='f9300000-0000-4000-8000-000000000082';
  exception when check_violation then
    get stacked diagnostics v_message = message_text;
    v_failed := v_message = 'expense_allocation_header_immutable';
  end;
  if not v_failed then raise exception 'allocation moved away from old expense'; end if;
end $$;
set local role app_executor;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000083","session_id":"f9100000-0000-0000-0000-000000000083","iat":1800000000}';
do $$ begin
  if app_private.can_read_expense_header(
      current_setting('eve.test.expense_id')::uuid,
      'f9200000-0000-0000-0000-000000000081') then
    raise exception 'cross-property expense header guard allowed partial-scope manager'; end if;
end $$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f9000000-0000-0000-0000-000000000084","session_id":"f9100000-0000-0000-0000-000000000084","iat":1800000000}';
do $$ declare v_result jsonb; begin
  v_result := api.create_expense_proposal('{"category":"repair","amount_minor":200,"allocations":[{"property_id":"f9300000-0000-4000-8000-000000000081","amount_minor":200}],"occurred_on":"2026-11-18"}', 'expense-smoke-key-0005');
  if v_result->>'approval'<>'proposed' or v_result->>'payment_status'<>'unpaid' then
    raise exception 'daily manager proposal was auto-approved or paid'; end if;
end $$;
set constraints all immediate;
rollback;
