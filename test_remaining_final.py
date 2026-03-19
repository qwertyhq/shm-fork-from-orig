#!/usr/bin/env python3
"""Test remaining Brevo templates by creating spool tasks directly"""

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

# Get all Brevo events
events = api("GET", "/admin/service/event?limit=100").get("data", [])
brevo_events = {ev.get("title"): ev for ev in events if ev.get("server_gid") == 13}

print("Available Brevo events:")
for title, ev in brevo_events.items():
    print(f"  {title}: id={ev.get('id')}")

# ============================================================
# TEST 1: brevo_password_reset
# ============================================================
sep("1. TEST brevo_password_reset")
if "brevo_password_reset" in brevo_events:
    ev = brevo_events["brevo_password_reset"]
    spool_data = {
        "event": json.dumps(ev),
        "user_id": "2385",
    }
    result = api("PUT", "/admin/spool", spool_data)
    print(f"  Spool result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")
else:
    print("  Event not found!")

# ============================================================
# TEST 2: brevo_verify_code
# ============================================================
sep("2. TEST brevo_verify_code")
if "brevo_verify_code" in brevo_events:
    ev = brevo_events["brevo_verify_code"]
    spool_data = {
        "event": json.dumps(ev),
        "user_id": "2385",
    }
    result = api("PUT", "/admin/spool", spool_data)
    print(f"  Spool result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")
else:
    print("  Event not found!")

# ============================================================
# TEST 3: brevo_welcome (already tested, but send again)
# ============================================================
sep("3. TEST brevo_welcome")
if "brevo_welcome" in brevo_events:
    ev = brevo_events["brevo_welcome"]
    spool_data = {
        "event": json.dumps(ev),
        "user_id": "2385",
    }
    result = api("PUT", "/admin/spool", spool_data)
    print(f"  Spool result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")
else:
    print("  Event not found!")

# ============================================================
# WAIT and check results
# ============================================================
sep("4. WAITING 10s FOR PROCESSING...")
time.sleep(10)

sep("5. SPOOL HISTORY (last 10)")
history = api("GET", "/admin/spool/history?user_id=2385&limit=10").get("data", [])
if history:
    status_map = {0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
    for task in history:
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        ev_title = ev.get("title", "") if isinstance(ev, dict) else ""
        resp = task.get("response", {})
        if isinstance(resp, dict):
            if "message" in resp:
                resp_str = resp.get("message", "")
            elif "error" in resp:
                resp_str = resp.get("error", "")
            else:
                resp_str = json.dumps(resp, ensure_ascii=False)[:80]
        else:
            resp_str = str(resp)[:80]
        print(f"  id={task.get('id'):>5} | {st:>7} | {ev_name:>20} | {ev_title[:25]:>25} | {resp_str}")
else:
    print("  No history entries found")

print("\n" + "=" * 60)
print("DONE! Check motsar@pm.me for test emails")
print("=" * 60)
