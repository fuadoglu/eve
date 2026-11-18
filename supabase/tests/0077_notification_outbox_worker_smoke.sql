-- EVE-018.2 synthetic component proof. No SMTP, push provider, or hosted cron.
begin;

do $$ begin
  if has_function_privilege('anon','api.claim_due_outbox(integer,integer,integer)','EXECUTE')
     or has_function_privilege('authenticated','api.claim_due_outbox(integer,integer,integer)','EXECUTE')
     or has_function_privilege('anon','api.complete_outbox(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','api.retry_outbox(uuid,uuid,text,integer)','EXECUTE')
     or has_table_privilege('anon','app_private.outbox','SELECT')
     or has_table_privilege('authenticated','app_private.outbox','SELECT')
     or has_table_privilege('service_role','app_private.outbox','SELECT') then
    raise exception 'outbox worker or private table grant is too broad';
  end if;
  if not has_function_privilege('service_role','api.claim_due_outbox(integer,integer,integer)','EXECUTE')
     or not has_function_privilege('service_role','api.complete_outbox(uuid,uuid)','EXECUTE')
     or not has_function_privilege('service_role','api.retry_outbox(uuid,uuid,text,integer)','EXECUTE') then
    raise exception 'service_role outbox RPC grants are missing';
  end if;
end $$;

insert into auth.users(id,email) values
  ('a1820000-0000-0000-0000-000000000001','eve0182-outbox@example.test');
insert into app_private.notification_preferences(user_id,preferences,quiet_start,quiet_end,timezone)
values('a1820000-0000-0000-0000-000000000001','{}'::jsonb,'22:00','08:00','Asia/Baku');
do $$ begin
  begin
    update app_private.notification_preferences set timezone='UTC'
      where user_id='a1820000-0000-0000-0000-000000000001';
    raise exception 'unsupported notification timezone was accepted';
  exception when check_violation then null;
  end;
end $$;

do $$ declare v_time timestamptz;
begin
  v_time := app_private.outbox_quiet_until(
    'a1820000-0000-0000-0000-000000000001',timestamptz '2026-11-18 20:00:00+00');
  if v_time is distinct from timestamptz '2026-11-19 04:00:00+00' then
    raise exception 'overnight quiet period did not resolve to Asia/Baku quiet end: %',v_time;
  end if;
  if app_private.outbox_quiet_until(null,timestamptz '2026-11-18 20:00:00+00')
       is distinct from timestamptz '2026-11-18 20:00:00+00'
     or app_private.outbox_quiet_until('a1820000-0000-0000-0000-000000000001',
         timestamptz '2026-11-18 12:00:00+00') is distinct from timestamptz '2026-11-18 12:00:00+00' then
    raise exception 'no-recipient or outside-quiet time was unexpectedly delayed';
  end if;
end $$;
update app_private.notification_preferences set
  quiet_start=((clock_timestamp() at time zone 'Asia/Baku')::time - interval '1 hour')::time,
  quiet_end=((clock_timestamp() at time zone 'Asia/Baku')::time + interval '1 hour')::time
where user_id='a1820000-0000-0000-0000-000000000001';

-- The existing global event key is the producer-event dedupe boundary.
insert into app_private.outbox(event_kind,dedupe_key,payload,next_attempt_at,created_at)
values('test.event','eve0182:duplicate','{}'::jsonb,now()-interval '1 year',now()-interval '1 year')
on conflict(dedupe_key) do nothing;
insert into app_private.outbox(event_kind,dedupe_key,payload,next_attempt_at,created_at)
values('test.event','eve0182:duplicate','{}'::jsonb,now()-interval '1 year',now()-interval '1 year')
on conflict(dedupe_key) do nothing;
do $$ begin
  if (select count(*) from app_private.outbox where dedupe_key='eve0182:duplicate')<>1 then
    raise exception 'same producer event created duplicate outbox rows';
  end if;
end $$;
update app_private.outbox set state='completed' where dedupe_key='eve0182:duplicate';

-- First item is quiet for this recipient and must remain pending until quiet end.
insert into app_private.outbox(event_kind,dedupe_key,recipient_user_id,payload,next_attempt_at,created_at)
values('test.quiet','eve0182:quiet','a1820000-0000-0000-0000-000000000001',
  '{}'::jsonb,now()-interval '1 year',now()-interval '1 year');
insert into app_private.outbox(event_kind,dedupe_key,payload,next_attempt_at,created_at)
values('test.claim','eve0182:claim','{}'::jsonb,now()-interval '1 year',now()-interval '364 days');

