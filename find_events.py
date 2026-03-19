#!/usr/bin/env python3
import urllib.request
import json
import ssl

BASE = 'https://admin.ev-agency.io/shm/v1'
AUTH = 'Basic bW90c2FyOnJoZWRDYVhaVGZUTXJIcDg='
ctx = ssl.create_default_context()

def api(method, path):
    url = BASE + path
    req = urllib.request.Request(url, method=method)
    req.add_header('Authorization', AUTH)
    with urllib.request.urlopen(req, context=ctx) as r:
        return json.loads(r.read().decode())

# Get ALL events
events = api('GET', '/admin/service/event?limit=200').get('data', [])

# Search for password_reset
print('EVENTS with password_reset:')
for ev in events:
    name = ev.get('name', '').lower()
    title = ev.get('title', '').lower()
    if 'password' in name or 'password' in title or 'reset' in name or 'reset' in title:
        print(f"  id={ev.get('id'):>3}, name={ev.get('name'):>25}, title={ev.get('title'):>30}, server_gid={ev.get('server_gid')}")

print()
print('ALL EVENTS (first 30):')
for ev in events[:30]:
    print(f"  id={ev.get('id'):>3}, name={ev.get('name'):>25}, title={ev.get('title'):>30}, server_gid={ev.get('server_gid')}")
