-- EVE-006.2: only reviewed RPCs can cross the Data API schema; media finalize is service-role only.
do $$
declare
  mismatch_count integer;
begin
  if not has_schema_privilege('authenticated','api','USAGE')
     or has_schema_privilege('anon','api','USAGE')
     or not has_schema_privilege('service_role','api','USAGE') then
    raise exception 'api schema grant boundary changed';
  end if;

  select count(*) into mismatch_count
  from pg_proc p
  where p.pronamespace='api'::regnamespace
    and (p.oid not in (
      'api.has_property_capability(uuid,text)'::regprocedure,
      'api.read_current_reservation(uuid)'::regprocedure,
      'api.list_visible_property_summaries(uuid,integer)'::regprocedure,
      'api.list_current_reservation_summaries(uuid,text,uuid,integer)'::regprocedure,
      'api.list_current_manual_blocks(uuid,date,date,uuid,integer)'::regprocedure,
      'api.list_property_contact_summaries(uuid,uuid,integer)'::regprocedure,
      'api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)'::regprocedure,
      'api.is_my_session_active()'::regprocedure,
      'api.revoke_my_sessions()'::regprocedure,
      'api.create_property(text,text,text)'::regprocedure,
      'api.get_inventory(uuid)'::regprocedure,
      'api.create_room(uuid,text,integer)'::regprocedure,
      'api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[])'::regprocedure,
      'api.apply_inventory_template(uuid,text,text)'::regprocedure,
      'api.create_manager_invite(uuid,text,uuid[],text,text)'::regprocedure,
      'api.accept_manager_invite(text)'::regprocedure,
      'api.create_reservation(jsonb,text)'::regprocedure,
      'api.transition_task(uuid,integer,text,text,text,text,uuid[],text)'::regprocedure,
      'api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)'::regprocedure)
      or p.prokind <> 'f'
      or (p.oid = 'api.is_my_session_active()'::regprocedure and p.proowner <> 'app_session_reader'::regrole)
      or (p.oid = 'api.revoke_my_sessions()'::regprocedure and p.proowner <> 'app_executor'::regrole)
      or (p.oid not in ('api.is_my_session_active()'::regprocedure,'api.revoke_my_sessions()'::regprocedure)
          and p.proowner <> 'app_executor'::regrole)
      or not p.prosecdef
      or (p.oid not in ('api.revoke_my_sessions()'::regprocedure,
                        'api.create_property(text,text,text)'::regprocedure,
                        'api.create_room(uuid,text,integer)'::regprocedure,
                        'api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[])'::regprocedure,
                        'api.apply_inventory_template(uuid,text,text)'::regprocedure,
                        'api.create_manager_invite(uuid,text,uuid[],text,text)'::regprocedure,
                        'api.accept_manager_invite(text)'::regprocedure,
                        'api.create_reservation(jsonb,text)'::regprocedure,
      'api.transition_task(uuid,integer,text,text,text,text,uuid[],text)'::regprocedure,
      'api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)'::regprocedure)
          and p.provolatile <> 's')
      or (p.oid in ('api.revoke_my_sessions()'::regprocedure,
                    'api.create_property(text,text,text)'::regprocedure,
                    'api.create_room(uuid,text,integer)'::regprocedure,
                    'api.create_inventory_item(uuid,uuid,text,numeric,text,text,numeric,bigint,date,date,text,text,text,uuid[])'::regprocedure,
                    'api.apply_inventory_template(uuid,text,text)'::regprocedure,
                    'api.create_manager_invite(uuid,text,uuid[],text,text)'::regprocedure,
                    'api.accept_manager_invite(text)'::regprocedure,
                    'api.create_reservation(jsonb,text)'::regprocedure,
      'api.transition_task(uuid,integer,text,text,text,text,uuid[],text)'::regprocedure,
      'api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)'::regprocedure)
          and p.provolatile <> 'v')
      or not (coalesce(p.proconfig, array[]::text[]) @> array['search_path=""']::text[])
      or has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('service_role',p.oid,'EXECUTE') is distinct from
        (p.oid in ('api.transition_task(uuid,integer,text,text,text,text,uuid[],text)'::regprocedure,
                   'api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)'::regprocedure))
      or has_function_privilege('authenticated',p.oid,'EXECUTE') is distinct from
        (p.oid<>'api.finalize_media_upload_for_server(uuid,uuid,text,bigint,integer,text,text)'::regprocedure));
  if mismatch_count <> 0 then
    raise exception 'unsafe or unexpected api function: %', mismatch_count;
  end if;

  select count(*) into mismatch_count
  from pg_proc p
  where p.pronamespace='api'::regnamespace;
  if mismatch_count <> 19 then
    raise exception 'api RPC inventory changed: %', mismatch_count;
  end if;

  select count(*) into mismatch_count
  from pg_class c
  where c.relnamespace='api'::regnamespace;
  if mismatch_count <> 0 then
    raise exception 'api schema unexpectedly contains relation: %', mismatch_count;
  end if;
end $$;
