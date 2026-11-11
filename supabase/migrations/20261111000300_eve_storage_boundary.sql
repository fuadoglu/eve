-- EVE-006.2: direct client Storage access is closed until scoped media APIs exist.
-- Bucket provisioning is handled by supabase/config.toml, not by DML on Storage metadata.
-- Public-safe media is still stored in private buckets and served only after a
-- server publish check; private media is served by a per-request scoped proxy.
begin;

do $$
begin
  if to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null then
    raise exception 'Supabase Storage schema is required before EVE storage policy';
  end if;
  if not exists (
    select 1 from pg_class c
    where c.oid='storage.objects'::regclass and c.relrowsecurity
  ) then
    raise exception 'storage.objects RLS must be enabled by Storage';
  end if;
  if exists (
    select 1 from storage.buckets b
    where b.id in (
      'eve-public-property', 'eve-public-guide', 'eve-private-guest',
      'eve-private-receipt', 'eve-private-inspection', 'eve-private-task'
    ) and b.public
  ) then
    raise exception 'Eve media buckets must remain private';
  end if;
end $$;

-- A media row cannot point a classification at another or unrelated bucket.
alter table app_private.media_assets
  add constraint media_bucket_classification
  check (
    (classification='public_property' and bucket='eve-public-property') or
    (classification='public_guide' and bucket='eve-public-guide') or
    (classification='private_guest' and bucket='eve-private-guest') or
    (classification='private_receipt' and bucket='eve-private-receipt') or
    (classification='private_inspection' and bucket='eve-private-inspection') or
    (classification='private_task' and bucket='eve-private-task')
  );

-- RESTRICTIVE makes an existing or future permissive Storage policy unable to
-- expose these bucket rows to anon/authenticated. Service-side bypass still
-- requires an explicit tenant/link check in the API; this policy is not one.
create policy eve_media_direct_client_deny on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id not in (
    'eve-public-property', 'eve-public-guide', 'eve-private-guest',
    'eve-private-receipt', 'eve-private-inspection', 'eve-private-task'
  ))
  with check (bucket_id not in (
    'eve-public-property', 'eve-public-guide', 'eve-private-guest',
    'eve-private-receipt', 'eve-private-inspection', 'eve-private-task'
  ));

commit;
