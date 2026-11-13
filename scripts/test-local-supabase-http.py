#!/usr/bin/env python3
"""EVE-006.2 local-only Data API and Storage negative acceptance checks.

Run on a fresh local Supabase stack after 0062_rent_read_smoke.sql. The fixture
contains synthetic A/B owners and daily/full managers. This script never prints
JWTs, signing material, or raw API responses.
"""

import base64
import atexit
import hashlib
import hmac
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid


API = "http://127.0.0.1:54321"
OWNER_A = "e1000000-0000-0000-0000-000000000001"
OWNER_B = "e1000000-0000-0000-0000-000000000002"
MANAGER = "e1000000-0000-0000-0000-000000000003"
TARGET_DAILY = "e1000000-0000-0000-0000-000000000005"
PROPERTY_A1 = "e2100000-0000-0000-0000-000000000001"
PROPERTY_A2 = "e2100000-0000-0000-0000-000000000002"
PROPERTY_B1 = "e2100000-0000-0000-0000-000000000003"
RESERVATION_A = "e3100000-0000-0000-0000-000000000001"
RESERVATION_B = "e3100000-0000-0000-0000-000000000002"
OWNER_ACCOUNT_A = "e1100000-0000-0000-0000-000000000001"
OWNER_ACCOUNT_B = "e1100000-0000-0000-0000-000000000002"
RENT_COLUMNS = {
    "entry_id", "reservation_id", "property_id", "placement_id", "kind",
    "amount_minor", "custodian", "occurred_at", "created_at",
}
ENTRY_A_TARGET = "e5100000-0000-0000-0000-000000000004"
ENTRY_B = "e5100000-0000-0000-0000-000000000003"
ASSERTIONS = 0


def assert_local_docker():
    host_override = os.environ.get("DOCKER_HOST", "")
    context = json.loads(subprocess.check_output(
        ["docker", "context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"],
        stderr=subprocess.DEVNULL,
    ))
    if not context.startswith("unix://") or (host_override and not host_override.startswith("unix://")):
        raise RuntimeError("local Unix Docker context required")


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


def local_signing_key():
    container = json.loads(subprocess.check_output(
        ["docker", "inspect", "supabase_rest_eve"], stderr=subprocess.DEVNULL
    ))[0]
    env = container["Config"]["Env"]
    value = next(item.split("=", 1)[1] for item in env
                 if item.startswith("PGRST_JWT_SECRET="))
    keys = json.loads(value)["keys"]
    encoded = next(item["k"] for item in keys if item["kty"] == "oct")
    return base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))


def jwt(actor, key, role="authenticated", issued_at=None, session_id=None):
    def part(value):
        return b64(json.dumps(value, separators=(",", ":")).encode())

    issued_at = int(time.time()) if issued_at is None else issued_at
    signed = part({"alg": "HS256", "typ": "JWT"}) + b"." + part({
        "role": role, "sub": actor, "aud": "authenticated",
        "iat": issued_at, "exp": max(int(time.time()) + 300, issued_at + 300),
        "session_id": session_id or str(uuid.uuid4()),
    })
    return (signed + b"." + b64(hmac.new(key, signed, hashlib.sha256).digest())).decode()


