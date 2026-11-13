-- D34: bind the private inventory classification to its own private bucket.
alter table app_private.media_assets drop constraint media_bucket_classification;
alter table app_private.media_assets add constraint media_bucket_classification check (
  (classification='public_property' and bucket='eve-public-property') or
  (classification='public_guide' and bucket='eve-public-guide') or
  (classification='private_guest' and bucket='eve-private-guest') or
  (classification='private_receipt' and bucket='eve-private-receipt') or
  (classification='private_inspection' and bucket='eve-private-inspection') or
  (classification='private_task' and bucket='eve-private-task') or
  (classification='private_inventory' and bucket='eve-private-inventory')
);

create policy eve_inventory_media_direct_deny on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id <> 'eve-private-inventory')
  with check (bucket_id <> 'eve-private-inventory');
