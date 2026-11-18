-- EVE-018.2: lease-protected, server-only outbox dispatch primitives.
-- Provider delivery and hosted cron activation remain external integration work.

alter table app_private.outbox add column lease_token uuid;
alter table app_private.outbox add constraint outbox_worker_lease_state
  check (
    (state='processing' and locked_until is not null and lease_token is not null)
    or (state<>'processing' and locked_until is null and lease_token is null)
  );
alter table app_private.notification_preferences add constraint notification_preferences_timezone_baku
  check (timezone='Asia/Baku');

grant select on app_private.notification_preferences to app_executor;
grant select, update on app_private.outbox to app_executor;

create policy notification_preferences_scheduler_read
  on app_private.notification_preferences for select to app_executor using (true);
create policy outbox_scheduler_read
  on app_private.outbox for select to app_executor using (true);
create policy outbox_scheduler_update
  on app_private.outbox for update to app_executor using (true) with check (true);

create function app_private.outbox_quiet_until(p_recipient_user_id uuid, p_at timestamptz)
returns timestamptz
language plpgsql stable security definer set search_path = '' as $$
declare
  v_start time := time '22:00';
  v_end time := time '08:00';
  v_local timestamp;
  v_local_date date;
  v_local_time time;
begin
  if p_at is null then return null; end if;
  if p_recipient_user_id is null then return p_at; end if;

  select coalesce((select p.quiet_start from app_private.notification_preferences p
                     where p.user_id = p_recipient_user_id), time '22:00'),
         coalesce((select p.quiet_end from app_private.notification_preferences p
                     where p.user_id = p_recipient_user_id), time '08:00')
    into v_start, v_end;

  v_local := p_at at time zone 'Asia/Baku';
  v_local_date := v_local::date;
  v_local_time := v_local::time;

  -- Equal endpoints form an empty half-open interval.
  if v_start = v_end then return p_at; end if;

  if v_start < v_end then
    if v_local_time >= v_start and v_local_time < v_end then
      return (v_local_date + v_end) at time zone 'Asia/Baku';
    end if;
    return p_at;
  end if;

  if v_local_time >= v_start then
    return ((v_local_date + 1) + v_end) at time zone 'Asia/Baku';
  elsif v_local_time < v_end then
    return (v_local_date + v_end) at time zone 'Asia/Baku';
  end if;
  return p_at;
end;
$$;
revoke all on function app_private.outbox_quiet_until(uuid,timestamptz)
  from public, anon, authenticated, service_role, app_executor;

create function api.claim_due_outbox(
  p_limit integer default 25, p_lease_seconds integer default 300,
  p_max_attempts integer default 8
)
returns table(
  id uuid, event_kind varchar, dedupe_key varchar, recipient_user_id uuid,
  property_id uuid, owner_account_id uuid, payload jsonb, attempts integer,
  lease_token uuid, locked_until timestamptz
)
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_role text := current_setting('request.jwt.claim.role', true);
  v_now timestamptz := clock_timestamp();
  v_row app_private.outbox%rowtype;
  v_quiet_until timestamptz;
  v_token uuid;
