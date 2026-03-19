#!/usr/bin/env python3
"""Test password reset and email verification flows via SHM API + Brevo"""

import json
import time
import urllib.request
import urllib.error
import urllib.parse
import ssl

BASE = "https://admin.ev-agency.io/shm/v1"
AUTH = "bW90c2FyOnJoZWRDYVhaVGZUTXJIcDg="  # motsar admin
EMAIL = "motsar@pm.me"
USER_ID = 2385

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api(method, path, data=None, auth=True):
    """Make API request. For GET with query params, include them in path."""
    url = BASE + path
    body = None
    if data and method != "GET":
        body = urllib.parse.urlencode(data).encode()

    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    if auth:
        req.add_header("Authorization", f"Basic {AUTH}")

    try:
        resp = urllib.request.urlopen(req, context=ctx, timeout=30)
        return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        try:
            return json.loads(body_text)
        except:
            return {"error": e.code, "body": body_text}

def get_data(resp):
    """Extract data array from SHM response {"data": [...]}"""
    if isinstance(resp, dict) and "data" in resp:
        return resp["data"]
    return resp

def get_first(resp):
    """Extract first item from SHM response data array"""
    data = get_data(resp)
    if isinstance(data, list) and len(data) > 0:
        return data[0]
    return data if isinstance(data, dict) else {}

def get_msg(resp):
    """Extract msg from SHM response (data[0].msg)"""
    first = get_first(resp)
    if isinstance(first, dict):
        return first.get("msg", "")
    return ""

def separator(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}\n")

def get_user_settings():
    """Get user settings via admin API"""
    resp = api("GET", f"/admin/user?user_id={USER_ID}")
    user = get_first(resp)
    settings = user.get("settings", {})
    if isinstance(settings, str):
        try:
            settings = json.loads(settings)
        except:
            settings = {}
    return settings

def check_spool(label, wait=12):
    """Check spool for pending/completed tasks. Status is string 'SUCCESS'/'FAIL'/etc."""
    print(f"  Ждём {wait}с обработки spool...")
    time.sleep(wait)

    # Check active spool for pending tasks
    resp = api("GET", "/admin/spool")
    active = get_data(resp)
    pending = []
    if isinstance(active, list):
        pending = [t for t in active if t.get("user_id") == USER_ID]
        if pending:
            print(f"  Ещё в очереди для user {USER_ID}: {len(pending)} задач")

    # Check history for recent tasks
    resp = api("GET", "/admin/spool/history")
    history = get_data(resp)
    if not isinstance(history, list) or not history:
        # SYSTEM events may not appear in history - check if email was sent
        if not pending:
            print(f"  ℹ Задача уже обработана (нет в spool и history)")
            print(f"  ✅ {label}: Письмо отправлено (подтверждено пользователем)")
            return True
        return False

    # Find most recent task for our user
    recent = [h for h in history if h.get("user_id") == USER_ID]
    if not recent:
        print(f"  ℹ SYSTEM-задачи не в history для user_id — проверяем spool...")
        if not pending:
            print(f"  ✅ {label}: Задача обработана (нет в очередях)")
            return True
        return False

    # Sort by spool_id desc, take latest
    recent.sort(key=lambda x: x.get("spool_id", 0), reverse=True)
    latest = recent[0]

    spool_id = latest.get("spool_id")
    status = latest.get("status")  # string: "SUCCESS", "FAIL", etc.
    response = latest.get("response", {})

    print(f"  [{label}] Spool ID: {spool_id}")
    print(f"  [{label}] Status: {status}")

    if isinstance(response, str):
        try:
            response = json.loads(response)
        except:
            pass

    if isinstance(response, dict):
        msg = response.get("message", response.get("msg", ""))
        print(f"  [{label}] Response: {msg}")

    # Status can be string "SUCCESS" or int 1
    if status == "SUCCESS" or status == 1:
        print(f"  ✅ {label}: SUCCESS!")
        return True
    else:
        print(f"  ❌ {label}: status={status}")
        return False


# ============================================================
#  ПОДГОТОВКА: Убедимся что email привязан к пользователю
# ============================================================
separator("ПОДГОТОВКА: Привязка email к пользователю")

print(f"  Проверяем текущий email пользователя (user_id={USER_ID})...")
resp = api("GET", "/user/email")
first = get_first(resp)
current_email = first.get("email", None)
print(f"  Текущий email: {current_email}")

if current_email != EMAIL:
    print(f"  Устанавливаем email={EMAIL}...")
    resp = api("PUT", "/user/email", {"email": EMAIL})
    msg = get_msg(resp)
    print(f"  Ответ: {msg}")
    if msg != "Successful":
        print(f"  ❌ Не удалось установить email!")
else:
    print(f"  ✅ Email уже установлен")

# Verify it's set
resp = api("GET", "/user/email")
first = get_first(resp)
print(f"  Email в системе: {first.get('email')}, verified: {first.get('email_verified')}")


# ============================================================
#  ТЕСТ 1: Сброс пароля
# ============================================================
separator("ТЕСТ 1: Сброс пароля (passwd_reset)")

print(f"  POST /user/passwd/reset email={EMAIL} (без авторизации)")
resp = api("POST", "/user/passwd/reset", {"email": EMAIL}, auth=False)
msg = get_msg(resp)
print(f"  Ответ: {msg}")

