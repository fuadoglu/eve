-- EVE-017.3 / AT16: one scoped report transaction includes an optional proposed expense.
-- The public DTO remains ScopedTask. A replay never creates another expense.

create policy expenses_scoped_task_read on app_private.expenses
  for select to app_executor using (
    submitted_link_id is not null and source_task_id is not null
    and exists(select 1 from app_private.access_links l
      where l.id=expenses.submitted_link_id and l.task_id=expenses.source_task_id
        and l.owner_account_id=expenses.owner_account_id
        and l.token_hash=current_setting('eve.scoped_task_token_hash',true))
  );
create policy expenses_scoped_task_insert on app_private.expenses
  for insert to app_executor with check (
    approval='proposed' and payment_status='unpaid' and approved_by is null
    and submitted_by is null and submitted_link_id is not null and source_task_id is not null
    and exists(select 1 from app_private.access_links l
      where l.id=expenses.submitted_link_id and l.task_id=expenses.source_task_id
        and l.owner_account_id=expenses.owner_account_id
        and l.token_hash=current_setting('eve.scoped_task_token_hash',true)
        and l.revoked_at is null and l.expires_at>statement_timestamp()
        and l.scopes ? 'task.report_done')
  );
create policy expense_allocations_scoped_task_insert on app_private.expense_allocations
  for insert to app_executor with check (
    exists(select 1 from app_private.expenses e
      join app_private.access_links l on l.id=e.submitted_link_id
      where e.id=expense_allocations.expense_id
        and e.owner_account_id=expense_allocations.owner_account_id
        and l.property_id=expense_allocations.property_id
        and l.owner_account_id=expense_allocations.owner_account_id
        and l.task_id=e.source_task_id
        and l.token_hash=current_setting('eve.scoped_task_token_hash',true))
  );
create policy idempotency_keys_scoped_task_read on app_private.idempotency_keys
  for select to app_executor using (
    actor_scope='link:'||current_setting('eve.scoped_task_link_id',true)||':reportDone'
    and operation_id='scopedTaskReport');
create policy idempotency_keys_scoped_task_insert on app_private.idempotency_keys
  for insert to app_executor with check (
    actor_scope='link:'||current_setting('eve.scoped_task_link_id',true)||':reportDone'
    and operation_id='scopedTaskReport');
create policy idempotency_keys_scoped_task_update on app_private.idempotency_keys
  for update to app_executor using (
    actor_scope='link:'||current_setting('eve.scoped_task_link_id',true)||':reportDone'
    and operation_id='scopedTaskReport')
  with check (actor_scope='link:'||current_setting('eve.scoped_task_link_id',true)||':reportDone'
    and operation_id='scopedTaskReport');

