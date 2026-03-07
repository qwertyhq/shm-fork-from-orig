{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║       REMNAWAVE UPDATE CONFIGS — Per-User Template v4.1 (Pure TT)            ║
║   Обновляет subscription_url и subscription_config в SHM storage             ║
╚══════════════════════════════════════════════════════════════════════════════╝

НАЗНАЧЕНИЕ:
  Перечитывает подписку из Remnawave API для конкретного пользователя
  и обновляет данные в SHM storage, сохраняя существующие поля (configs и др.)

ВЫЗОВ:
  GET /shm/v1/template/remna-link-update?user_service_id=XXXX

ЛОГИКА:
  1. Получает user_id из admin storage metadata (GET /admin/storage/manage?name=...)
  2. Генерирует user session для чтения текущих данных из storage
  3. Читает текущие данные через user API (сохраняет configs и другие поля)
  4. Ищет пользователя в Remnawave по username (HQVPN_{us_id})
  5. Получает свежую подписку и raw конфигурацию
  6. Мержит новые данные в существующие и сохраняет через admin storage API
#}}

{{# === Параметры === #}}
{{ us_id = request.params.user_service_id }}

{{ UNLESS us_id }}
{"error": "user_service_id parameter is required"}
{{ RETURN }}
{{ END }}

{{ STORAGE_PREFIX = "vpn_mrzb_" }}
{{ USERNAME_PREFIX = "HQVPN_" }}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ" }}
{{ remna_headers = { 'Authorization' => 'Bearer ' _ REMNA_TOKEN } }}
{{ storage_key = STORAGE_PREFIX _ us_id }}

{{# === 1. Admin session + API URL === #}}
{{ admin_session = user.gen_session.id }}
{{ api_url = config.api.url }}
{{ admin_headers = { 'session-id' => admin_session } }}

{{# === 2. Получаем user_id из метаданных storage === #}}
{{ storage_meta = http.get(api_url _ '/shm/v1/admin/storage/manage?name=' _ storage_key, 'headers', admin_headers) }}
{{ target_user_id = storage_meta.data.0.user_id }}

{{ UNLESS target_user_id }}
{"error": "storage record not found", "storage_key": "{{ storage_key }}"}
{{ RETURN }}
{{ END }}

{{# === 3. Генерируем user session и читаем текущие данные из storage === #}}
{{ user_session_resp = http.put(api_url _ '/shm/v1/admin/user/session?user_id=' _ target_user_id, 'headers', admin_headers) }}
{{ user_session = user_session_resp.id }}

{{ UNLESS user_session }}
{"error": "failed to generate user session", "user_id": {{ target_user_id }}}
{{ RETURN }}
{{ END }}

{{# storage GET возвращает text/plain → http.get возвращает строку, не хеш. Парсим через fromJson #}}
{{ existing_data_raw = http.get(api_url _ '/shm/v1/storage/manage/' _ storage_key, 'headers', { 'session-id' => user_session }) }}
{{ existing_data = fromJson(existing_data_raw) }}
{{ existing_data = existing_data || {} }}

{{# === 4. Получаем пользователя из Remnawave по username === #}}
{{ username = USERNAME_PREFIX _ us_id }}
{{ fresh_user = http.get(REMNA_HOST _ '/api/users/by-username/' _ username, 'headers', remna_headers) }}

{{ UNLESS fresh_user && fresh_user.response && fresh_user.response.uuid }}
{"error": "user not found in Remnawave", "username": "{{ username }}"}
{{ RETURN }}
{{ END }}

{{ short_uuid = fresh_user.response.shortUuid }}
{{ new_sub_url = fresh_user.response.subscriptionUrl }}

{{# === 5. Получаем свежую подписку (base64 конфигурация) === #}}
{{ new_sub_config = http.get(REMNA_HOST _ '/api/sub/' _ short_uuid) }}

{{# === 6. Получаем свежую raw конфигурацию === #}}
{{ new_raw_config = http.get(REMNA_HOST _ '/api/sub/' _ short_uuid _ '/raw?withDisabledHosts=true', 'headers', remna_headers) }}

{{# === 7. Мержим в существующие данные (сохраняем configs и др.) === #}}
{{ existing_data.response = fresh_user.response }}
{{ existing_data.subscription_url = new_sub_url }}
{{ existing_data.subscription_config = new_sub_config }}
{{ existing_data.raw_config = new_raw_config }}
{{ payload_json = toJson(existing_data) }}

{{# storage POST тоже возвращает text/plain → парсим ответ #}}
{{ save_result_raw = http.post(api_url _ '/shm/v1/storage/manage/' _ storage_key, 'headers', { 'session-id' => user_session, 'Content-Type' => 'application/json' }, 'content', payload_json) }}
{{ save_result = fromJson(save_result_raw) }}

{"status": "ok", "us_id": {{ us_id }}, "user_id": {{ target_user_id }}, "uuid": "{{ fresh_user.response.uuid }}", "subscription_url": "{{ new_sub_url }}", "save_length": {{ save_result.length }}}
