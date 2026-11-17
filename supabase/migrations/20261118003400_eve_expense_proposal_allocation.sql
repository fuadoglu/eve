-- EVE-016.1: atomic expense proposal and scoped allocation foundation.
-- The API role has no direct access to these private tables.
grant select, insert on app_private.expenses, app_private.expense_allocations to app_executor;
grant select on app_private.subscriptions, app_private.contacts,
  app_private.contact_properties, app_private.tasks to app_executor;

-- Earlier media proxy policies were permissive USING (true). With expense SELECT
-- granted for this command, they would OR-open whole headers across properties.
drop policy expenses_media_internal_read on app_private.expenses;
drop policy expense_allocations_media_internal_read on app_private.expense_allocations;

-- This helper sees the complete allocation set, including rows hidden from the caller by RLS.
create function app_private.can_read_expense_header(p_expense_id uuid,p_owner_account_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app_private.is_owner(p_owner_account_id) or (
    exists(select 1 from app_private.expense_allocations a where a.expense_id=p_expense_id and a.owner_account_id=p_owner_account_id)
    and not exists(select 1 from app_private.expense_allocations a
      where a.expense_id=p_expense_id and a.owner_account_id=p_owner_account_id
        and not app_private.has_property_capability(a.property_id,a.owner_account_id,'finance.read'))
  );
$$;
revoke all on function app_private.can_read_expense_header(uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.can_read_expense_header(uuid,uuid) to app_executor;
create policy expenses_executor_select on app_private.expenses for select to app_executor
  using (app_private.can_read_expense_header(id,owner_account_id)
    or (submitted_by=app_private.current_actor_id() and approval='proposed'));
create policy expenses_executor_insert on app_private.expenses for insert to app_executor
  with check (submitted_by=app_private.current_actor_id() and payment_status='unpaid'
    and ((approval='proposed' and approved_by is null)
      or (approval='approved' and approved_by=app_private.current_actor_id())));
create policy expense_allocations_executor_select on app_private.expense_allocations for select to app_executor
  using (app_private.has_property_capability(property_id,owner_account_id,'property.read'));
create policy expense_allocations_executor_insert on app_private.expense_allocations for insert to app_executor
  with check (app_private.has_property_capability(property_id,owner_account_id,'property.read'));
create policy idempotency_keys_expense_read on app_private.idempotency_keys for select to app_executor
  using (actor_scope=app_private.current_actor_id()::text||':createExpense');
create policy idempotency_keys_expense_insert on app_private.idempotency_keys for insert to app_executor
  with check (actor_scope=app_private.current_actor_id()::text||':createExpense');
create policy idempotency_keys_expense_update on app_private.idempotency_keys for update to app_executor
  using (actor_scope=app_private.current_actor_id()::text||':createExpense')
  with check (actor_scope=app_private.current_actor_id()::text||':createExpense');

-- Check the whole allocation set at commit, including direct writes by privileged roles.
create function app_private.check_expense_allocation_total() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_expense_id uuid;
  v_total bigint;
  v_allocated numeric;
begin
  if tg_table_name='expenses' then
    v_expense_id := new.id;
  elsif tg_op='DELETE' then
    v_expense_id := old.expense_id;
  else
    v_expense_id := new.expense_id;
  end if;
  select e.total_minor into v_total from app_private.expenses e where e.id=v_expense_id;
  if not found then return null; end if;
  select coalesce(sum(a.amount_minor),0) into v_allocated
  from app_private.expense_allocations a where a.expense_id=v_expense_id;
  if v_allocated<>v_total then
    raise exception using errcode='23514',message='expense_allocation_total_mismatch';
  end if;
  return null;
end;
$$;
revoke all on function app_private.check_expense_allocation_total() from public,anon,authenticated;
create constraint trigger expense_total_on_header after insert or update of total_minor
  on app_private.expenses deferrable initially deferred for each row
  execute function app_private.check_expense_allocation_total();
create constraint trigger expense_total_on_allocation after insert or update or delete
  on app_private.expense_allocations deferrable initially deferred for each row
  execute function app_private.check_expense_allocation_total();

-- An allocation can change its amount/property in a future edit, but moving it
-- to another header would skip the deferred sum check for the old header.
create function app_private.prevent_expense_allocation_move() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.expense_id is distinct from old.expense_id
    or new.owner_account_id is distinct from old.owner_account_id then
    raise exception using errcode='23514',message='expense_allocation_header_immutable';
  end if;
  return new;
end;
$$;
revoke all on function app_private.prevent_expense_allocation_move() from public,anon,authenticated;
create trigger expense_allocation_header_immutable before update
  on app_private.expense_allocations for each row
  execute function app_private.prevent_expense_allocation_move();

-- Receipt-media authorization needs only the expense/property allocation binding,
-- never the header's total. Keep the existing function owner and direct grants.
grant create on schema app_private to app_executor;
grant app_executor to current_user with set true, inherit false;
set role app_executor;
create or replace function app_private.media_actor_can_read(p_media_id uuid)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_media app_private.media_assets%rowtype;
begin
  select * into v_media from app_private.media_assets a
  where a.id=p_media_id and a.state='validated' and a.deleted_at is null;
  if not found or (select app_private.current_actor_id()) is null then return false; end if;

  if v_media.classification='private_receipt' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'finance.read')
      and exists (select 1 from app_private.media_bindings b
        join app_private.expense_allocations al on al.expense_id=b.expense_id
          and al.owner_account_id=b.owner_account_id and al.property_id=b.property_id
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id and b.expense_id is not null);
  elsif v_media.classification='private_inventory' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'inventory.read')
      and exists (select 1 from app_private.media_bindings b
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id and b.inventory_item_id is not null);
  elsif v_media.classification='private_task' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'property.read')
      and (exists (select 1 from app_private.media_bindings b
          where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
            and b.owner_account_id=v_media.owner_account_id and b.task_id is not null)
        or exists (select 1 from app_private.task_transition_media tm
          where tm.media_asset_id=v_media.id and tm.property_id=v_media.property_id
            and tm.owner_account_id=v_media.owner_account_id));
  elsif v_media.classification='private_inspection' then
    return app_private.has_property_capability(v_media.property_id,v_media.owner_account_id,'property.read')
      and exists (select 1 from app_private.media_bindings b
        join app_private.inspection_answers a on a.id=b.inspection_answer_id
          and a.property_id=b.property_id and a.owner_account_id=b.owner_account_id
        where b.media_asset_id=v_media.id and b.property_id=v_media.property_id
          and b.owner_account_id=v_media.owner_account_id);
  end if;
  -- private_guest is bearer-link only; public classifications use a different safe projection.
  return false;
