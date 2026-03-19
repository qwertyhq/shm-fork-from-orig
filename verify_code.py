#!/usr/bin/env python3
import urllib.request, urllib.parse, json, ssl

ctx = ssl.create_default_context()
BASE = 'https://admin.ev-agency.io/shm/v1'
AUTH = 'Basic bW90c2FyOnJoZWRDYVhaVGZUTXJIcDg='

def api(method, path, data=None):
    url = BASE + path
    if data:
        data = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', AUTH)
    resp = urllib.request.urlopen(req, context=ctx)
    return json.loads(resp.read().decode())

# Step 1: Verify email with code ONLY (no email param - otherwise it sends a NEW code)
print('=== Verifying email with code 486812 ===')
try:
    result = api('POST', '/user/email/verify', {'code': '486812'})
    print(json.dumps(result, indent=2, ensure_ascii=False))
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f'HTTP {e.code}: {body}')

# Step 2: Check user settings after verification
print()
print('=== User settings after verify ===')
result = api('GET', '/admin/user?user_id=2385')
data = result.get('data', [])
if data:
    settings = data[0].get('settings', {})
    print(json.dumps(settings, indent=2, ensure_ascii=False))
    ev = settings.get('email_verified')
    print(f'\nemail_verified = {ev}')
    if ev == 1 or ev == '1':
        print('SUCCESS! Email verified!')
    else:
        print('Email NOT verified yet')
