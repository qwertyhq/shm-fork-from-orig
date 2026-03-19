#!/usr/bin/env python3
"""Test remaining Brevo email templates: welcome, password_reset, verify_code"""

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
# TEST 1: brevo_welcome - triggered on user registration
# ============================================================
sep("1. TEST brevo_welcome (user registration)")

# Create a test user to trigger welcome email
welcome_data = {
    "email": "motsar@pm.me",
    "name": "Test Welcome",
    "password": "test123456",
}

# Try to trigger welcome via user creation
# Note: This might not work if welcome is not auto-triggered
result = api("PUT", "/admin/user", welcome_data)
print(f"  Create user result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")

# Check if there's a direct way to trigger welcome event
# Look for welcome event in events
events = api("GET", "/admin/service/event?limit=200").get('data', [])
welcome_event = None
for ev in events:
    if 'welcome' in ev.get('name', '').lower() or 'welcome' in ev.get('title', '').lower():
        welcome_event = ev
        print(f"  Found welcome event: id={ev.get('id')}, name={ev.get('name')}, title={ev.get('title')}")
        break

if not welcome_event:
    print("  No welcome event found in system")

# ============================================================
# TEST 2: brevo_password_reset - triggered via password reset API
# ============================================================
sep("2. TEST brevo_password_reset")

# Trigger password reset
reset_data = {
    "email": "motsar@pm.me",
}
result = api("POST", "/user/password_reset", reset_data)
print(f"  Password reset result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")

# ============================================================
# TEST 3: brevo_verify_code - triggered when sending verification code
# ============================================================
sep("3. TEST brevo_verify_code")

# Look for verify event
verify_event = None
for ev in events:
    if 'verify' in ev.get('name', '').lower() or 'verify' in ev.get('title', '').lower():
        verify_event = ev
        print(f"  Found verify event: id={ev.get('id')}, name={ev.get('name')}, title={ev.get('title')}")
        break

if verify_event:
    # Try to trigger verify code
    verify_data = {
        "event": json.dumps(verify_event),
        "user_id": "2385",
    }
    result = api("PUT", "/admin/spool", verify_data)
    print(f"  Verify code spool result: {json.dumps(result, indent=2, ensure_ascii=False)[:300]}")
else:
    print("  No verify event found - checking if there's a verify API...")
    # Try direct verify API
    verify_result = api("POST", "/user/verify", {"email": "motsar@pm.me"})
    print(f"  Verify API result: {json.dumps(verify_result, indent=2, ensure_ascii=False)[:300]}")

# ============================================================
# WAIT and check results
# ============================================================
sep("4. WAITING 10s FOR PROCESSING...")
time.sleep(10)

sep("5. SPOOL HISTORY (user 2385, last 10)")
history = api("GET", "/admin/spool/history?user_id=2385&limit=10").get('data', [])
if history:
    status_map = {0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
    for task in history:
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        ev_title = ev.get("title", "") if isinstance(ev, dict) else ""
        print(f"  id={task.get('id'):>5} | {st:>7} | {ev_name:>20} | {ev_title[:30]}")
else:
    print("  No history entries found")

# Also check spool for pending tasks
sep("6. PENDING SPOOL (user 2385)")
spool = api("GET", "/admin/spool?user_id=2385&limit=10").get('data', [])
if spool:
    for task in spool:
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        print(f"  id={task.get('id'):>5} | status={task.get('status')} | {ev_name}")
else:
    print("  No pending tasks")

print("\n" + "=" * 60)
print("DONE! Check motsar@pm.me for test emails")
print("=" * 60)
