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
    and (p.proname not in (
      'has_property_capability', 'read_current_reservation',
      'list_visible_property_summaries', 'list_current_reservation_summaries',
      'list_current_manual_blocks', 'list_property_contact_summaries',
      'list_reservation_rent_summaries')
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