def request(path, *, actor=None, key=None, role="authenticated", bearer=None,
            payload=None, method=None, headers=None):
    request_headers = dict(headers or {})
    if bearer:
        request_headers["Authorization"] = "Bearer " + bearer
    elif actor:
        request_headers["Authorization"] = "Bearer " + jwt(actor, key, role)
    body = json.dumps(payload).encode() if isinstance(payload, dict) else payload
    if isinstance(payload, dict):
        request_headers["Content-Type"] = "application/json"
    call = urllib.request.Request(API + path, data=body, headers=request_headers,
                                  method=method or ("POST" if body is not None else "GET"))
    try:
        with urllib.request.urlopen(call, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def sql(statement):
    subprocess.run(
        ["docker", "exec", "-i", "supabase_db_eve", "psql", "-U",
         "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
        input=statement.encode(), check=True, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def verify(name, condition, detail):
    global ASSERTIONS
    if not condition:
        raise AssertionError(name + ": " + detail)
    ASSERTIONS += 1
    print("PASS " + name)


def safe_error_detail(status, data):
    error = data[0] if isinstance(data, list) and data else data
    if isinstance(error, dict):
        return f"{status}:{error.get('code', '')}:{error.get('message', '')}"
    return f"{status}:{type(data).__name__}:{str(data)[:160]}"


def rpc(name, actor, key, arguments, *, role="authenticated", bearer=None):
    status, body = request("/rest/v1/rpc/" + name, actor=actor, key=key,
                           role=role, bearer=bearer, payload=arguments)
    return status, json.loads(body)


def main():
    assert_local_docker()
    key = local_signing_key()
    session_a, session_b = str(uuid.uuid4()), str(uuid.uuid4())
    session_a_id, session_b_id, session_a_fresh_id = (str(uuid.uuid4()) for _ in range(3))
    sql(f"insert into auth.users(id) values ('{session_a}'),('{session_b}');")
    sql(f"insert into auth.sessions(id,user_id,created_at) values ('{session_a_id}','{session_a}',now()),('{session_b_id}','{session_b}',now());")
    old_session_token = jwt(session_a, key, session_id=session_a_id)
    try:
        status, data = rpc("is_my_session_active", session_a, key, {}, bearer=old_session_token)
        verify("session new user without profile active", status == 200 and data is True,
               safe_error_detail(status, data))
        status, data = rpc("revoke_my_sessions", session_a, key, {})
        verify("session logout-all cutoff recorded", status == 200 and data is True,
               str(status))
        status, data = rpc("is_my_session_active", session_a, key, {}, bearer=old_session_token)
        verify("session pre-cutoff token denied", status == 200 and data is False,
               str(status))
        refreshed_old_session = jwt(session_a, key, issued_at=int(time.time()) + 30,
                                    session_id=session_a_id)
        status, data = rpc("is_my_session_active", session_a, key, {},
                           bearer=refreshed_old_session)
        verify("session refreshed old session remains denied", status == 200 and data is False,
               str(status))
        time.sleep(0.05)
        sql(f"insert into auth.sessions(id,user_id,created_at) values ('{session_a_fresh_id}','{session_a}',now() + interval '1 second');")
        status, data = rpc("is_my_session_active", session_a, key, {},
                           bearer=jwt(session_a, key, session_id=session_a_fresh_id))
        verify("session post-cutoff login active", status == 200 and data is True,
               str(status))
        status, data = rpc("is_my_session_active", session_b, key, {},
                           bearer=jwt(session_b, key, session_id=session_b_id))
        verify("session logout-all tenant isolation", status == 200 and data is True,
               str(status))
        status, data = rpc("revoke_my_sessions", session_a, key, {}, role="anon")
        verify("session anonymous revoke denied", status in (401, 403)
               and isinstance(data, dict) and data.get("code") == "42501", str(status))
    finally:
        sql(f"delete from app_private.profiles where user_id in ('{session_a}','{session_b}'); "
            f"delete from auth.sessions where user_id in ('{session_a}','{session_b}'); "
            f"delete from auth.users where id in ('{session_a}','{session_b}');")

    capability = lambda property_id, name: {
        "p_property_id": property_id, "p_capability": name,
    }
    rent = lambda reservation_id: {"p_reservation_id": reservation_id}

    # These rows exist only in the fresh local Supabase CI stack. Keep their
    # identifiers random so this test remains safe if a developer reruns it.
    block_a, block_b = str(uuid.uuid4()), str(uuid.uuid4())
    contact_a, contact_b = str(uuid.uuid4()), str(uuid.uuid4())
    def cleanup_read_fixtures():
        sql(f"""
          delete from app_private.contact_properties where contact_id in ('{contact_a}','{contact_b}');
          delete from app_private.contacts where id in ('{contact_a}','{contact_b}');
          delete from app_private.manual_blocks where id in ('{block_a}','{block_b}');
        """)

    atexit.register(cleanup_read_fixtures)
    sql(f"""
      insert into app_private.manual_blocks
        (id,owner_account_id,property_id,check_in,check_out,reason)
      values
        ('{block_a}','{OWNER_ACCOUNT_A}','{PROPERTY_A2}','2027-08-01','2027-08-03','Synthetic A block'),
        ('{block_b}','{OWNER_ACCOUNT_B}','{PROPERTY_B1}','2027-08-01','2027-08-03','Synthetic B block');
      insert into app_private.contacts
        (id,owner_account_id,name,phone,service_type,private_note)
      values
        ('{contact_a}','{OWNER_ACCOUNT_A}','Synthetic A contact','+994501234567','cleaner','Synthetic private note A'),
        ('{contact_b}','{OWNER_ACCOUNT_B}','Synthetic B contact','+994501234567','repair','Synthetic private note B');
      insert into app_private.contact_properties(owner_account_id,property_id,contact_id)
      values ('{OWNER_ACCOUNT_A}','{PROPERTY_A2}','{contact_a}'),
             ('{OWNER_ACCOUNT_B}','{PROPERTY_B1}','{contact_b}');
    """)

    status, data = rpc("has_property_capability", OWNER_A, key,
                       capability(PROPERTY_A1, "property.read"))
    verify("AT04 owner own property", status == 200 and data is True, str(status))
    status, data = rpc("has_property_capability", OWNER_B, key,
                       capability(PROPERTY_A1, "property.read"))
    verify("AT04 cross-owner deny", status == 200 and data is False, str(status))
    status, data = rpc("has_property_capability", TARGET_DAILY, key,
                       capability(PROPERTY_A2, "finance.read"))
    verify("AT06 daily tenant finance deny", status == 200 and data is False,
           str(status))

    status, data = rpc("list_reservation_rent_summaries", TARGET_DAILY, key,
                       rent(RESERVATION_A))
    verify("AT06 daily current rent read", status == 200 and len(data) == 1
           and set(data[0]) == RENT_COLUMNS
           and data[0]["entry_id"] == ENTRY_A_TARGET
           and data[0]["property_id"] == PROPERTY_A2
           and data[0]["amount_minor"] == 4000, str(status))
    status, data = rpc("list_reservation_rent_summaries", OWNER_A, key,
                       rent(RESERVATION_A))
    verify("AT06 owner history read", status == 200 and len(data) == 3
           and all(set(row) == RENT_COLUMNS for row in data)
           and {row["amount_minor"] for row in data} == {10000, 5000, 4000},
           str(status))
    status, data = rpc("list_reservation_rent_summaries", OWNER_B, key,
                       rent(RESERVATION_A))
    verify("AT04 other owner rent deny", status == 200 and data == [], str(status))
    status, data = rpc("list_reservation_rent_summaries", MANAGER, key,
                       rent(RESERVATION_B))
    verify("AT04 full manager assigned read", status == 200 and len(data) == 1
           and data[0]["entry_id"] == ENTRY_B
           and data[0]["amount_minor"] == 7000,
           str(status))

    manager_bearer = jwt(MANAGER, key)
    sql("update app_private.property_memberships set revoked_at=null "
        "where property_id='" + PROPERTY_A1 + "' and user_id='" + MANAGER + "';")
    status, data = rpc("has_property_capability", MANAGER, key,
                       capability(PROPERTY_A1, "property.read"), bearer=manager_bearer)
    verify("AT05 manager before revoke", status == 200 and data is True,
           str(status))
    sql("update app_private.property_memberships set revoked_at=now() "
        "where property_id='" + PROPERTY_A1 + "' and user_id='" + MANAGER + "';")
    status, data = rpc("has_property_capability", MANAGER, key,
                       capability(PROPERTY_A1, "property.read"), bearer=manager_bearer)
    verify("AT05 next request revoke", status == 200 and data is False,
           str(status))
    status, data = rpc("list_visible_property_summaries", MANAGER, key,
                       {"p_after_id": None, "p_page_size": 100},
                       bearer=manager_bearer)
    verify("AT05 revoke removes A1 and preserves B1", status == 200
           and {row["property_id"] for row in data} == {PROPERTY_B1}, str(status))

    status, _ = request("/rest/v1/properties", actor=OWNER_A, key=key)
    verify("AT04 direct base table deny", status == 404, str(status))
    status, _ = request("/rest/v1/properties", actor=OWNER_A, key=key,
                        headers={"Accept-Profile": "app_private"})
    verify("AT04 private schema deny", status == 406, str(status))
    status, data = rpc("has_property_capability",
                       "00000000-0000-0000-0000-000000000000", key,
                       capability(PROPERTY_A1, "property.read"), role="anon")
    verify("AT04 signed anon RPC deny", status in (401, 403)
           and data.get("code") == "42501", str(status))

    status, data = rpc("read_current_reservation", OWNER_A, key,
                       {"p_reservation_id": RESERVATION_A})
    verify("AT04 current reservation projection", status == 200 and len(data) == 1
           and data[0]["reservation_id"] == RESERVATION_A
           and data[0]["property_id"] == PROPERTY_A2
           and data[0]["guest_name"] == "Synthetic A guest"
           and set(data[0]) == {"reservation_id", "property_id", "placement_id",
               "guest_name", "guest_phone", "check_in", "check_out", "state",
               "total_minor", "version", "created_at", "updated_at"}, str(status))
    status, data = rpc("read_current_reservation", OWNER_A, key,
                       {"p_reservation_id": RESERVATION_B})
    verify("AT04 reservation IDOR deny", status == 200 and data == [], str(status))

    status, data = rpc("list_visible_property_summaries", OWNER_A, key,
                       {"p_after_id": None, "p_page_size": 100})
    verify("AT04 owner property projection", status == 200 and
           {row["property_id"] for row in data} == {PROPERTY_A1, PROPERTY_A2}
           and all(set(row) == {"property_id", "owner_account_id", "name", "area",
                                "readiness", "version"} for row in data), str(status))
    status, data = rpc("list_visible_property_summaries", OWNER_A, key,
                       {"p_after_id": PROPERTY_A1, "p_page_size": 100})
    verify("AT04 owner cursor page remains tenant-scoped",
           status == 200 and {row["property_id"] for row in data} == {PROPERTY_A2}
           and PROPERTY_B1 not in {row["property_id"] for row in data}, str(status))
    status, _ = request("/rest/v1/rpc/list_visible_property_summaries",
                        actor=OWNER_A, key=key,
                        payload={"p_after_id": None, "p_page_size": 100,
                                 "p_owner_account_id": OWNER_B})
    verify("AT04 unexpected owner override argument rejected",
           status in (400, 404), str(status))
    status, data = rpc("list_visible_property_summaries", MANAGER, key,
                       {"p_after_id": None, "p_page_size": 100})
    verify("AT05 revoked manager property projection", status == 200
           and {row["property_id"] for row in data} == {PROPERTY_B1},
           str(status))

    status, data = rpc("list_current_reservation_summaries", OWNER_A, key,
                       {"p_property_id": PROPERTY_A2, "p_status": None,
                        "p_after_id": None, "p_page_size": 30})
    verify("AT04 current reservation list", status == 200 and len(data) == 1
           and data[0]["reservation_id"] == RESERVATION_A
           and data[0]["placement_id"] == "e4100000-0000-0000-0000-000000000003",
           str(status))
    status, data = rpc("list_current_reservation_summaries", OWNER_B, key,
                       {"p_property_id": PROPERTY_A2, "p_status": None,
                        "p_after_id": None, "p_page_size": 30})
    verify("AT04 cross-owner reservation list deny", status == 200 and data == [],
           str(status))

    status, data = rpc("list_current_manual_blocks", OWNER_A, key,
                       {"p_property_id": PROPERTY_A2, "p_from": "2027-08-01",
                        "p_to": "2027-08-10", "p_after_id": None,
                        "p_page_size": 100})
    verify("AT04 scoped manual block projection", status == 200 and len(data) == 1
           and data[0]["block_id"] == block_a
           and data[0]["reason"] == "Synthetic A block", str(status))
    status, data = rpc("list_current_manual_blocks", OWNER_B, key,
                       {"p_property_id": PROPERTY_A2, "p_from": "2027-08-01",
                        "p_to": "2027-08-10", "p_after_id": None,
                        "p_page_size": 100})
    verify("AT04 cross-owner manual block deny", status == 200 and data == [],
           str(status))

    status, data = rpc("list_property_contact_summaries", OWNER_A, key,
                       {"p_property_id": PROPERTY_A2, "p_after_id": None,
                        "p_page_size": 30})
    verify("AT04 scoped contact projection", status == 200 and len(data) == 1
           and data[0]["contact_id"] == contact_a
           and data[0]["private_note"] == "Synthetic private note A", str(status))
    status, data = rpc("list_property_contact_summaries", OWNER_B, key,
                       {"p_property_id": PROPERTY_A2, "p_after_id": None,
                        "p_page_size": 30})
    verify("AT04 cross-owner contact deny", status == 200 and data == [], str(status))

    buckets = ("eve-public-property", "eve-public-guide", "eve-private-guest",
               "eve-private-receipt", "eve-private-inspection", "eve-private-task")
    try:
        for bucket in buckets:
            name = "local-boundary-" + uuid.uuid4().hex + ".txt"
            object_path = f"/storage/v1/object/{bucket}/{name}"
            status, body = request(object_path, actor=TARGET_DAILY, key=key,
                                   payload=b"synthetic client upload",
                                   headers={"Content-Type": "text/plain"})
            storage_error = json.loads(body)
            verify(f"AT06 {bucket} authenticated upload deny",
                   status == 400 and storage_error.get("code") == "AccessDenied"
                   and storage_error.get("statusCode") == "403", str(status))
            anon_bearer = jwt("00000000-0000-0000-0000-000000000000", key,
                              role="anon")
            status, body = request(object_path, role="anon", key=key,
                                   bearer=anon_bearer,
                                   payload=b"synthetic anon upload",
                                   headers={"Content-Type": "text/plain"})
            storage_error = json.loads(body)
            verify(f"AT06 {bucket} anon upload deny",
                   status == 400 and storage_error.get("code") == "AccessDenied"
                   and storage_error.get("statusCode") == "403", str(status))

            status, _ = request(object_path, actor=TARGET_DAILY, key=key,
                                role="service_role", payload=b"synthetic local proof",
                                headers={"Content-Type": "text/plain"})
            verify(f"AT06 {bucket} local fixture upload", status == 200, str(status))
            try:
                status, body = request(object_path, actor=TARGET_DAILY, key=key,
                                       role="service_role")
                verify(f"AT06 {bucket} fixture object exists", status == 200
                       and body == b"synthetic local proof", str(status))
                for actor, actor_role in ((TARGET_DAILY, "authenticated"),
                                          (None, "anon")):
                    status, body = request(object_path, actor=actor, key=key,
                                           role=actor_role,
                                           bearer=(anon_bearer if actor_role == "anon" else None))
                    storage_error = json.loads(body)
                    verify(f"AT06 {bucket} {actor_role} read deny",
                           status != 200 and storage_error.get("code") == "NoSuchKey",
                           str(status))
            finally:
                status, _ = request(object_path, actor=TARGET_DAILY, key=key,
                                    role="service_role", method="DELETE")
                verify(f"AT06 {bucket} local fixture cleanup", status == 200,
                       str(status))
    finally:
        cleanup_read_fixtures()
        atexit.unregister(cleanup_read_fixtures)
    print(f"{ASSERTIONS} local HTTP/DB assertions passed; synthetic fixture only.")


if __name__ == "__main__":
    main()
