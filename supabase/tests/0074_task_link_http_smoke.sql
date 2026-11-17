-- EVE-017.3 / AT15-16: real SQL authorization, prefetch-safe read, revoke, expiry and scope.
begin;
insert into auth.users(id) values
  ('f0000000-0000-0000-0000-000000000074'),
  ('f0000000-0000-0000-0000-000000000075') on conflict(id) do nothing;
insert into auth.sessions(id,user_id) values
  ('f5000000-0000-0000-0000-000000000074','f0000000-0000-0000-0000-000000000074'),
  ('f5000000-0000-0000-0000-000000000075','f0000000-0000-0000-0000-000000000075');
insert into app_private.owner_accounts(id,owner_user_id) values
  ('f1000000-0000-0000-0000-000000000074','f0000000-0000-0000-0000-000000000074'),
  ('f1000000-0000-0000-0000-000000000075','f0000000-0000-0000-0000-000000000075');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f2000000-0000-0000-0000-000000000074','f1000000-0000-0000-0000-000000000074','Task link house','Bakı'),
  ('f2000000-0000-0000-0000-000000000075','f1000000-0000-0000-0000-000000000075','Foreign house','Bakı');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
  ('f1000000-0000-0000-0000-000000000074','f2000000-0000-0000-0000-000000000074','active',now()+interval '30 days'),
  ('f1000000-0000-0000-0000-000000000075','f2000000-0000-0000-0000-000000000075','active',now()+interval '30 days');
insert into app_private.tasks(id,owner_account_id,property_id,title,due_at,state,version) values
  ('f3000000-0000-0000-0000-000000000074','f1000000-0000-0000-0000-000000000074','f2000000-0000-0000-0000-000000000074','Open task',now()+interval '8 days','open',1),
  ('f3000000-0000-0000-0000-000000000075','f1000000-0000-0000-0000-000000000075','f2000000-0000-0000-0000-000000000075','Foreign task',now()+interval '8 days','open',1);

do $$ begin
  if has_function_privilege('anon','api.create_task_link(uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    or has_function_privilege('authenticated','api.create_task_link(uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    or has_function_privilege('authenticated','api.revoke_task_link(uuid,uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','api.read_scoped_task_for_server(text)','EXECUTE')
    or has_function_privilege('anon','api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[],jsonb)','EXECUTE')
    or has_function_privilege('authenticated','api.read_scoped_task_for_server(text)','EXECUTE')
    or has_function_privilege('authenticated','api.transition_scoped_task_for_server(text,integer,text,text,text,text,uuid[],jsonb)','EXECUTE')
    or not has_function_privilege('service_role','api.create_task_link(uuid,uuid,uuid,text,text,text,timestamptz)','EXECUTE')
    or not has_function_privilege('service_role','api.revoke_task_link(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'task link RPC grants are broader than intended';
  end if;
end $$;

set local role authenticated;
do $$ begin
  begin
    perform api.create_task_link('f0000000-0000-0000-0000-000000000074',
      'f5000000-0000-0000-0000-000000000074','f3000000-0000-0000-0000-000000000074',
      repeat('9',64),repeat('9',64),repeat('9',64),null);
    raise exception 'direct authenticated link creation worked';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local request.jwt.claim.role='service_role';
set local role service_role;
do $$ declare first_link jsonb; replay_link jsonb;
begin
  first_link := api.create_task_link('f0000000-0000-0000-0000-000000000074',
    'f5000000-0000-0000-0000-000000000074','f3000000-0000-0000-0000-000000000074',
    repeat('a',64),repeat('b',64),repeat('c',64),null);
  replay_link := api.create_task_link('f0000000-0000-0000-0000-000000000074',
    'f5000000-0000-0000-0000-000000000074','f3000000-0000-0000-0000-000000000074',
    repeat('a',64),repeat('b',64),repeat('c',64),null);
  if first_link->>'link_id'<>replay_link->>'link_id' or replay_link->>'replayed'<>'true' then
    raise exception 'task link idempotent replay failed';
  end if;
  perform set_config('test.task_link_id',first_link->>'link_id',true);
  begin
    perform api.create_task_link('f0000000-0000-0000-0000-000000000074',
      'f5000000-0000-0000-0000-000000000074','f3000000-0000-0000-0000-000000000074',
      repeat('a',64),repeat('b',64),repeat('d',64),null);
    raise exception 'same request key accepted changed payload';
  exception when unique_violation then null;
  end;
  begin
    perform api.create_task_link('f0000000-0000-0000-0000-000000000074',
      'f5000000-0000-0000-0000-000000000074','f3000000-0000-0000-0000-000000000075',
      repeat('e',64),repeat('f',64),repeat('1',64),null);
    raise exception 'cross-owner task link created';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.create_task_link('f0000000-0000-0000-0000-000000000074',
      'f5000000-0000-0000-0000-000000000099','f3000000-0000-0000-0000-000000000074',
      repeat('e',64),repeat('f',64),repeat('1',64),null);
    raise exception 'revoked or absent session created link';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local request.jwt.claim.sub='';
set local request.jwt.claim.role='service_role';
set local role service_role;
do $$ declare result jsonb; v_proposal jsonb := '{"amount_minor":1250,"category":"cleaning","note":"Təmizlik materialı"}'::jsonb;
begin
  result := api.read_scoped_task_for_server(repeat('a',64));
  if result->>'state'<>'open' or result->>'version'<>'1' then raise exception 'scoped safe read wrong'; end if;
  result := api.read_scoped_task_for_server(repeat('a',64));
  if result->>'state'<>'open' or result->>'version'<>'1' then
    raise exception 'GET/prefetch read changed task state';
  end if;
  begin
    perform api.transition_scoped_task_for_server(repeat('a',64),1,'confirm',
      'task-link-deny-confirm-01','Usta',null,array[]::uuid[]);
    raise exception 'scoped link confirmed task';
  exception when insufficient_privilege then null;
  end;
  result := api.transition_scoped_task_for_server(repeat('a',64),1,'accept',
    'task-link-accept-key-01','Usta',null,array[]::uuid[]);
  if result->>'state'<>'accepted' or result->>'version'<>'2' then
    raise exception 'explicit scoped POST did not accept task';
  end if;
  begin
    perform api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
      'task-link-invalid-expense-01','Usta',null,array[]::uuid[],
      '{"amount_minor":1250,"category":"cleaning","property_id":"f2000000-0000-0000-0000-000000000075"}'::jsonb);
    raise exception 'cross-property expense input accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
      'task-link-invalid-sum-001','Usta',null,array[]::uuid[],
      '{"amount_minor":0,"category":"cleaning"}'::jsonb);
    raise exception 'zero-value expense input accepted';
  exception when invalid_parameter_value then null;
  end;
  result := api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
    'task-link-expense-key-001','Usta','İş bitdi',array[]::uuid[],v_proposal);
  if result->>'state'<>'reported_done' or result->>'version'<>'3' then
    raise exception 'scoped report plus expense did not acknowledge task';
  end if;
  result := api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
    'task-link-expense-key-001','Usta','İş bitdi',array[]::uuid[],v_proposal);
  if result->>'state'<>'reported_done' or result->>'version'<>'3' then
    raise exception 'scoped report replay changed task';
  end if;
  begin
    perform api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
      'task-link-expense-key-001','Usta','İş bitdi',array[]::uuid[],
      '{"amount_minor":1251,"category":"cleaning","note":"Təmizlik materialı"}'::jsonb);
    raise exception 'same-key changed expense payload accepted';
  exception when unique_violation then null;
  end;