drop function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[]);
grant create on schema api to app_executor;
create function api.transition_scoped_task_for_server(
  p_link_token_hash text,p_expected_version integer,p_action text,
  p_idempotency_key text,p_claimed_name text,p_note text default null,
  p_media_ids uuid[] default array[]::uuid[],p_expense_proposal jsonb default null
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_link app_private.access_links%rowtype; v_task app_private.tasks%rowtype;
  v_ack jsonb; v_prior app_private.idempotency_keys%rowtype;
  v_scope text; v_key_hash text; v_request_hash text;
  v_amount bigint; v_category app_private.expense_category;
  v_expense_id uuid; v_now timestamptz := statement_timestamp();
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' then
    raise exception using errcode='42501',message='server_adapter_required';
  end if;
  -- Service-role link actions must not inherit any earlier actor claim.
  perform pg_catalog.set_config('request.jwt.claim.sub','',true);
  perform pg_catalog.set_config('request.jwt.claims','',true);
  if p_link_token_hash is null or p_link_token_hash !~ '^[0-9a-f]{64}$'
    or p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9_-]{16,128}$' then
    raise exception using errcode='22023',message='invalid_scoped_task_input';
  end if;
  select * into v_link from app_private.access_links
    where token_hash=p_link_token_hash and kind='task' for share;
  if not found then raise exception using errcode='P0002',message='task_link_not_found'; end if;
  if v_link.revoked_at is not null or v_link.expires_at<=v_now then
    raise exception using errcode='P4100',message='task_link_expired'; end if;
  if p_expense_proposal is not null then
    if p_action<>'report_done' or jsonb_typeof(p_expense_proposal) is distinct from 'object'
      or p_expense_proposal - array['amount_minor','category','note'] <> '{}'::jsonb
      or jsonb_typeof(p_expense_proposal->'amount_minor') is distinct from 'number'
      or (p_expense_proposal->>'amount_minor') !~ '^[1-9][0-9]*$'
      or (p_expense_proposal->>'amount_minor')::numeric>9007199254740991
      or jsonb_typeof(p_expense_proposal->'category') is distinct from 'string'
      or p_expense_proposal->>'category' not in
        ('utilities','building_service','cleaning','repair','purchase','consumables','other')
      or (p_expense_proposal ? 'note' and
        (jsonb_typeof(p_expense_proposal->'note') is distinct from 'string'
          or length(p_expense_proposal->>'note')>2000)) then
      raise exception using errcode='22023',message='invalid_scoped_expense_proposal';
    end if;
    v_amount := (p_expense_proposal->>'amount_minor')::bigint;
    v_category := (p_expense_proposal->>'category')::app_private.expense_category;
  end if;
  if p_action='report_done' then
    v_scope := 'link:'||v_link.id::text||':reportDone';
    v_key_hash := encode(extensions.digest(convert_to(p_idempotency_key,'UTF8'),'sha256'),'hex');
    v_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
      'task_id',v_link.task_id,'expected_version',p_expected_version,
      'claimed_name',p_claimed_name,'note',p_note,'media_ids',to_jsonb(p_media_ids),
      'expense_proposal',p_expense_proposal)::text,'UTF8'),'sha256'),'hex');
    perform pg_catalog.set_config('eve.scoped_task_link_id',v_link.id::text,true);
    perform pg_catalog.set_config('eve.scoped_task_token_hash',p_link_token_hash,true);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope||':'||v_key_hash,0));
    select * into v_prior from app_private.idempotency_keys i
      where i.actor_scope=v_scope and i.key=v_key_hash for update;
    if found then
      if v_prior.request_hash<>v_request_hash or v_prior.operation_id<>'scopedTaskReport' then
        raise exception using errcode='23505',message='idempotency_key_payload_mismatch'; end if;
    else
      insert into app_private.idempotency_keys(actor_scope,key,request_hash,operation_id,
        created_at,expires_at)
      values(v_scope,v_key_hash,v_request_hash,'scopedTaskReport',v_now,v_now+interval '24 hours');
    end if;
  end if;
  -- Existing transition validates exact action scope, task/property, expiry/revoke,
  -- expected version, media binding and transition history in this transaction.
  v_ack := api.transition_task(v_link.task_id,p_expected_version,p_action,
    p_idempotency_key,p_note,p_claimed_name,p_media_ids,p_link_token_hash);
  if p_action='report_done' then
    if v_prior.id is not null then
      if v_prior.result_id is distinct from (v_ack->>'event_id')::uuid
        or v_ack->>'replayed'<>'true' then
        raise exception using errcode='23505',message='scoped_task_replay_mismatch'; end if;
    else
      if v_ack->>'replayed'='true' then
        raise exception using errcode='23505',message='scoped_task_prior_without_expense_record'; end if;
      if p_expense_proposal is not null then
        select * into v_task from app_private.tasks t where t.id=v_link.task_id
          and t.property_id=v_link.property_id and t.owner_account_id=v_link.owner_account_id;
        if not found then raise exception using errcode='P0002',message='task_not_found'; end if;
        v_expense_id := gen_random_uuid();
        insert into app_private.expenses(id,owner_account_id,category,total_minor,approval,
          payment_status,expense_date,source_task_id,submitted_link_id,note)
        values(v_expense_id,v_task.owner_account_id,v_category,v_amount,'proposed','unpaid',
          (v_now at time zone 'Asia/Baku')::date,v_task.id,v_link.id,p_expense_proposal->>'note');
        insert into app_private.expense_allocations(owner_account_id,property_id,expense_id,amount_minor)
        values(v_task.owner_account_id,v_task.property_id,v_expense_id,v_amount);
      end if;
      update app_private.idempotency_keys set result_id=(v_ack->>'event_id')::uuid,
        response_status=200 where actor_scope=v_scope and key=v_key_hash;
    end if;
  end if;
  return api.read_scoped_task_for_server(p_link_token_hash);
end;
$$;
revoke all on function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[],jsonb)
  from public,anon,authenticated,service_role;
grant execute on function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[],jsonb)
  to service_role;
grant app_executor to current_user with set true, inherit false;
alter function api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[],jsonb) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;