end;
$$;
reset role;
revoke app_executor from current_user;
revoke create on schema app_private from app_executor;

create function api.create_expense_proposal(p_input jsonb,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor_id();
  v_owner uuid;
  v_property uuid;
  v_amount bigint;
  v_sum numeric := 0;
  v_count integer := 0;
  v_allocation jsonb;
  v_category app_private.expense_category;
  v_expense app_private.expenses%rowtype;
  v_allocations jsonb;
  v_contact uuid;
  v_task uuid;
  v_date date;
  v_due date;
  v_now timestamptz := statement_timestamp();
  v_key_scope text;
  v_request_hash text;
  v_prior app_private.idempotency_keys%rowtype;
  v_replay boolean := false;
  v_approve boolean := true;
  v_id uuid;
begin
  if not api.is_my_session_active() or v_actor is null then
    raise exception using errcode='28000',message='active_session_required'; end if;
  if p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$'
    or p_input is null or jsonb_typeof(p_input) is distinct from 'object'
    or p_input - array['category','amount_minor','allocations','occurred_on','due_on','contact_id','task_id','note','receipt_media_ids','mark_paid'] <> '{}'::jsonb
    or jsonb_typeof(p_input->'category') is distinct from 'string'
    or p_input->>'category' not in ('utilities','building_service','cleaning','repair','purchase','consumables','other')
    or jsonb_typeof(p_input->'amount_minor') is distinct from 'number'
    or (p_input->>'amount_minor') !~ '^[1-9][0-9]*$'
    or (p_input->>'amount_minor')::numeric>9007199254740991
    or jsonb_typeof(p_input->'allocations') is distinct from 'array'
    or jsonb_array_length(p_input->'allocations') not between 1 and 100
    or jsonb_typeof(p_input->'occurred_on') is distinct from 'string'
    or (p_input ? 'mark_paid' and jsonb_typeof(p_input->'mark_paid') is distinct from 'boolean')
    or coalesce((p_input->>'mark_paid')::boolean,false)
    or (p_input ? 'receipt_media_ids' and p_input->'receipt_media_ids'<>'[]'::jsonb)
    or (p_input ? 'note' and (jsonb_typeof(p_input->'note') is distinct from 'string' or length(p_input->>'note')>2000))
    or (p_input ? 'due_on' and jsonb_typeof(p_input->'due_on') is distinct from 'string')
    or (p_input ? 'contact_id' and (jsonb_typeof(p_input->'contact_id') is distinct from 'string' or (p_input->>'contact_id') !~ '^[0-9a-fA-F-]{36}$'))
    or (p_input ? 'task_id' and (jsonb_typeof(p_input->'task_id') is distinct from 'string' or (p_input->>'task_id') !~ '^[0-9a-fA-F-]{36}$')) then
    raise exception using errcode='22023',message='invalid_expense_proposal_input'; end if;
  v_category := (p_input->>'category')::app_private.expense_category;
  v_amount := (p_input->>'amount_minor')::bigint;
  begin
    v_date := (p_input->>'occurred_on')::date;
    v_due := (p_input->>'due_on')::date;
    v_contact := (p_input->>'contact_id')::uuid;
    v_task := (p_input->>'task_id')::uuid;
  exception when others then raise exception using errcode='22023',message='invalid_expense_proposal_date_or_id'; end;
  if to_char(v_date,'YYYY-MM-DD') is distinct from p_input->>'occurred_on'
    or (v_due is not null and to_char(v_due,'YYYY-MM-DD') is distinct from p_input->>'due_on') then
    raise exception using errcode='22023',message='invalid_expense_proposal_date'; end if;

  for v_allocation in select value from jsonb_array_elements(p_input->'allocations') loop
    if jsonb_typeof(v_allocation) is distinct from 'object'
      or v_allocation - array['property_id','amount_minor'] <> '{}'::jsonb
      or jsonb_typeof(v_allocation->'property_id') is distinct from 'string'
      or (v_allocation->>'property_id') !~ '^[0-9a-fA-F-]{36}$'
      or jsonb_typeof(v_allocation->'amount_minor') is distinct from 'number'
      or (v_allocation->>'amount_minor') !~ '^[1-9][0-9]*$'
      or (v_allocation->>'amount_minor')::numeric>9007199254740991 then
      raise exception using errcode='22023',message='invalid_expense_allocation'; end if;
    v_property := (v_allocation->>'property_id')::uuid;
    if v_count=0 then
      select p.owner_account_id into v_owner from app_private.properties p where p.id=v_property;
      if v_owner is null then raise exception using errcode='P0002',message='property_not_found'; end if;
    end if;
    if not exists(select 1 from app_private.properties p where p.id=v_property and p.owner_account_id=v_owner)
      or not app_private.has_property_capability(v_property,v_owner,'property.read') then
      raise exception using errcode='42501',message='expense_allocation_scope_required'; end if;
    if not exists(select 1 from app_private.subscriptions s where s.property_id=v_property
      and s.owner_account_id=v_owner and s.state in ('trialing','active') and s.current_end>v_now) then
      raise exception using errcode='42501',message='active_entitlement_required'; end if;
    v_approve := v_approve and (app_private.is_owner(v_owner) or exists (
      select 1 from app_private.property_memberships m where m.property_id=v_property
        and m.owner_account_id=v_owner and m.user_id=v_actor and m.permission='full' and m.revoked_at is null));
    v_sum := v_sum+(v_allocation->>'amount_minor')::numeric;
    v_count := v_count+1;
  end loop;
  if v_sum<>v_amount then raise exception using errcode='22023',message='expense_allocation_total_mismatch'; end if;
  if v_contact is not null and exists(select 1 from jsonb_array_elements(p_input->'allocations') x
    where not exists(select 1 from app_private.contact_properties cp join app_private.contacts c
      on c.id=cp.contact_id and c.owner_account_id=cp.owner_account_id
      where c.id=v_contact and c.owner_account_id=v_owner and c.archived_at is null
        and cp.property_id=(x->>'property_id')::uuid)) then
    raise exception using errcode='22023',message='expense_contact_scope_invalid'; end if;
  if v_task is not null and (v_count<>1 or not exists(select 1 from app_private.tasks t
    where t.id=v_task and t.owner_account_id=v_owner
      and t.property_id=(p_input->'allocations'->0->>'property_id')::uuid)) then
    raise exception using errcode='22023',message='expense_task_scope_invalid'; end if;

  v_key_scope := v_actor::text||':createExpense';
  v_request_hash := encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_key_scope||':'||p_idempotency_key,0));
  select * into v_prior from app_private.idempotency_keys i
    where i.actor_scope=v_key_scope and i.key=p_idempotency_key for update;
  if found and v_prior.expires_at>v_now then
    if v_prior.request_hash<>v_request_hash or v_prior.operation_id<>'createExpense' then
      raise exception using errcode='23505',message='idempotency_key_payload_conflict'; end if;
    v_replay := true;
  elsif found then
    update app_private.idempotency_keys set request_hash=v_request_hash,
      operation_id='createExpense',response_status=null,result_id=null,
      created_at=v_now,expires_at=v_now+interval '24 hours' where id=v_prior.id;
  else
    insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,created_at,expires_at)
    values(v_key_scope,p_idempotency_key,v_request_hash,'createExpense',v_now,v_now+interval '24 hours');
  end if;
  if v_replay then
    select * into v_expense from app_private.expenses e where e.id=v_prior.result_id
      and e.owner_account_id=v_owner and e.submitted_by=v_actor;
    if not found then raise exception using errcode='23505',message='idempotency_result_unavailable'; end if;
  else

    v_id := gen_random_uuid();
    insert into app_private.expenses(id,owner_account_id,category,total_minor,approval,payment_status,
    expense_date,due_date,contact_id,source_task_id,submitted_by,approved_by,note)
    values(v_id,v_owner,v_category,v_amount,
      case when v_approve then 'approved'::app_private.expense_approval else 'proposed'::app_private.expense_approval end,
      'unpaid',v_date,v_due,v_contact,v_task,v_actor,case when v_approve then v_actor else null end,p_input->>'note');
    insert into app_private.expense_allocations(owner_account_id,property_id,expense_id,amount_minor)
      select v_owner,(x->>'property_id')::uuid,v_id,(x->>'amount_minor')::bigint
      from jsonb_array_elements(p_input->'allocations') x;
    update app_private.idempotency_keys set response_status=201,result_id=v_id
      where actor_scope=v_key_scope and key=p_idempotency_key;
    select * into v_expense from app_private.expenses e where e.id=v_id;
    if not found then raise exception using errcode='42501',message='expense_header_scope_required'; end if;
  end if;
  select jsonb_agg(jsonb_build_object('property_id',a.property_id,'amount_minor',a.amount_minor)
    order by a.property_id) into v_allocations
    from app_private.expense_allocations a where a.expense_id=v_expense.id;
  return jsonb_build_object('id',v_expense.id,'category',v_expense.category::text,
    'amount_minor',v_expense.total_minor,'currency','AZN','allocations',v_allocations,
    'approval',v_expense.approval::text,'payment_status',v_expense.payment_status::text,'paid_minor',0,
    'occurred_on',v_expense.expense_date,'due_on',v_expense.due_date,'contact_id',v_contact,
    'task_id',v_task,'note',v_expense.note,'receipt_media_ids','[]'::jsonb,
    'version',v_expense.version,'created_at',v_expense.created_at,'updated_at',v_expense.updated_at);
end;
$$;
revoke all on function api.create_expense_proposal(jsonb,text) from public,anon,authenticated;
grant execute on function api.create_expense_proposal(jsonb,text) to authenticated;
grant create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.create_expense_proposal(jsonb,text) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
