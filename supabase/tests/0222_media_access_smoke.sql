-- EVE-022.2: private proxy source authorization, link exchange, and server-only boundaries.
do $$ begin
  if has_function_privilege('anon','api.get_media_actor_source_for_server(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','api.get_media_actor_source_for_server(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','api.get_media_scoped_source_for_server(text,uuid)','EXECUTE')
     or has_function_privilege('authenticated','api.exchange_scoped_link_for_server(text)','EXECUTE')
     or not has_function_privilege('service_role','api.get_media_actor_source_for_server(uuid,uuid)','EXECUTE')
     or not has_function_privilege('service_role','api.get_media_scoped_source_for_server(text,uuid)','EXECUTE')
     or not has_function_privilege('service_role','api.exchange_scoped_link_for_server(text)','EXECUTE') then
    raise exception 'media proxy bridge grant boundary changed';
  end if;
end $$;

begin;
insert into auth.users(id) values
 ('a0232000-0000-4000-8000-000000000011'),
 ('a0232000-0000-4000-8000-000000000012'),
 ('a0232000-0000-4000-8000-000000000013') on conflict(id) do nothing;
insert into app_private.owner_accounts(id,owner_user_id) values
 ('a0232100-0000-4000-8000-000000000011','a0232000-0000-4000-8000-000000000011'),
 ('a0232100-0000-4000-8000-000000000012','a0232000-0000-4000-8000-000000000013');
insert into app_private.properties(id,owner_account_id,name,area) values
 ('a0232200-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','Media proxy test','Bakı'),
 ('a0232200-0000-4000-8000-000000000012','a0232100-0000-4000-8000-000000000012','Other tenant','Bakı');
insert into app_private.subscriptions(owner_account_id,property_id,state,current_end) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','trialing',now()+interval '7 days');
insert into app_private.property_memberships(owner_account_id,property_id,user_id,permission,granted_by) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232000-0000-4000-8000-000000000012','daily','a0232000-0000-4000-8000-000000000011');
insert into app_private.rooms(id,owner_account_id,property_id,name) values
 ('a0232400-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','Kitchen');
insert into app_private.inventory_items(id,owner_account_id,property_id,room_id,name) values
 ('a0232500-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232400-0000-4000-8000-000000000011','Kettle');
insert into app_private.tasks(id,owner_account_id,property_id,title,due_at) values
 ('a0232600-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','Replace kettle','2026-11-15T10:00:00Z');
insert into app_private.expenses(id,owner_account_id,category,total_minor,expense_date) values
 ('a0232700-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','repair',1000,current_date);
insert into app_private.expense_allocations(owner_account_id,property_id,expense_id,amount_minor) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232700-0000-4000-8000-000000000011',1000);
insert into app_private.media_assets(id,owner_account_id,property_id,classification,bucket,object_key,mime,size_bytes,state) values
 ('a0232300-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','private_inventory','eve-private-inventory','a0232300-0000-4000-8000-000000000011','image/jpeg',4,'validated'),
 ('a0232300-0000-4000-8000-000000000012','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','private_task','eve-private-task','a0232300-0000-4000-8000-000000000012','image/jpeg',4,'validated'),
 ('a0232300-0000-4000-8000-000000000013','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','private_receipt','eve-private-receipt','a0232300-0000-4000-8000-000000000013','application/pdf',4,'validated'),
 ('a0232300-0000-4000-8000-000000000014','a0232100-0000-4000-8000-000000000012','a0232200-0000-4000-8000-000000000012','private_inventory','eve-private-inventory','a0232300-0000-4000-8000-000000000014','image/jpeg',4,'validated');
insert into app_private.media_bindings(owner_account_id,property_id,media_asset_id,inventory_item_id) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232300-0000-4000-8000-000000000011','a0232500-0000-4000-8000-000000000011');
insert into app_private.media_bindings(owner_account_id,property_id,media_asset_id,task_id) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232300-0000-4000-8000-000000000012','a0232600-0000-4000-8000-000000000011');
insert into app_private.media_bindings(owner_account_id,property_id,media_asset_id,expense_id) values
 ('a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011','a0232300-0000-4000-8000-000000000013','a0232700-0000-4000-8000-000000000011');
