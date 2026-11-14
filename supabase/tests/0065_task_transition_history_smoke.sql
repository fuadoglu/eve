-- EVE-017.1 synthetic DB/RPC proof; HTTP/scoped cookie and notification routing are out of scope.
do $$
begin
  if (select p.proowner<>'app_executor'::regrole or not p.prosecdef
      or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.transition_task(uuid,integer,text,text,text,text,uuid[],text)'::regprocedure)
     or has_function_privilege('anon','api.transition_task(uuid,integer,text,text,text,text,uuid[],text)','EXECUTE')
     or not has_function_privilege('service_role','api.transition_task(uuid,integer,text,text,text,text,uuid[],text)','EXECUTE')
     or not has_function_privilege('authenticated','api.transition_task(uuid,integer,text,text,text,text,uuid[],text)','EXECUTE')
     or has_table_privilege('authenticated','app_private.task_transition_events','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','app_private.task_transition_events','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'task transition RPC or table grant boundary is unsafe';
  end if;
end $$;
begin;
insert into auth.users(id) values
 ('f0000000-0000-0000-0000-000000000021'),
 ('f0000000-0000-0000-0000-000000000022'),
 ('f0000000-0000-0000-0000-000000000023') on conflict (id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id) values
 ('f1000000-0000-0000-0000-000000000021','f0000000-0000-0000-0000-000000000021');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('f2000000-0000-0000-0000-000000000021','f1000000-0000-0000-0000-000000000021','A task house','Bakı'),
 ('f2000000-0000-0000-0000-000000000022','f1000000-0000-0000-0000-000000000021','A second house','Bakı');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
 ('f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','active',now()+interval '30 days'),
 ('f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000022','active',now()+interval '30 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','f0000000-0000-0000-0000-000000000022','daily','f0000000-0000-0000-0000-000000000021');
insert into app_private.tasks(id,owner_account_id,property_id,title,due_at,state,version) values
 ('f3000000-0000-0000-0000-000000000021','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','Repair heater',now()+interval '1 day','open',1),
 ('f3000000-0000-0000-0000-000000000022','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','Replace lock',now()+interval '1 day','reported_done',1),
 ('f3000000-0000-0000-0000-000000000023','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000022','Other property task',now()+interval '1 day','open',1);
insert into app_private.tasks(id,owner_account_id,property_id,title,due_at,state,version,required_for_readiness) values
 ('f3000000-0000-0000-0000-000000000024','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','Required inspection',now()+interval '1 day','open',1,true);
insert into app_private.access_links(id,owner_account_id,property_id,token_hash,kind,task_id,scopes,expires_at)
values ('f4000000-0000-0000-0000-000000000021','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021',repeat('a',64),'task','f3000000-0000-0000-0000-000000000021','["task.accept","task.report_done"]',now()+interval '2 days');
insert into app_private.access_links(id,owner_account_id,property_id,token_hash,kind,task_id,scopes,expires_at)
values ('f4000000-0000-0000-0000-000000000024','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021',repeat('c',64),'task','f3000000-0000-0000-0000-000000000024','["task.report_done"]',now()+interval '2 days');
insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes,state,sha256)
values ('f5000000-0000-0000-0000-000000000021','f1000000-0000-0000-0000-000000000021','f2000000-0000-0000-0000-000000000021','private_task','eve-private-task','synthetic-task-media','image/jpeg',128,'validated',repeat('b',64));

set local role service_role;
do $$
declare first_ack jsonb; replay_ack jsonb; done_ack jsonb;
begin
  first_ack := api.transition_task('f3000000-0000-0000-0000-000000000021',1,'accept','task-transition-accept-0001',null,'Contractor',array[]::uuid[],repeat('a',64));
  replay_ack := api.transition_task('f3000000-0000-0000-0000-000000000021',1,'accept','task-transition-accept-0001',null,'Contractor',array[]::uuid[],repeat('a',64));
  if first_ack->>'state'<>'accepted' or first_ack->>'version'<>'2'
     or replay_ack->>'event_id'<>first_ack->>'event_id' or replay_ack->>'replayed'<>'true' then
    raise exception 'scoped task accept/idempotent replay mismatch: % / %',first_ack,replay_ack;
  end if;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000021',2,'report_done','task-transition-bad-media-0001','Bad photo','Contractor',array['f5000000-0000-0000-0000-000000000099']::uuid[],repeat('a',64));
    raise exception 'unvalidated/missing media accepted';
  exception when insufficient_privilege then null;
  end;
  done_ack := api.transition_task('f3000000-0000-0000-0000-000000000021',2,'report_done','task-transition-accept-0001','Initial report','Contractor',array['f5000000-0000-0000-0000-000000000021']::uuid[],repeat('a',64));
  if done_ack->>'state'<>'reported_done' or done_ack->>'version'<>'3' then
    raise exception 'scoped task report/media association mismatch: %',done_ack;
  end if;
  perform set_config('test.task_report_event_id',done_ack->>'event_id',true);
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000024',1,'report_done','task-required-inspection-0001','Done','Contractor',array[]::uuid[],repeat('c',64));
    raise exception 'readiness-required task accepted without completed inspection answers';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000023',1,'accept','task-transition-foreign-0001',null,'Contractor',array[]::uuid[],repeat('a',64));
    raise exception 'task link accepted a different property task';
  exception when insufficient_privilege then null;
  end;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000021',2,'report_done','task-transition-bad-version-0001','Bad version','Contractor',array[]::uuid[],repeat('a',64));
    raise exception 'stale task version accepted';
  exception when serialization_failure then null;
  end;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000021',3,'report_done','task-transition-accept-0001','Changed body','Contractor',array[]::uuid[],repeat('a',64));
    raise exception 'same key with changed body accepted';
  exception when unique_violation then null;
  end;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000021',3,'confirm','task-transition-scoped-confirm-1',null,null,array[]::uuid[],repeat('a',64));
    raise exception 'scoped link confirmed a task';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f0000000-0000-0000-0000-000000000022';
do $$
declare rework_ack jsonb;
begin
  rework_ack := api.transition_task('f3000000-0000-0000-0000-000000000021',3,'request_rework','task-transition-rework-0001','Photo is unclear',null,array[]::uuid[],null);
  if rework_ack->>'state'<>'accepted' or rework_ack->>'version'<>'4' then
    raise exception 'daily task manager rework transition failed: %',rework_ack;
  end if;
  begin
    perform api.transition_task('f3000000-0000-0000-0000-000000000023',1,'cancel','task-transition-cross-property-01',null,null,array[]::uuid[],null);
    raise exception 'manager wrote a task in another property';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub='f0000000-0000-0000-0000-000000000021';
do $$
declare confirmed_ack jsonb;
begin
  confirmed_ack := api.transition_task('f3000000-0000-0000-0000-000000000022',1,'confirm','task-transition-confirm-0001',null,null,array[]::uuid[],null);
  if confirmed_ack->>'state'<>'completed' or confirmed_ack->>'version'<>'2' then
    raise exception 'owner task confirmation failed: %',confirmed_ack;
  end if;
end $$;
reset role;
do $$
begin
  if (select state from app_private.tasks where id='f3000000-0000-0000-0000-000000000021')<>'accepted'
     or (select version from app_private.tasks where id='f3000000-0000-0000-0000-000000000021')<>4
     or (select count(*) from app_private.task_transition_events where task_id='f3000000-0000-0000-0000-000000000021')<>3
     or (select count(*) from app_private.task_transition_media where media_asset_id='f5000000-0000-0000-0000-000000000021')<>1
     or (select description from app_private.tasks where id='f3000000-0000-0000-0000-000000000021') is not null then
    raise exception 'task transition history, atomicity, or instruction immutability mismatch';
  end if;
  if not exists(select 1 from app_private.task_transition_media m
      where m.transition_event_id=current_setting('test.task_report_event_id')::uuid)
     or (select count(*) from app_private.outbox where event_kind='task.reported_done'
      and payload->>'transition_event_id'=current_setting('test.task_report_event_id'))<>1 then
    raise exception 'task report media association or owner notice outbox mismatch';
  end if;
  begin
    update app_private.task_transition_events set note='rewrite' where task_id='f3000000-0000-0000-0000-000000000021';
    raise exception 'append-only task history was mutable';
  exception when integrity_constraint_violation then null;
  end;
end $$;
rollback;
