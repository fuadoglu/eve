-- EVE-008.1 local PostgreSQL/JWT-role smoke; not hosted Data API or production proof.
do $$
begin
  if (select p.proowner <> 'app_executor'::regrole or not p.prosecdef
          or not (coalesce(p.proconfig,array[]::text[]) @> array['search_path=""']::text[])
      from pg_proc p where p.oid='api.create_property(text,text,text)'::regprocedure)
     or has_function_privilege('anon','api.create_property(text,text,text)','EXECUTE')
     or has_table_privilege('authenticated','app_private.properties','INSERT')
     or has_table_privilege('app_executor','app_private.properties','UPDATE')
     or has_table_privilege('app_executor','app_private.properties','DELETE') then
    raise exception 'property create RPC owner/grant boundary is unsafe';
  end if;
end $$;

insert into auth.users(id) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
on conflict (id) do nothing;

begin;
set local request.jwt.claim.sub = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
do $$
declare first_property record; second_property record; third_property record; claim_count integer;
begin
  select * into first_property from api.create_property(' İlk ev ',' Bakı ','villa');
  if first_property.id is null or first_property.name <> ' İlk ev '
     or first_property.area <> ' Bakı ' or first_property.property_type <> 'villa'
     or first_property.permission <> 'owner'
     or first_property.subscription_state <> 'trialing' then
    raise exception 'first property DTO/trial mismatch: %',row_to_json(first_property);
  end if;
  if not exists (select 1 from app_private.trial_claims t
      where t.property_id=first_property.id
        and t.started_at <= clock_timestamp()
        and t.ends_at=t.started_at+interval '7 days') then
    raise exception 'first trial claim is absent or not exactly seven days';
  end if;

  select * into second_property from api.create_property('İkinci ev','Gəncə');
  if second_property.subscription_state <> 'draft'
     or exists (select 1 from app_private.trial_claims t
       where t.property_id=second_property.id) then
    raise exception 'second property incorrectly received trial';
  end if;
  select count(*) into claim_count from app_private.trial_claims
    where owner_account_id=first_property.owner_account_id;
  if claim_count <> 1 then raise exception 'owner has % trial claims',claim_count; end if;

  update app_private.properties set archived_at=clock_timestamp() where id=first_property.id;
  select * into third_property from api.create_property('Arxivdən sonra','Bakı');
  if third_property.subscription_state <> 'draft'
     or not exists (select 1 from app_private.trial_claims t
        where t.owner_account_id=first_property.owner_account_id
          and t.property_id=first_property.id) then
    raise exception 'archive incorrectly restored first-trial eligibility';
  end if;
  begin
    delete from app_private.properties where id=first_property.id;
    raise exception 'property with a trial claim was deleted';
  exception when foreign_key_violation then null;
  end;

  begin
    perform * from api.create_property('   ','Sumqayıt');
    raise exception 'blank property name accepted';
  exception when invalid_parameter_value then null;
  end;
  if (select count(*) from app_private.properties
      where owner_account_id=first_property.owner_account_id) <> 3 then
    raise exception 'invalid property create left partial data';
  end if;

end $$;
rollback;

begin;
set local role authenticated;
set local request.jwt.claim.sub = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
do $$
begin
  perform * from api.create_property('Scoped owner','Bakı');
  begin
    execute 'select id from app_private.properties limit 1';
    raise exception 'authenticated direct base-table read unexpectedly worked';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;

delete from auth.users
where id in ('dddddddd-dddd-dddd-dddd-dddddddddddd',
             'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');

begin;
set local role authenticated;
set local request.jwt.claim.sub = '';
do $$
begin
  begin
    perform * from api.create_property('Anon','Bakı');
    raise exception 'unauthenticated property create accepted';
  exception when sqlstate '28000' then null;
  end;
end $$;
rollback;
