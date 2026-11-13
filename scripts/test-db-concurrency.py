#!/usr/bin/env python3
"""Exercise the occupancy exclusion constraint with overlapping DB transactions."""

from __future__ import annotations

import os
import selectors
import shutil
import subprocess
import sys
import time
import uuid


def psql_args() -> list[str]:
    target = (
        "host=localhost hostaddr=127.0.0.1 port=5432 "
        "dbname=eve_schema_test user=postgres password=local_schema_test_only"
    )
    return ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-At", f"--dbname={target}"]


def psql(sql: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(psql_args(), input=sql, text=True, capture_output=True, timeout=20)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result


def wait_for_lock_waiters(match_value: str, expected: int) -> None:
    deadline = time.monotonic() + 10
    escaped = match_value.replace("'", "''")
    while time.monotonic() < deadline:
        waiting = psql(
            "select count(*) from pg_stat_activity "
            "where datname=current_database() and pid<>pg_backend_pid() "
            "and wait_event_type='Lock' and query like "
            f"'%{escaped}%';"
        ).stdout.strip()
        if int(waiting) >= expected:
            return
        time.sleep(0.05)
    raise RuntimeError(f"{expected} transactions did not reach the property lock wait")


def wait_for_marker(stream, marker: str, timeout: float = 10) -> tuple[bool, str]:
    deadline = time.monotonic() + timeout
    output = ""
    with selectors.DefaultSelector() as selector:
        selector.register(stream.fileno(), selectors.EVENT_READ)
        while time.monotonic() < deadline:
            events = selector.select(timeout=max(0, deadline - time.monotonic()))
            if not events:
                break
            chunk = os.read(stream.fileno(), 4096).decode()
            if not chunk:
                break
            output += chunk
            if marker in output:
                return True, output
    return False, output


def run_parallel_booking_block_race(
    account: str,
    owner_user: str,
    property_id: str,
    block_id: str,
    block_occupancy_id: str,
    candidates: list[tuple[str, str, str, str]],
) -> None:
    """Race a manual block against one hold and one confirmed reservation."""
    winner_sql = f"""
begin;
select id from app_private.properties where id='{property_id}' for update;
insert into app_private.manual_blocks(id,owner_account_id,property_id,check_in,check_out)
values ('{block_id}','{account}','{property_id}','2040-04-01','2040-04-04');
insert into app_private.occupancy(id,owner_account_id,property_id,manual_block_id,date_range)
values ('{block_occupancy_id}','{account}','{property_id}','{block_id}',daterange('2040-04-01','2040-04-04','[)'));
\\echo WINNER_INSERTED
"""
    winner = subprocess.Popen(
        psql_args(),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert winner.stdin and winner.stdout and winner.stderr
    losers: list[subprocess.Popen[str]] = []
    try:
        winner.stdin.write(winner_sql)
        winner.stdin.flush()
        marker_seen, marker_output = wait_for_marker(winner.stdout, "WINNER_INSERTED")
        if not marker_seen:
            raise RuntimeError(
                "winner transaction did not reach its uncommitted insert: "
                f"{marker_output.strip()}"
            )

        for reservation_id, placement_id, occupancy_id, state in candidates:
            expiry = "statement_timestamp()+interval '1 hour'" if state == "hold" else "null"
            loser_sql = f"""
begin;
select id from app_private.properties where id='{property_id}' for update;
set constraints all deferred;
insert into app_private.reservations(
 id,owner_account_id,property_id,current_placement_id,guest_name,
 check_in,check_out,check_in_time,check_out_time,state,hold_expires_at,total_minor
) values ('{reservation_id}','{account}','{property_id}','{placement_id}',
 'Parallel {state}','2040-04-02','2040-04-05','14:00','12:00','{state}',{expiry},100);
insert into app_private.reservation_placements(
 id,owner_account_id,property_id,reservation_id,placement_no,
 check_in_snapshot,check_out_snapshot,effective_from,created_by
) values ('{placement_id}','{account}','{property_id}','{reservation_id}',1,
 '2040-04-02','2040-04-05',now(),'{owner_user}');
insert into app_private.occupancy(id,owner_account_id,property_id,placement_id,date_range,expires_at)
values ('{occupancy_id}','{account}','{property_id}','{placement_id}',
 daterange('2040-04-02','2040-04-05','[)'),{expiry});
commit;
"""
            loser = subprocess.Popen(
                psql_args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, bufsize=1,
            )
            assert loser.stdin
            losers.append(loser)
            loser.stdin.write(loser_sql)
            loser.stdin.close()

        wait_for_lock_waiters(property_id, len(candidates))
        winner.stdin.write("commit;\n")
        winner.stdin.close()

        winner_stdout = winner.stdout.read()
        winner_stderr = winner.stderr.read()
        winner_code = winner.wait(timeout=20)

        if winner_code != 0:
            raise RuntimeError(f"first transaction failed: {winner_stderr.strip()} {winner_stdout.strip()}")
        for loser in losers:
            loser_stdout = loser.stdout.read() if loser.stdout else ""
            loser_stderr = loser.stderr.read() if loser.stderr else ""
            loser_code = loser.wait(timeout=20)
            if loser_code == 0 or "occupancy_no_overlap" not in loser_stderr:
                raise RuntimeError(
                    "overlapping reservation transaction did not fail on occupancy_no_overlap: "
                    f"exit={loser_code}, stdout={loser_stdout.strip()}, stderr={loser_stderr.strip()}"
                )

        count = psql(
            f"select count(*) from app_private.occupancy where property_id='{property_id}' and active "
            "and date_range && daterange('2040-04-01','2040-04-05','[)');"
        ).stdout.strip()
        if count != "1":
            raise RuntimeError(f"expected exactly one committed active occupancy, found {count}")
        for reservation_id, placement_id, _, _ in candidates:
            remaining = psql(
                f"select (select count(*) from app_private.reservations where id='{reservation_id}')||':'||"
                f"(select count(*) from app_private.reservation_placements where id='{placement_id}');"
            ).stdout.strip()
            if remaining != "0:0":
                raise RuntimeError(f"losing booking left reservation/placement rows: {remaining}")
    finally:
        for loser in losers:
            if loser.poll() is None:
                loser.terminate()
                try:
                    loser.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    loser.kill()
                    loser.wait(timeout=3)
        if winner.poll() is None:
            winner.terminate()
            try:
                winner.wait(timeout=3)
            except subprocess.TimeoutExpired:
                winner.kill()
                winner.wait(timeout=3)


def run_delayed_expiry_catchup(
    owner_user: str,
    property_id: str,
    expired_reservation: str,
    replacement_reservation: str,
    replacement_placement: str,
    replacement_occupancy: str,
) -> None:
    """A delayed background pass cannot keep an expired hold blocking a write."""
    delayed_job_sql = f"""
begin;
select id from app_private.properties where id='{property_id}' for update;
\\echo DELAYED_JOB_LOCKED
"""
    delayed_job = subprocess.Popen(
        psql_args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, bufsize=1,
    )
    assert delayed_job.stdin and delayed_job.stdout and delayed_job.stderr
    try:
        delayed_job.stdin.write(delayed_job_sql)
        delayed_job.stdin.flush()
        marker_seen, marker_output = wait_for_marker(delayed_job.stdout, "DELAYED_JOB_LOCKED")
        if not marker_seen:
            delayed_job.terminate()
            try:
                delayed_job.wait(timeout=3)
            except subprocess.TimeoutExpired:
                delayed_job.kill()
                delayed_job.wait(timeout=3)
            detail = delayed_job.stderr.read() if delayed_job.stderr else ""
            output = delayed_job.stdout.read() if delayed_job.stdout else ""
            raise RuntimeError(
                "delayed job fixture did not acquire its property lock: "
                f"exit={delayed_job.returncode}, stdout={(marker_output + output).strip()}, stderr={detail.strip()}"
            )

        booking_sql = f"""
begin;
select id from app_private.properties where id='{property_id}' for update;
set local request.jwt.claim.sub = '{owner_user}';
select app_private.expire_property_holds('{property_id}');
set constraints all deferred;
insert into app_private.reservations(
 id,owner_account_id,property_id,current_placement_id,guest_name,
 check_in,check_out,check_in_time,check_out_time,state,hold_expires_at,total_minor
) select '{replacement_reservation}',r.owner_account_id,r.property_id,'{replacement_placement}',
 'Post-expiry reservation','2040-06-01','2040-06-03','14:00','12:00','confirmed',null,100
 from app_private.reservations r where r.id='{expired_reservation}';
insert into app_private.reservation_placements(
 id,owner_account_id,property_id,reservation_id,placement_no,
 check_in_snapshot,check_out_snapshot,effective_from,created_by
) select '{replacement_placement}',r.owner_account_id,r.property_id,r.id,2,
 '2040-06-01','2040-06-03',now(),'{owner_user}'
 from app_private.reservations r where r.id='{replacement_reservation}';
insert into app_private.occupancy(id,owner_account_id,property_id,placement_id,date_range)
select '{replacement_occupancy}',r.owner_account_id,r.property_id,'{replacement_placement}',
 daterange('2040-06-01','2040-06-03','[)')
from app_private.reservations r where r.id='{replacement_reservation}';
commit;
"""
        booking = subprocess.Popen(
            psql_args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        assert booking.stdin
        booking.stdin.write(booking_sql)
        booking.stdin.close()
        wait_for_lock_waiters(property_id, 1)
        delayed_job.stdin.write("commit;\n")
        delayed_job.stdin.close()
        booking_stdout = booking.stdout.read() if booking.stdout else ""
        booking_stderr = booking.stderr.read() if booking.stderr else ""
        booking_code = booking.wait(timeout=20)
        delayed_stdout = delayed_job.stdout.read()
        delayed_stderr = delayed_job.stderr.read()
        delayed_code = delayed_job.wait(timeout=20)
        if delayed_code != 0:
            raise RuntimeError(f"delayed-job fixture failed: {delayed_stderr.strip()} {delayed_stdout.strip()}")
        if booking_code != 0:
            raise RuntimeError(f"post-expiry booking transaction failed: {booking_stderr.strip()} {booking_stdout.strip()}")

        state = psql(
            f"select (select state from app_private.reservations where id='{expired_reservation}')||':'||"
            f"(select active::text from app_private.occupancy where placement_id=(select current_placement_id "
            f"from app_private.reservations where id='{expired_reservation}'))||':'||"
            f"(select state from app_private.reservations where id='{replacement_reservation}')||':'||"
            f"(select count(*) from app_private.occupancy where property_id='{property_id}' "
            f"and date_range && daterange('2040-06-01','2040-06-03','[)') and active);"
        ).stdout.strip()
        if state != "cancelled:false:confirmed:1":
            raise RuntimeError(f"expiry catch-up/replacement invariant mismatch: {state}")
        retry = psql(
            f"begin; set local request.jwt.claim.sub='{owner_user}'; "
            f"select app_private.expire_property_holds('{property_id}'); commit;"
        ).stdout.strip().splitlines()
        if retry[-1:] != ["0"]:
            raise RuntimeError(f"repeated expiry catch-up was not idempotent: {retry}")
    finally:
        if "booking" in locals() and booking.poll() is None:
            booking.terminate()
            try:
                booking.wait(timeout=3)
            except subprocess.TimeoutExpired:
                booking.kill()
                booking.wait(timeout=3)
        if delayed_job.poll() is None:
            delayed_job.terminate()
            try:
                delayed_job.wait(timeout=3)
            except subprocess.TimeoutExpired:
                delayed_job.kill()
                delayed_job.wait(timeout=3)


def run_first_trial_race(owner_user: str) -> None:
    winner_sql = f"""
begin;
set local role authenticated;
set local request.jwt.claim.sub = '{owner_user}';
select id from api.create_property('Trial race winner','Synthetic') \\gset
\\echo TRIAL_WINNER_CREATED
"""
    winner = subprocess.Popen(
        psql_args(),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert winner.stdin and winner.stdout and winner.stderr
    loser: subprocess.Popen[str] | None = None
    try:
        winner.stdin.write(winner_sql)
        winner.stdin.flush()
        marker_seen, marker_output = wait_for_marker(winner.stdout, "TRIAL_WINNER_CREATED")
        if not marker_seen:
            raise RuntimeError(
                "first property transaction did not reach its uncommitted create: "
                f"{marker_output.strip()}"
            )

        loser_sql = f"""
begin;
set local role authenticated;
set local request.jwt.claim.sub = '{owner_user}';
select subscription_state from api.create_property('Trial race loser','Synthetic');
commit;
"""
        loser = subprocess.Popen(
            psql_args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        assert loser.stdin
        loser.stdin.write(loser_sql)
        loser.stdin.close()
        wait_for_lock_waiters("create_property('Trial race loser'", 1)
        winner.stdin.write("commit;\n")
        winner.stdin.close()
        winner_stdout = winner.stdout.read()
        winner_stderr = winner.stderr.read()
        winner_code = winner.wait(timeout=20)
        loser_stdout = loser.stdout.read() if loser.stdout else ""
        loser_stderr = loser.stderr.read() if loser.stderr else ""
        loser_code = loser.wait(timeout=20)
        if winner_code != 0:
            raise RuntimeError(f"first trial transaction failed: {winner_stderr.strip()} {winner_stdout.strip()}")
        if loser_code != 0 or loser_stdout.strip().splitlines() != ["draft"]:
            raise RuntimeError(
                "second locked property transaction did not remain draft: "
                f"exit={loser_code}, stdout={loser_stdout.strip()}, stderr={loser_stderr.strip()}"
            )

        result = psql(
            f"select count(*)||':'||count(*) filter (where state='trialing')||':'||"
            f"count(*) filter (where state='draft') from app_private.subscriptions s "
            f"join app_private.owner_accounts a on a.id=s.owner_account_id "
            f"where a.owner_user_id='{owner_user}';"
        ).stdout.strip()
        claims = psql(
            f"select count(*) from app_private.trial_claims t "
            f"join app_private.owner_accounts a on a.id=t.owner_account_id "
            f"where a.owner_user_id='{owner_user}';"
        ).stdout.strip()
        if result != "2:1:1" or claims != "1":
            raise RuntimeError(f"first-trial race invariant mismatch: subscriptions={result}, claims={claims}")
    finally:
        if loser is not None and loser.poll() is None:
            loser.terminate()
            try:
                loser.wait(timeout=3)
            except subprocess.TimeoutExpired:
                loser.kill()
                loser.wait(timeout=3)
        if winner.poll() is None:
            winner.terminate()
            try:
                winner.wait(timeout=3)
            except subprocess.TimeoutExpired:
                winner.kill()
                winner.wait(timeout=3)


def main() -> int:
    if not shutil.which("psql"):
        print("psql is required", file=sys.stderr)
        return 2
    if (
        os.environ.get("EVE_TEST_DATABASE") != "1"
        or os.environ.get("PGHOST", "").lower() not in {"localhost", "127.0.0.1", "::1"}
        or os.environ.get("PGDATABASE") != "eve_schema_test"
        or os.environ.get("PGPORT") != "5432"
        or os.environ.get("PGUSER") != "postgres"
        or os.environ.get("PGPASSWORD") != "local_schema_test_only"
        or os.environ.get("PGHOSTADDR")
        or os.environ.get("PGSERVICE")
        or os.environ.get("PGSERVICEFILE")
    ):
        print("refusing to run: target must be the marked localhost eve_schema_test database", file=sys.stderr)
        return 2

    ids = [str(uuid.uuid4()) for _ in range(18)]
    (
        owner_user, account, property_id, block_id, block_occupancy,
        expired_reservation, expired_placement, expired_occupancy,
        hold_reservation, hold_placement, hold_occupancy,
        confirmed_reservation, confirmed_placement, confirmed_occupancy,
        replacement_reservation, replacement_placement, replacement_occupancy,
        trial_owner,
    ) = ids
    setup = f"""
begin;
insert into auth.users(id) values ('{owner_user}'), ('{trial_owner}');
insert into app_private.owner_accounts(id,owner_user_id) values ('{account}','{owner_user}');
insert into app_private.properties(id,owner_account_id,name,area)
values ('{property_id}','{account}','Concurrency fixture','Synthetic');
set constraints all deferred;
insert into app_private.reservations(
 id,owner_account_id,property_id,current_placement_id,guest_name,
 check_in,check_out,check_in_time,check_out_time,state,hold_expires_at,total_minor
) values ('{expired_reservation}','{account}','{property_id}','{expired_placement}',
 'Expired hold fixture','2040-06-01','2040-06-03','14:00','12:00','hold',
 statement_timestamp()-interval '1 hour',100);
insert into app_private.reservation_placements(
 id,owner_account_id,property_id,reservation_id,placement_no,
 check_in_snapshot,check_out_snapshot,effective_from,created_by
) values ('{expired_placement}','{account}','{property_id}','{expired_reservation}',1,
 '2040-06-01','2040-06-03',now(),'{owner_user}');
insert into app_private.occupancy(id,owner_account_id,property_id,placement_id,date_range,expires_at)
values ('{expired_occupancy}','{account}','{property_id}','{expired_placement}',
 daterange('2040-06-01','2040-06-03','[)'),statement_timestamp()-interval '1 hour');
set constraints all immediate;
commit;
"""
    psql(setup)

    cleanup = f"""
begin;
-- This script refuses all targets except the dedicated localhost CI database.
-- Cyclic RESTRICTed reservation/placement FKs require trigger suppression only
-- while these synthetic fixtures are removed.
set local session_replication_role = replica;
delete from app_private.occupancy where property_id='{property_id}';
delete from app_private.audit_events where property_id='{property_id}';
delete from app_private.reservation_placements where reservation_id in (
 '{expired_reservation}','{replacement_reservation}','{hold_reservation}','{confirmed_reservation}');
delete from app_private.reservations where id in (
 '{expired_reservation}','{replacement_reservation}','{hold_reservation}','{confirmed_reservation}');
delete from app_private.manual_blocks where property_id='{property_id}';
delete from app_private.properties where id='{property_id}';
delete from app_private.owner_accounts where id='{account}';
delete from auth.users where id='{owner_user}';
commit;
"""
    try:
        run_parallel_booking_block_race(
            account, owner_user, property_id, block_id, block_occupancy,
            [
                (hold_reservation, hold_placement, hold_occupancy, "hold"),
                (confirmed_reservation, confirmed_placement, confirmed_occupancy, "confirmed"),
            ],
        )
        run_delayed_expiry_catchup(
            owner_user, property_id, expired_reservation, replacement_reservation,
            replacement_placement, replacement_occupancy,
        )
        run_first_trial_race(trial_owner)
    finally:
        psql(cleanup)
        psql(
            f"delete from app_private.subscriptions where owner_account_id in "
            f"(select id from app_private.owner_accounts where owner_user_id='{trial_owner}'); "
            f"delete from app_private.trial_claims where owner_account_id in "
            f"(select id from app_private.owner_accounts where owner_user_id='{trial_owner}'); "
            f"delete from app_private.properties where owner_account_id in "
            f"(select id from app_private.owner_accounts where owner_user_id='{trial_owner}'); "
            f"delete from app_private.owner_accounts where owner_user_id='{trial_owner}'; "
            f"delete from auth.users where id='{trial_owner}';"
        )

    print("PASS occupancy concurrency: manual block wins against parallel hold and booking; both losers roll back")
    print("PASS delayed-expiry catch-up: next booking waits for property lock, expires hold, then commits same interval")
    print("PASS hold-expiry retry: repeated catch-up is idempotent")
    print("PASS first-trial concurrency: 2 concurrent property creates, 1 trial claim, 1 trialing, 1 draft")
    print("LIMIT synthetic PostgreSQL only; no booking-create/idempotency API, public departure query, hosted DB, or production evidence")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as error:
        print(f"FAIL occupancy concurrency: {error}", file=sys.stderr)
        raise SystemExit(1)