begin
  if v_role is distinct from 'service_role' then
    raise exception using errcode='42501', message='outbox_worker_forbidden';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_lease_seconds is null or p_lease_seconds < 30 or p_lease_seconds > 900
     or p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception using errcode='22023', message='outbox_batch_limit_invalid';
  end if;

  for v_row in
    select o.* from app_private.outbox o
    where (o.state='pending' and o.next_attempt_at <= v_now)
       or (o.state='processing' and o.locked_until <= v_now)
    order by o.next_attempt_at, o.created_at, o.id
    for update skip locked
    limit p_limit
  loop
    if v_row.attempts >= p_max_attempts then
      update app_private.outbox o set state='failed', locked_until=null, lease_token=null,
        last_error_code=coalesce(o.last_error_code,'outbox_max_attempts_reached')
        where o.id=v_row.id;
      continue;
    end if;

    v_quiet_until := app_private.outbox_quiet_until(v_row.recipient_user_id, v_now);
    if v_quiet_until > v_now then
      update app_private.outbox o set state='pending', next_attempt_at=v_quiet_until,
        locked_until=null, lease_token=null
        where o.id=v_row.id;
      continue;
    end if;

    v_token := gen_random_uuid();
    return query update app_private.outbox o
      set state='processing', attempts=o.attempts+1,
          locked_until=v_now + make_interval(secs => p_lease_seconds), lease_token=v_token
      where o.id=v_row.id
      returning o.id,o.event_kind,o.dedupe_key,o.recipient_user_id,o.property_id,
        o.owner_account_id,o.payload,o.attempts,o.lease_token,o.locked_until;
  end loop;
end;
$$;

create function api.complete_outbox(p_id uuid, p_lease_token uuid)
returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_role text := current_setting('request.jwt.claim.role', true);
  v_updated integer;
begin
  if v_role is distinct from 'service_role' then
    raise exception using errcode='42501', message='outbox_worker_forbidden';
  end if;
  if p_id is null or p_lease_token is null then
    raise exception using errcode='22023', message='outbox_lease_required';
  end if;
  update app_private.outbox o set state='completed', locked_until=null, lease_token=null,
      last_error_code=null
    where o.id=p_id and o.state='processing' and o.lease_token=p_lease_token
      and o.locked_until > clock_timestamp();
  get diagnostics v_updated = row_count;
  return v_updated=1;
end;
$$;

create function api.retry_outbox(
  p_id uuid, p_lease_token uuid, p_error_code text, p_max_attempts integer default 8
)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_role text := current_setting('request.jwt.claim.role', true);
  v_state app_private.job_state;
begin
  if v_role is distinct from 'service_role' then
    raise exception using errcode='42501', message='outbox_worker_forbidden';
  end if;
  if p_id is null or p_lease_token is null
     or p_error_code is null or p_error_code !~ '^[a-z][a-z0-9_.-]{0,99}$'
     or p_max_attempts is null or p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception using errcode='22023', message='outbox_retry_input_invalid';
  end if;
  update app_private.outbox o set
      state=case when o.attempts >= p_max_attempts then 'failed'::app_private.job_state else 'pending'::app_private.job_state end,
      next_attempt_at=case when o.attempts >= p_max_attempts then o.next_attempt_at
        else clock_timestamp() + make_interval(mins => (power(2, greatest(o.attempts-1,0)))::integer) end,
      locked_until=null, lease_token=null, last_error_code=p_error_code
    where o.id=p_id and o.state='processing' and o.lease_token=p_lease_token
      and o.locked_until > clock_timestamp()
    returning o.state into v_state;
  if not found then return null; end if;
  return v_state::text;
end;
$$;

revoke all on function api.claim_due_outbox(integer,integer,integer),
  api.complete_outbox(uuid,uuid), api.retry_outbox(uuid,uuid,text,integer)
  from public, anon, authenticated, service_role;
grant execute on function api.claim_due_outbox(integer,integer,integer),
  api.complete_outbox(uuid,uuid), api.retry_outbox(uuid,uuid,text,integer) to service_role;

grant usage, create on schema api to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function api.claim_due_outbox(integer,integer,integer) owner to app_executor;
alter function api.complete_outbox(uuid,uuid) owner to app_executor;
alter function api.retry_outbox(uuid,uuid,text,integer) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema api from app_executor;

grant usage, create on schema app_private to app_executor;
grant app_executor to current_user with set true, inherit false;
alter function app_private.outbox_quiet_until(uuid,timestamptz) owner to app_executor;
revoke app_executor from current_user;
revoke create on schema app_private from app_executor;

grant usage on schema api to service_role;
grant usage on schema app_private to app_executor;
