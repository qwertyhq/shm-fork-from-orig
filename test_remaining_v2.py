#!/usr/bin/env python3
"""Test remaining Brevo email templates by calling SHM APIs"""

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
# TEST 1: Password reset request
# ============================================================
sep("1. TEST brevo_password_reset via /user/passwd/reset")

# Get user 2385 email first
user_resp = api("GET", "/admin/user/2385")
user_data = user_resp.get("data", [{}])[0] if user_resp.get("data") else {}
user_email = user_data.get("settings", {}).get("email", "motsar@pm.me")
print(f"  User 2385 email: {user_email}")

# Request password reset
reset_data = {"email": user_email}
result = api("POST", "/user/passwd/reset", reset_data)
print(f"  Password reset result: {json.dumps(result, indent=2, ensure_ascii=False)[:500]}")

# ============================================================
# TEST 2: Email verification
# ============================================================
sep("2. TEST brevo_verify_code via /user/email/verify")

# Request verification code
verify_data = {"email": user_email}
result = api("POST", "/user/email/verify", verify_data)
print(f"  Email verify result: {json.dumps(result, indent=2, ensure_ascii=False)[:500]}")

# ============================================================
# TEST 3: Create brevo_welcome event manually
# ============================================================
sep("3. TEST brevo_welcome - create event and spool task")

# Get existing Brevo events to use as template
events = api("GET", "/admin/service/event?limit=100").get("data", [])
brevo_events = [ev for ev in events if ev.get("server_gid") == 13]

if brevo_events:
    # Use first Brevo event as template
    template = brevo_events[0]
    
    # Create welcome event
    welcome_event_data = {
        "name": "welcome",
        "title": "brevo_welcome",
        "server_gid": "13",
        "settings": json.dumps(template.get("settings", {})),
    }
    
    create_result = api("PUT", "/admin/service/event", welcome_event_data)
    print(f"  Create welcome event: {json.dumps(create_result, indent=2, ensure_ascii=False)[:300]}")
    
    if create_result.get("data"):
        welcome_event_id = create_result["data"][0].get("event_id")
        print(f"  Created event id={welcome_event_id}")
        
        # Get the created event
        new_events = api("GET", "/admin/service/event?limit=100").get("data", [])
        welcome_event = None
        for ev in new_events:
            if ev.get("title") == "brevo_welcome":
                welcome_event = ev
                break
        
        if welcome_event:
            # Create spool task
            spool_data = {
                "event": json.dumps(welcome_event),
                "user_id": "2385",
            }
            spool_result = api("PUT", "/admin/spool", spool_data)
            print(f"  Spool result: {json.dumps(spool_result, indent=2, ensure_ascii=False)[:300]}")
else:
    print("  No Brevo events found to use as template")

# ============================================================
# WAIT and check results
# ============================================================
sep("4. WAITING 10s FOR PROCESSING...")
time.sleep(10)

sep("5. SPOOL HISTORY (user 2385, last 15)")
history = api("GET", "/admin/spool/history?user_id=2385&limit=15").get("data", [])
if history:
    status_map = {0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
    for task in history:
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        ev_title = ev.get("title", "") if isinstance(ev, dict) else ""
        resp = task.get("response", {})
        resp_str = json.dumps(resp, ensure_ascii=False)[:100] if isinstance(resp, dict) else str(resp)[:100]
        print(f"  id={task.get('id'):>5} | {st:>7} | {ev_name:>20} | {ev_title[:25]:>25} | {resp_str}")
else:
    print("  No history entries found")

print("\n" + "=" * 60)
print("DONE! Check motsar@pm.me for test emails")
print("=" * 60)
