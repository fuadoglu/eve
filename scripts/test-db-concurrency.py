#!/usr/bin/env python3
"""Exercise the occupancy exclusion constraint with overlapping DB transactions."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
import uuid


def psql(sql: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    command = ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-At"]
    result = subprocess.run(command, input=sql, text=True, capture_output=True, timeout=20)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result


def run_race(account: str, property_id: str, block_a: str, block_b: str, occupancy_a: str, occupancy_b: str) -> None:
    winner_sql = f"""
begin;
insert into app_private.occupancy(id,owner_account_id,property_id,manual_block_id,date_range)
values ('{occupancy_a}','{account}','{property_id}','{block_a}',daterange('2040-04-01','2040-04-04','[)'));
\\echo WINNER_INSERTED
select pg_sleep(1.5);
commit;
"""
    winner = subprocess.Popen(
        ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-At"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert winner.stdin and winner.stdout and winner.stderr
    try:
        winner.stdin.write(winner_sql)
        winner.stdin.close()
        marker_seen = False
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            line = winner.stdout.readline()
            if not line:
                break
            if "WINNER_INSERTED" in line:
                marker_seen = True
                break
        if not marker_seen:
            raise RuntimeError("winner transaction did not reach its uncommitted insert")

        loser_sql = f"""
begin;
insert into app_private.occupancy(id,owner_account_id,property_id,manual_block_id,date_range)
values ('{occupancy_b}','{account}','{property_id}','{block_b}',daterange('2040-04-02','2040-04-05','[)'));
commit;
"""
        loser = subprocess.run(
            ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-At"],
            input=loser_sql,
            text=True,
            capture_output=True,
            timeout=20,
        )
        winner_stdout = winner.stdout.read()
        winner_stderr = winner.stderr.read()
        winner_code = winner.wait(timeout=20)

        if winner_code != 0:
            raise RuntimeError(f"first transaction failed: {winner_stderr.strip()} {winner_stdout.strip()}")
        if loser.returncode == 0 or "occupancy_no_overlap" not in loser.stderr:
            raise RuntimeError(
                "overlapping transaction did not fail on occupancy_no_overlap: "
                f"exit={loser.returncode}, stderr={loser.stderr.strip()}"
            )

        count = psql(
            f"select count(*) from app_private.occupancy where property_id='{property_id}' and active;"
        ).stdout.strip()
        if count != "1":
            raise RuntimeError(f"expected exactly one committed active occupancy, found {count}")
    finally:
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
    ):
        print("refusing to run: target must be the marked localhost eve_schema_test database", file=sys.stderr)
        return 2

    ids = [str(uuid.uuid4()) for _ in range(6)]
    owner_user, account, property_id, block_a, block_b, occupancy_a = ids
    occupancy_b = str(uuid.uuid4())
    setup = f"""
begin;
insert into auth.users(id) values ('{owner_user}');
insert into app_private.owner_accounts(id,owner_user_id) values ('{account}','{owner_user}');
insert into app_private.properties(id,owner_account_id,name,area)
values ('{property_id}','{account}','Concurrency fixture','Synthetic');
insert into app_private.manual_blocks(id,owner_account_id,property_id,check_in,check_out)
values ('{block_a}','{account}','{property_id}','2040-04-01','2040-04-04'),
       ('{block_b}','{account}','{property_id}','2040-04-02','2040-04-05');
commit;
"""
    psql(setup)

    cleanup = f"""
delete from app_private.occupancy where property_id='{property_id}';
delete from app_private.manual_blocks where property_id='{property_id}';
delete from app_private.properties where id='{property_id}';
delete from app_private.owner_accounts where id='{account}';
delete from auth.users where id='{owner_user}';
"""
    try:
        run_race(account, property_id, block_a, block_b, occupancy_a, occupancy_b)
    finally:
        psql(cleanup, check=False)

    print("PASS occupancy concurrency: 2 concurrent transactions, 1 commit, 1 exclusion_violation, 1 active row")
    print("LIMIT synthetic local PostgreSQL only; not booking API, hosted DB, or production evidence")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as error:
        print(f"FAIL occupancy concurrency: {error}", file=sys.stderr)
        raise SystemExit(1)
