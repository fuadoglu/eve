#!/usr/bin/env python3
"""EVE-006.2 local-only Data API and Storage negative acceptance checks.

Run on a fresh local Supabase stack after 0062_rent_read_smoke.sql. The fixture
contains synthetic A/B owners and daily/full managers. This script never prints
JWTs, signing material, or raw API responses.
"""

import base64
import hashlib
import hmac
import json
import subprocess
import time
import urllib.error
import urllib.request


API = "http://127.0.0.1:54321"
OWNER_A = "e1000000-0000-0000-0000-000000000001"
OWNER_B = "e1000000-0000-0000-0000-000000000002"
MANAGER = "e1000000-0000-0000-0000-000000000003"
TARGET_DAILY = "e1000000-0000-0000-0000-000000000005"
PROPERTY_A1 = "e2100000-0000-0000-0000-000000000001"
PROPERTY_A2 = "e2100000-0000-0000-0000-000000000002"
RESERVATION_A = "e3100000-0000-0000-0000-000000000001"
RESERVATION_B = "e3100000-0000-0000-0000-000000000002"
RENT_COLUMNS = {
    "entry_id", "reservation_id", "property_id", "placement_id", "kind",
    "amount_minor", "custodian", "occurred_at", "created_at",
}


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


def jwt(actor, key, role="authenticated"):
    def part(value):
        return b64(json.dumps(value, separators=(",", ":")).encode())

    signed = part({"alg": "HS256", "typ": "JWT"}) + b"." + part({
        "role": role, "sub": actor, "aud": "authenticated",
        "exp": int(time.time()) + 300,
    })
    return (signed + b"." + b64(hmac.new(key, signed, hashlib.sha256).digest())).decode()


def request(path, *, actor=None, key=None, role="authenticated", payload=None,
            method=None, headers=None):
    request_headers = dict(headers or {})
    if actor:
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
    if not condition:
        raise AssertionError(name + ": " + detail)
    print("PASS " + name)


def rpc(name, actor, key, arguments):
    status, body = request("/rest/v1/rpc/" + name, actor=actor, key=key,
                           payload=arguments)
    return status, json.loads(body)


def main():
    key = local_signing_key()
    capability = lambda property_id, name: {
        "p_property_id": property_id, "p_capability": name,
    }
    rent = lambda reservation_id: {"p_reservation_id": reservation_id}

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
           and set(data[0]) == RENT_COLUMNS, str(status))
    status, data = rpc("list_reservation_rent_summaries", OWNER_A, key,
                       rent(RESERVATION_A))
    verify("AT06 owner history read", status == 200 and len(data) == 3
           and all(set(row) == RENT_COLUMNS for row in data), str(status))
    status, data = rpc("list_reservation_rent_summaries", OWNER_B, key,
                       rent(RESERVATION_A))
    verify("AT04 other owner rent deny", status == 200 and data == [], str(status))
    status, data = rpc("list_reservation_rent_summaries", MANAGER, key,
                       rent(RESERVATION_B))
    verify("AT04 full manager assigned read", status == 200 and len(data) == 1,
           str(status))

    sql("update app_private.property_memberships set revoked_at=null "
        "where property_id='" + PROPERTY_A1 + "' and user_id='" + MANAGER + "';")
    status, data = rpc("has_property_capability", MANAGER, key,
                       capability(PROPERTY_A1, "property.read"))
    verify("AT05 manager before revoke", status == 200 and data is True,
           str(status))
    sql("update app_private.property_memberships set revoked_at=now() "
        "where property_id='" + PROPERTY_A1 + "' and user_id='" + MANAGER + "';")
    status, data = rpc("has_property_capability", MANAGER, key,
                       capability(PROPERTY_A1, "property.read"))
    verify("AT05 next request revoke", status == 200 and data is False,
           str(status))

    status, _ = request("/rest/v1/properties", actor=OWNER_A, key=key)
    verify("AT04 direct base table deny", status == 404, str(status))
    status, _ = request("/rest/v1/properties", actor=OWNER_A, key=key,
                        headers={"Accept-Profile": "app_private"})
    verify("AT04 private schema deny", status == 406, str(status))
    status, _ = request("/rest/v1/rpc/has_property_capability",
                        payload=capability(PROPERTY_A1, "property.read"))
    verify("AT04 anonymous RPC deny", status == 401, str(status))

    status, body = request("/storage/v1/object/eve-private-task/denied.txt",
                           actor=TARGET_DAILY, key=key, payload=b"synthetic",
                           headers={"Content-Type": "text/plain"})
    storage_error = json.loads(body)
    verify("AT06 direct private storage upload deny",
           status == 400 and storage_error.get("code") == "AccessDenied"
           and storage_error.get("statusCode") == "403", str(status))

    object_path = "/storage/v1/object/eve-private-task/local-isolation-proof.txt"
    status, _ = request(object_path, actor=TARGET_DAILY, key=key,
                        role="service_role", payload=b"synthetic local proof",
                        headers={"Content-Type": "text/plain"})
    verify("AT06 local service fixture upload", status == 200, str(status))
    try:
        status, body = request(object_path, actor=TARGET_DAILY, key=key,
                               role="service_role")
        verify("AT06 fixture object exists", status == 200
               and body == b"synthetic local proof", str(status))
        status, body = request(object_path, actor=TARGET_DAILY, key=key)
        storage_error = json.loads(body)
        verify("AT06 direct private storage read deny",
               status != 200 and storage_error.get("code") == "NoSuchKey",
               str(status))
    finally:
        status, _ = request(object_path, actor=TARGET_DAILY, key=key,
                            role="service_role", method="DELETE")
        verify("AT06 local service fixture cleanup", status == 200,
               str(status))
    print("17 local HTTP/DB assertions passed; synthetic fixture only.")


if __name__ == "__main__":
    main()
