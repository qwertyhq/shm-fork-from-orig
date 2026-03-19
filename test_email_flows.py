#!/usr/bin/env python3
"""Test all Brevo email notification flows via SHM API"""

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
            # For JSON fields, encode them properly
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

def get_data(resp):
    """Extract data array from SHM API response"""
    if isinstance(resp, dict) and "data" in resp:
        return resp["data"]
    if isinstance(resp, list):
        return resp
    return []

# ============================================================
# STEP 1: List all Brevo events (server_gid=13)
# ============================================================
sep("1. EVENTS for Brevo (server_gid=13)")
events_resp = api("GET", "/admin/service/event?limit=100")
all_events = get_data(events_resp)
print(f"  DEBUG: resp type={type(events_resp).__name__}, data type={type(all_events).__name__}, len={len(all_events)}")
if all_events:
    gids = set(ev.get('server_gid') for ev in all_events)
    print(f"  DEBUG: server_gid values found: {gids}")
    print(f"  DEBUG: server_gid types: {set(type(ev.get('server_gid')).__name__ for ev in all_events)}")
brevo_events = [ev for ev in all_events if ev.get('server_gid') == 13 or str(ev.get('server_gid')) == '13']
for ev in brevo_events:
    print(f"  id={ev.get('id')}, name={ev.get('name')}, title={ev.get('title')}, server_gid={ev.get('server_gid')}")
    print(f"    settings: {json.dumps(ev.get('settings', {}), ensure_ascii=False)}")
print(f"\n  Brevo events: {len(brevo_events)} / Total events: {len(all_events)}")

# ============================================================
# STEP 2: Get user 2385's services (for user_service_id)
# ============================================================
sep("2. USER 2385 SERVICES")
services_resp = api("GET", "/admin/user/service?user_id=2385")
services = get_data(services_resp)
user_service_id = None
if services:
    for s in services[:5]:
        print(f"  us_id={s.get('user_service_id')}, service_id={s.get('service_id')}, name={s.get('name','?')}, status={s.get('status')}, expire={s.get('expire','?')}")
    user_service_id = services[0].get('user_service_id')
    print(f"\n  Using user_service_id={user_service_id} for tests")
else:
    print("  No services found!")

# ============================================================
# STEP 3: Check existing spool for user 2385
# ============================================================
sep("3. EXISTING SPOOL (user 2385, last 5)")
spool_resp = api("GET", "/admin/spool?user_id=2385&limit=5")
spool = get_data(spool_resp)
if spool:
    for task in spool:
        status_map = {"0": "NEW", "1": "SUCCESS", "2": "FAIL", "3": "DELAYED", "4": "STUCK", "5": "PAUSED",
                       0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        resp = str(task.get("response", ""))[:100]
        print(f"  id={task.get('id')}, status={st}, event_name={ev_name}, response={resp}")
else:
    print("  Spool is empty")

# ============================================================
# STEP 4: Create spool tasks for each Brevo event
# ============================================================
if not brevo_events:
    print("\n!!! No Brevo events found. Cannot test.")
else:
    for i, ev in enumerate(brevo_events):
        ev_id = ev.get('id')
        ev_name = ev.get('name', '?')
        ev_title = ev.get('title', '?')
        
        sep(f"4.{i+1} TEST: {ev_title} (event id={ev_id}, name={ev_name})")
        
        # Build the spool entry like make_event does:
        # event=<event_record_json>, user_id, user_service_id
        event_json = json.dumps(ev)
        
        spool_data = {
            "event": event_json,
            "user_id": "2385",
        }
        if user_service_id:
            spool_data["user_service_id"] = str(user_service_id)
        
        result = api("PUT", "/admin/spool", spool_data)
        print(f"  Result: {json.dumps(result, indent=2, ensure_ascii=False)[:200]}")
        
        time.sleep(1)

# ============================================================
# STEP 5: Wait for processing and check results
# ============================================================
sep("5. WAITING 10s FOR SPOOL PROCESSING...")
time.sleep(10)

sep("6. SPOOL RESULTS (user 2385, last 15)")
spool_resp = api("GET", "/admin/spool?user_id=2385&limit=15")
spool = get_data(spool_resp)
if spool:
    for task in spool:
        status_map = {"0": "NEW", "1": "SUCCESS", "2": "FAIL", "3": "DELAYED", "4": "STUCK", "5": "PAUSED",
                       0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        ev_title = ev.get("title", "") if isinstance(ev, dict) else ""
        resp = task.get("response", {})
        resp_str = json.dumps(resp, ensure_ascii=False)[:150] if isinstance(resp, dict) else str(resp)[:150]
        print(f"  id={task.get('id'):>5} | {st:>7} | {ev_name:>20} | {ev_title[:30]:>30} | resp: {resp_str}")
else:
    print("  No spool entries found")

# ============================================================
# STEP 7: Also check spool history for recent completions
# ============================================================
sep("7. SPOOL HISTORY (user 2385, last 10)")
history_resp = api("GET", "/admin/spool/history?user_id=2385&limit=10")
history = get_data(history_resp)
if history:
    for task in history:
        status_map = {"0": "NEW", "1": "SUCCESS", "2": "FAIL", "3": "DELAYED", "4": "STUCK", "5": "PAUSED",
                       0: "NEW", 1: "SUCCESS", 2: "FAIL", 3: "DELAYED", 4: "STUCK", 5: "PAUSED"}
        st = status_map.get(task.get("status"), str(task.get("status")))
        ev = task.get("event", {})
        ev_name = ev.get("name", "?") if isinstance(ev, dict) else "?"
        resp = task.get("response", {})
        resp_str = json.dumps(resp, ensure_ascii=False)[:150] if isinstance(resp, dict) else str(resp)[:150]
        print(f"  id={task.get('id'):>5} | {st:>7} | {ev_name:>20} | resp: {resp_str}")
else:
    print("  No history entries found")

print("\n" + "=" * 60)
print("DONE! Check motsar@pm.me for test emails")
print("=" * 60)
