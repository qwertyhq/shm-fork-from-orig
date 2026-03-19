#!/usr/bin/env python3
"""Debug: check actual API response formats"""
import json, urllib.request, ssl

BASE = "https://admin.ev-agency.io/shm/v1"
AUTH = "bW90c2FyOnJoZWRDYVhaVGZUTXJIcDg="
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def get(path):
    req = urllib.request.Request(BASE + path, method="GET")
    req.add_header("Authorization", "Basic " + AUTH)
    return json.loads(urllib.request.urlopen(req, context=ctx, timeout=30).read().decode())

print("=== SPOOL HISTORY (last 3 for user 2385) ===")
resp = get("/admin/spool/history")
items = resp.get("data", [])
recent = [h for h in items if h.get("user_id") == 2385]
recent.sort(key=lambda x: x.get("spool_id", 0), reverse=True)
for r in recent[:3]:
    sid = r.get("spool_id")
    st = r.get("status")
    print(f"  spool_id={sid} status={st} (type={type(st).__name__})")
    ev = r.get("event", "")
    if isinstance(ev, dict):
        print(f"  event.name={ev.get('name')} event.title={ev.get('title')}")
    resp_data = r.get("response", "")
    if isinstance(resp_data, dict):
        print(f"  response.message={resp_data.get('message', '')}")
    print()

print("=== USER SETTINGS (user_id=2385) ===")
resp = get("/admin/user?user_id=2385")
data = resp.get("data", [])
if data:
    user = data[0]
    settings = user.get("settings", {})
    print(f"  type: {type(settings).__name__}")
    if isinstance(settings, str):
        settings = json.loads(settings)
    # Show relevant keys
    for key in ["email", "email_verified", "email_verify_code", "email_verify_expires",
                 "reset_password_verify_token", "reset_password_verify_expires"]:
        val = settings.get(key, "<NOT SET>")
        if key == "reset_password_verify_token" and isinstance(val, str) and len(val) > 15:
            val = val[:10] + "..."
        print(f"  {key} = {val}")