insert into app_private.access_links(id,owner_account_id,property_id,token_hash,kind,task_id,scopes,expires_at,created_by) values
 ('a0232800-0000-4000-8000-000000000011','a0232100-0000-4000-8000-000000000011','a0232200-0000-4000-8000-000000000011',
  encode(extensions.digest(convert_to(repeat('x',43),'UTF8'),'sha256'),'hex'),'task','a0232600-0000-4000-8000-000000000011',
  '["task.read","task.accept"]',now()+interval '1 day','a0232000-0000-4000-8000-000000000011');

set local role service_role;
set local request.jwt.claim.role='service_role';
do $$ declare v jsonb; h text := 'cc0b1c2c66f3bb9fd1a081c626ba1bef62f6f96441a43be15268523776ac26a1'; i integer; begin
  v := api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000012','a0232300-0000-4000-8000-000000000011');
  if v->>'classification'<>'private_inventory' or v->>'bucket'<>'eve-private-inventory' then
    raise exception 'inventory.read did not authorize validated inventory media';
  end if;
  v := api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000012','a0232300-0000-4000-8000-000000000012');
  if v->>'classification'<>'private_task' then raise exception 'task.read media source missing'; end if;
  begin
    perform api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000012','a0232300-0000-4000-8000-000000000013');
    raise exception 'daily manager read finance receipt';
  exception when no_data_found then null; end;
  v := api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000011','a0232300-0000-4000-8000-000000000013');
  if v->>'classification'<>'private_receipt' then raise exception 'owner finance.read media source missing'; end if;
  begin
    perform api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000012','a0232300-0000-4000-8000-000000000014');
    raise exception 'cross-owner inventory media read';
  exception when no_data_found then null; end;

  v := api.exchange_scoped_link_for_server(h);
  if v->>'resource_type'<>'task' then raise exception 'scoped link exchange resource mismatch'; end if;
  v := api.get_media_scoped_source_for_server(h,'a0232300-0000-4000-8000-000000000012');
  if v->>'classification'<>'private_task' or v->>'link_expires_at' is null then
    raise exception 'task link could not read its bound private media';
  end if;
  begin
    perform api.get_media_scoped_source_for_server(h,'a0232300-0000-4000-8000-000000000011');
    raise exception 'task link crossed to inventory media';
  exception when no_data_found then null; end;
  for i in 1..9 loop perform api.exchange_scoped_link_for_server(h); end loop;
  begin
    perform api.exchange_scoped_link_for_server(h);
    raise exception 'link session exchange passed the 10/minute cap';
  exception when sqlstate 'PGR01' then null; end;
end $$;
reset role;

update app_private.property_memberships set revoked_at=now()
where property_id='a0232200-0000-4000-8000-000000000011' and user_id='a0232000-0000-4000-8000-000000000012';
set local role service_role;
set local request.jwt.claim.role='service_role';
do $$ begin
  begin
    perform api.get_media_actor_source_for_server('a0232000-0000-4000-8000-000000000012','a0232300-0000-4000-8000-000000000011');
    raise exception 'revoked inventory membership retained media access';
  exception when no_data_found then null; end;
end $$;
reset role;

update app_private.access_links set revoked_at=now()
where id='a0232800-0000-4000-8000-000000000011';
set local role service_role;
set local request.jwt.claim.role='service_role';
do $$ declare h text := 'cc0b1c2c66f3bb9fd1a081c626ba1bef62f6f96441a43be15268523776ac26a1'; begin
  begin
    perform api.get_media_scoped_source_for_server(h,'a0232300-0000-4000-8000-000000000012');
    raise exception 'revoked scoped link retained media access';
  exception when sqlstate 'P4100' then null; end;
end $$;
reset role;
rollback;
