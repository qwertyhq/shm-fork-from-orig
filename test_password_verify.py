#!/usr/bin/env python3
"""Test password_reset and verify_code with new Brevo events"""

import urllib.request
import urllib.parse
import json
import ssl
import time

BASE = "https://admin.ev-agency.io/shm/v1"
AUTH = "Basic bW90c2FyOnJoZWRDYVhaVGZUTXJIcDg="
ctx = ssl.create_default_context()

def api(method, path, data=None):
    url = BASE + path
    encoded = None
    if data:
        if isinstance(data, dict):
            encoded = urllib.parse.urlencode(data).encode()
        else:
            encoded = data.encode() if isinstance(data, str) else data
    req = urllib.request.Request(url, data=encoded, method=method)
    req.add_header("Authorization", AUTH)
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            body = r.read().decode()
            try:
                return json.loads(body)
            except Exception:
                return body
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return {"error": e.code, "body": json.loads(body)}
        except Exception:
            return {"error": e.code, "body": body}

def sep(title):
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)

# ============================================================
# TEST 1: Password reset request (should trigger both events)
# ============================================================
sep("1. TEST brevo_password_reset via /user/passwd/reset")

user_email = "motsar@pm.me"
reset_data = {"email": user_email}
result = api("POST", "/user/passwd/reset", reset_data)
print(f"  Password reset result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")

# ============================================================
# TEST 2: Email verification (should trigger verify_email events)
# ============================================================
sep("2. TEST brevo_verify_code via /user/email/verify")

verify_data = {"email": user_email}
result = api("POST", "/user/email/verify", verify_data)
print(f"  Email verify result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")

# ============================================================
# WAIT and check results
# ============================================================
sep("3. WAITING 10s FOR PROCESSING...")
time.sleep(10)

sep("4. SPOOL HISTORY (user 2385, last 20)")
history = api("GET", "/admin/spool/history?user_id=2385&limit=20").get("data", [])
if history:
    status_map = {0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
    for task in history:
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        ev_title = ev.get("title", "") if isinstance(ev, dict) else ""
        server_gid = ev.get("server_gid", "?") if isinstance(ev, dict) else "?"
        resp = task.get("response", {})
        resp_str = json.dumps(resp, ensure_ascii=False)[:80] if isinstance(resp, dict) else str(resp)[:80]
        print(f"  id={task.get('id'):>5} | {st:>7} | gid={server_gid:>2} | {ev_name:>20} | {ev_title[:25]:>25} | {resp_str}")
else:
    print("  No history entries found")

print("\n" + "=" * 60)
print("DONE! Check motsar@pm.me for test emails")
print("=" * 60)