create temporary table eve0182_worker_results (
  id uuid primary key, first_lease uuid not null, retry_lease uuid, current_lease uuid
);
grant select,insert,update on eve0182_worker_results to service_role;

set local request.jwt.claim.role='service_role';
set local role service_role;
do $$ begin
  if (select count(*) from api.claim_due_outbox(1))<>0 then
    raise exception 'quiet-hours recipient was dispatched';
  end if;
end $$;
reset role;
do $$ begin
  if (select state from app_private.outbox where dedupe_key='eve0182:quiet')<>'pending'
     or (select next_attempt_at<=clock_timestamp() from app_private.outbox where dedupe_key='eve0182:quiet') then
    raise exception 'recipient quiet-hours item was not postponed';
  end if;
end $$;

set local role service_role;
do $$ declare v_id uuid; v_attempts integer; v_lease uuid; v_locked timestamptz;
begin
  select c.id,c.attempts,c.lease_token,c.locked_until into v_id,v_attempts,v_lease,v_locked
    from api.claim_due_outbox(1) c;
  if v_id is null or v_attempts<>1 or v_lease is null or v_locked<=clock_timestamp() then
    raise exception 'due event was not claimed with a bounded lease';
  end if;
  if api.complete_outbox(v_id,gen_random_uuid()) then
    raise exception 'stale lease token completed an outbox row';
  end if;
  if api.retry_outbox(v_id,gen_random_uuid(),'safe.test_error') is not null then
    raise exception 'stale lease token retried an outbox row';
  end if;
  begin
    perform api.retry_outbox(v_id,v_lease,'Provider timeout with guest email guest@example.com');
    raise exception 'PII-shaped worker error was accepted';
  exception when sqlstate '22023' then null;
  end;
  if api.retry_outbox(v_id,v_lease,'provider.timeout')<>'pending' then
    raise exception 'valid worker failure did not return to pending';
  end if;
  insert into eve0182_worker_results(id,first_lease) values(v_id,v_lease);
end $$;
reset role;
do $$ begin
  if (select attempts from app_private.outbox where dedupe_key='eve0182:claim')<>1
     or (select last_error_code from app_private.outbox where dedupe_key='eve0182:claim')<>'provider.timeout'
     or (select next_attempt_at<clock_timestamp()+interval '59 seconds'
          from app_private.outbox where dedupe_key='eve0182:claim')
     or (select next_attempt_at>clock_timestamp()+interval '61 seconds'
          from app_private.outbox where dedupe_key='eve0182:claim') then
    raise exception 'retry attempt, redacted code, or first exponential delay is incorrect';
  end if;
  update app_private.outbox set next_attempt_at=clock_timestamp()-interval '1 second'
    where dedupe_key='eve0182:claim';
end $$;

set local role service_role;
do $$ declare v_id uuid; v_lease uuid;
begin
  select c.id,c.lease_token into v_id,v_lease from api.claim_due_outbox(1) c;
  if v_id is null or v_lease is null then raise exception 'retry row was not re-claimed'; end if;
  update eve0182_worker_results set retry_lease=v_lease where id=v_id;
end $$;
reset role;
do $$ begin
  update app_private.outbox set locked_until=clock_timestamp()-interval '1 second'
    where dedupe_key='eve0182:claim';
end $$;
set local role service_role;
do $$ declare v_id uuid; v_lease uuid; v_old_lease uuid;
begin
  select r.id,r.retry_lease into v_id,v_old_lease from eve0182_worker_results r;
  select c.lease_token into v_lease from api.claim_due_outbox(1) c where c.id=v_id;
  if v_lease is null or v_lease=v_old_lease then raise exception 'expired lease token was reused'; end if;
  if api.complete_outbox(v_id,v_old_lease) then
    raise exception 'worker with expired lease completed a re-claimed row';
  end if;
  if not api.complete_outbox(v_id,v_lease) then
    raise exception 'current lease could not complete row';
  end if;
  update eve0182_worker_results set current_lease=v_lease where id=v_id;
end $$;
reset role;
do $$ begin
  if (select state from app_private.outbox where dedupe_key='eve0182:claim')<>'completed'
     or (select lease_token is not null or locked_until is not null
           from app_private.outbox where dedupe_key='eve0182:claim') then
    raise exception 'completion did not clear the active lease';
  end if;
end $$;

rollback;
