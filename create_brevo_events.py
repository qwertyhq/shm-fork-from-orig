#!/usr/bin/env python3
"""Create Brevo events for password_reset and verify_code"""

import urllib.request
import urllib.parse
import json
import ssl

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

# Get existing Brevo events to use as template
events = api("GET", "/admin/service/event?limit=100").get("data", [])
brevo_events = [ev for ev in events if ev.get("server_gid") == 13]
print(f"Found {len(brevo_events)} Brevo events")

# Use first Brevo event as template
template = brevo_events[0] if brevo_events else {}
template_settings = template.get("settings", {})

# Create brevo_password_reset event
print("\n1. Creating brevo_password_reset event...")
password_reset_data = {
    "name": "user_password_reset",
    "title": "brevo_password_reset",
    "server_gid": "13",
    "settings": json.dumps({
        "category": "%",
        "template_id": "brevo_password_reset"
    }),
}
result = api("PUT", "/admin/service/event", password_reset_data)
print(f"  Result: {json.dumps(result, indent=2, ensure_ascii=False)[:400]}")

# Create brevo_verify_code event
print("\n2. Creating brevo_verify_code event...")
verify_code_data = {
    "name": "verify_email",
    "title": "brevo_verify_code",
    "server_gid": "13",
    "settings": json.dumps({
        "category": "%",
        "template_id": "brevo_verify_code"
    }),
}
result = api("PUT", "/admin/service/event", verify_code_data)
print(f"  Result: {json.dumps(result, indent=2, ensure_ascii=False)[:400]}")

# List all Brevo events now
print("\n3. All Brevo events (server_gid=13):")
events = api("GET", "/admin/service/event?limit=100").get("data", [])
brevo_events = [ev for ev in events if ev.get("server_gid") == 13]
for ev in brevo_events:
    print(f"  id={ev.get('id'):>3}, name={ev.get('name'):>25}, title={ev.get('title'):>30}")