end $$;
reset role;
do $$ begin
  if (select count(*) from app_private.expenses e where e.source_task_id='f3000000-0000-0000-0000-000000000074'
      and e.submitted_link_id=current_setting('test.task_link_id')::uuid)<>1
    or not exists(select 1 from app_private.expenses e
      join app_private.expense_allocations a on a.expense_id=e.id and a.owner_account_id=e.owner_account_id
      where e.source_task_id='f3000000-0000-0000-0000-000000000074'
        and e.submitted_link_id=current_setting('test.task_link_id')::uuid
        and e.approval='proposed' and e.payment_status='unpaid'
        and e.submitted_by is null and e.approved_by is null and e.total_minor=1250
        and a.property_id='f2000000-0000-0000-0000-000000000074' and a.amount_minor=1250) then
    raise exception 'scoped expense state, allocation, or replay count mismatch';
  end if;
end $$;

set local request.jwt.claim.role='service_role';
set local request.jwt.claim.sub='';
set local role service_role;
do $$ begin
  begin
    perform api.revoke_task_link('f0000000-0000-0000-0000-000000000075',
      'f5000000-0000-0000-0000-000000000075',current_setting('test.task_link_id')::uuid);
    raise exception 'foreign owner revoked task link';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local request.jwt.claim.sub='';
set local request.jwt.claim.role='service_role';
set local role service_role;
select api.revoke_task_link('f0000000-0000-0000-0000-000000000074',
  'f5000000-0000-0000-0000-000000000074',current_setting('test.task_link_id')::uuid);
reset role;
set local request.jwt.claim.sub='';
set local request.jwt.claim.role='service_role';
set local role service_role;
do $$ begin
  begin
    perform api.read_scoped_task_for_server(repeat('a',64));
    raise exception 'revoked task link remained readable';
  exception when sqlstate 'P4100' then null;
  end;
  begin
    perform api.transition_scoped_task_for_server(repeat('a',64),2,'report_done',
      'task-link-done-key-001','Usta',null,array[]::uuid[]);
    raise exception 'revoked task link wrote task';
  exception when sqlstate 'P4100' then null;
  end;
end $$;
reset role;

-- A read-only scope cannot transition; an expired link cannot read.
insert into app_private.access_links(owner_account_id,property_id,token_hash,kind,task_id,scopes,created_at,expires_at)
values ('f1000000-0000-0000-0000-000000000074','f2000000-0000-0000-0000-000000000074',
  repeat('7',64),'task','f3000000-0000-0000-0000-000000000074','["task.read"]',now()-interval '2 days',now()+interval '1 day'),
 ('f1000000-0000-0000-0000-000000000074','f2000000-0000-0000-0000-000000000074',
  repeat('8',64),'task','f3000000-0000-0000-0000-000000000074','["task.read"]',now()-interval '2 days',now()-interval '1 second');
set local request.jwt.claim.role='service_role';
set local role service_role;
do $$ begin
  begin
    perform api.transition_scoped_task_for_server(repeat('7',64),2,'report_done',
      'task-link-scope-key-001','Usta',null,array[]::uuid[]);
    raise exception 'read-only task link wrote task';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.read_scoped_task_for_server(repeat('8',64));
    raise exception 'expired task link remained readable';
  exception when sqlstate 'P4100' then null;
  end;
end $$;
reset role;
rollback;
