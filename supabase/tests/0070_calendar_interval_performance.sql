-- EVE-013.3 bounded interval-query p95 budget; synthetic PostgreSQL 17 data only.
begin;
set constraints all deferred;

insert into auth.users(id) values ('f9700000-0000-0000-0000-000000000001');
insert into auth.sessions(id,user_id,created_at) values
  ('f9710000-0000-0000-0000-000000000001','f9700000-0000-0000-0000-000000000001',now());
insert into app_private.owner_accounts(id,owner_user_id) values
  ('f9720000-0000-0000-0000-000000000001','f9700000-0000-0000-0000-000000000001');
insert into app_private.properties(id,owner_account_id,name,area) values
  ('f9730000-0000-4000-8000-000000000001','f9720000-0000-0000-0000-000000000001','Calendar performance fixture','Baku');

create temporary table eve_calendar_perf_fixture (
  reservation_id uuid primary key,
  placement_id uuid unique not null,
  ordinal integer not null,
  check_in date not null
) on commit drop;

insert into eve_calendar_perf_fixture(reservation_id,placement_id,ordinal,check_in)
select gen_random_uuid(),gen_random_uuid(),n,date '2099-01-01'+(n-1)
from generate_series(1,5000) n;

insert into app_private.reservations(
  id,owner_account_id,property_id,current_placement_id,guest_name,check_in,check_out,
  check_in_time,check_out_time,guest_count,state,total_minor
)
select f.reservation_id,'f9720000-0000-0000-0000-000000000001',
  'f9730000-0000-4000-8000-000000000001',f.placement_id,'Synthetic calendar guest',
  f.check_in,f.check_in+1,'15:00','11:00',1,'confirmed',10000
from eve_calendar_perf_fixture f;

insert into app_private.reservation_placements(
  id,owner_account_id,property_id,reservation_id,placement_no,
  check_in_snapshot,check_out_snapshot,effective_from,created_by
)
select f.placement_id,'f9720000-0000-0000-0000-000000000001',
  'f9730000-0000-4000-8000-000000000001',f.reservation_id,1,
  f.check_in,f.check_in+1,now(),'f9700000-0000-0000-0000-000000000001'
from eve_calendar_perf_fixture f;

insert into app_private.occupancy(owner_account_id,property_id,placement_id,date_range)
select 'f9720000-0000-0000-0000-000000000001',
  'f9730000-0000-4000-8000-000000000001',f.placement_id,
  daterange(f.check_in,f.check_in+1,'[)')
from eve_calendar_perf_fixture f;

analyze app_private.reservations;
analyze app_private.reservation_placements;
analyze app_private.rent_entries;
set local role authenticated;
set local request.jwt.claims = '{"sub":"f9700000-0000-0000-0000-000000000001","session_id":"f9710000-0000-0000-0000-000000000001","iat":1800000000}';

do $$
declare
  i integer;
  v_samples double precision[] := array[]::double precision[];
  v_started timestamptz;
  v_result jsonb;
  v_p95_ms double precision;
begin
  for i in 1..30 loop
    v_started := clock_timestamp();
    v_result := api.get_calendar('2099-06-01','2099-07-01',
      array['f9730000-0000-4000-8000-000000000001']::uuid[]);
    v_samples := array_append(v_samples,
      extract(epoch from clock_timestamp()-v_started)*1000);
    if jsonb_array_length(v_result->'reservations')<>30
       or jsonb_array_length(v_result->'blocks')<>0 then
      raise exception 'bounded calendar query returned an unexpected interval result';
    end if;
  end loop;

  select percentile_cont(0.95) within group (order by sample.value)
    into v_p95_ms from unnest(v_samples) as sample(value);
  raise notice 'EVE-013.3 synthetic calendar RPC: 5000 stored reservations, 30 interval rows, 30 samples, p95=% ms',round(v_p95_ms::numeric,2);
  if v_p95_ms>500 then
    raise exception 'calendar RPC p95 % ms exceeds PRD read target 500 ms',round(v_p95_ms::numeric,2);
  end if;
end $$;

rollback;