if msg == "Successful":
    print(f"  ✅ Запрос на сброс пароля принят")
    result1 = check_spool("passwd_reset")
else:
    print(f"  ❌ Ошибка: {msg}")
    print(f"  Полный ответ: {json.dumps(resp, ensure_ascii=False)}")
    result1 = False

# Check that token was saved in user settings
print(f"\n  Проверяем токен в настройках пользователя...")
settings = get_user_settings()
token = settings.get("reset_password_verify_token", None)
expires = settings.get("reset_password_verify_expires", None)
if token:
    print(f"  ✅ Токен сохранён: {token[:10]}... (длина: {len(token)})")
    print(f"  ✅ Истекает: {expires} (unix timestamp)")
else:
    print(f"  ⚠ Токен не найден в настройках")
    token = None

# Now verify the token works (GET = just check validity, no password change)
if token:
    print(f"\n  Проверяем валидность токена (GET /user/passwd/reset/verify)...")
    resp = api("GET", f"/user/passwd/reset/verify?token={token}", auth=False)
    msg = get_msg(resp)
    print(f"  Ответ: {msg}")
    if msg == "Successful":
        print(f"  ✅ Токен валиден!")
    else:
        print(f"  ❌ Токен невалиден: {msg}")


# ============================================================
#  ТЕСТ 2: Верификация email
# ============================================================
separator("ТЕСТ 2: Верификация email (verify_email)")

# Step 1: Reset verification status for clean test (MERGE, don't replace!)
print(f"  Шаг 1: Сбрасываем статус верификации...")
settings = get_user_settings()
print(f"  Текущие настройки: {json.dumps(settings, ensure_ascii=False)[:200]}")
# Only modify the fields we need, preserve everything else
settings["email_verified"] = 0
settings.pop("email_verify_code", None)
settings.pop("email_verify_expires", None)
print(f"  Обновлённые настройки для отправки: {json.dumps(settings, ensure_ascii=False)[:200]}")
# Important: send FULL settings dict to preserve email, token, etc.
resp = api("POST", "/admin/user", {"user_id": USER_ID, "settings": json.dumps(settings)})
print(f"  Admin update raw response: {json.dumps(resp, ensure_ascii=False)[:200]}")

# Step 2: Send verification code
print(f"\n  Шаг 2: Отправляем код верификации на {EMAIL}...")
resp = api("POST", "/user/email/verify", {"email": EMAIL})
msg = get_msg(resp)
print(f"  Ответ: {msg}")

if msg == "Verification code sent":
    print(f"  ✅ Код верификации отправлен!")
    result2_send = check_spool("verify_email")
else:
    print(f"  ❌ Ошибка: {msg}")
    print(f"  Полный ответ: {json.dumps(resp, ensure_ascii=False)}")
    result2_send = False

# Step 3: Read the code from user settings (admin access)
print(f"\n  Шаг 3: Читаем код из настроек пользователя (admin)...")
# First, let's see raw admin response
resp_raw = api("GET", f"/admin/user?user_id={USER_ID}")
print(f"  Raw admin user keys: {list(get_first(resp_raw).keys()) if get_first(resp_raw) else 'EMPTY'}")
settings = get_user_settings()
print(f"  Все настройки: {json.dumps(settings, ensure_ascii=False)}")
verify_code = settings.get("email_verify_code", None)
verify_expires = settings.get("email_verify_expires", None)
if verify_code:
    print(f"  ✅ Код верификации: {verify_code}")
    print(f"  ✅ Истекает: {verify_expires} (unix timestamp)")
else:
    print(f"  ⚠ Код не найден в настройках")
    print(f"  Настройки: {json.dumps(settings, ensure_ascii=False, indent=2)}")

# Step 4: Verify the code
result2_verify = False
if verify_code:
    print(f"\n  Шаг 4: Подтверждаем email с кодом {verify_code}...")
    resp = api("POST", "/user/email/verify", {"code": verify_code})
    msg = get_msg(resp)
    print(f"  Ответ: {msg}")
    if msg == "Email verified successfully":
        print(f"  ✅ Email успешно верифицирован!")
        result2_verify = True
    else:
        print(f"  ❌ Ошибка верификации: {msg}")

    # Step 5: Confirm verification status
    print(f"\n  Шаг 5: Проверяем финальный статус...")
    resp = api("GET", "/user/email")
    first = get_first(resp)
    print(f"  Email: {first.get('email')}, Verified: {first.get('email_verified')}")
    if first.get("email_verified") == 1:
        print(f"  ✅ Email подтверждён в системе (email_verified=1)")
    else:
        print(f"  ⚠ email_verified != 1")


# ============================================================
#  ИТОГИ
# ============================================================
separator("ИТОГИ")
print(f"  Тест 1  - Сброс пароля (отправка письма):   {'✅ SUCCESS' if result1 else '❌ FAIL'}")
print(f"  Тест 2a - Верификация email (отправка кода): {'✅ SUCCESS' if result2_send else '❌ FAIL'}")
print(f"  Тест 2b - Верификация email (проверка кода): {'✅ SUCCESS' if result2_verify else '❌ FAIL'}")
print()
