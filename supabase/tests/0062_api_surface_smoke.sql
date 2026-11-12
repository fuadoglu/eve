-- EVE-006.2: only the reviewed read/capability RPCs can cross the Data API schema.
do $$
declare
  mismatch_count integer;
begin
  if not has_schema_privilege('authenticated','api','USAGE')
     or has_schema_privilege('anon','api','USAGE') then
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
      'api.list_reservation_rent_summaries(uuid,timestamptz,uuid,integer)'::regprocedure)
      or p.prokind <> 'f'
      or p.proowner <> 'app_executor'::regrole
      or not p.prosecdef
      or p.provolatile <> 's'
      or not (coalesce(p.proconfig, array[]::text[]) @> array['search_path=']::text[])
      or has_function_privilege('anon',p.oid,'EXECUTE')
      or not has_function_privilege('authenticated',p.oid,'EXECUTE'));
  if mismatch_count <> 0 then
    raise exception 'unsafe or unexpected api function: %', mismatch_count;
  end if;

  select count(*) into mismatch_count
  from pg_proc p
  where p.pronamespace='api'::regnamespace;
  if mismatch_count <> 7 then
    raise exception 'api RPC inventory changed: %', mismatch_count;
  end if;

  select count(*) into mismatch_count
  from pg_class c
  where c.relnamespace='api'::regnamespace;
  if mismatch_count <> 0 then
    raise exception 'api schema unexpectedly contains relation: %', mismatch_count;
  end if;
end $$;
