{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║       REMNAWAVE UPDATE CONFIGS ALL — Batch Template v4.1 (Pure TT)           ║
║    Массовое обновление subscription_url и subscription_config                ║
║    для всех пользователей в SHM storage                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝

НАЗНАЧЕНИЕ:
  Обходит всех пользователей Remnawave, для каждого перечитывает подписку
  и обновляет данные в SHM storage, сохраняя существующие поля (configs и др.)

ВЫЗОВ:
  GET /shm/v1/template/remna-link-update-all

ЛОГИКА:
  1. Загружает карту storage_name -> user_id из admin storage API
  2. Получает полный список пользователей из Remnawave API (с пагинацией)
  3. Для каждого пользователя с username вида HQVPN_{us_id}:
     a. Извлекает us_id из username
     b. Берёт user_id из предзагруженной карты storage
     c. Генерирует user session, читает текущие данные из storage
     d. Получает свежую подписку и raw config из Remnawave
     e. Мержит новые данные в существующие, сохраняет через admin storage API
  4. Выводит итоговый JSON с результатами
#}}

{{# === Параметры === #}}
{{ STORAGE_PREFIX = "vpn_mrzb_" }}
{{ NAME_PREFIX = "HQVPN_" }}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "твой токен" }}
{{ remna_headers = { 'Authorization' => 'Bearer ' _ REMNA_TOKEN } }}
{{ PAGE_SIZE = 100 }}curl -s -H "session-id: <ADMIN_SESSION_ID>" "https://<SHM_API_HOST>/shm/v1/template/remna-link-update-all"

{{# === Admin session и API URL === #}}
{{ admin_session = user.gen_session.id }}
{{ api_url = config.api.url }}
{{ admin_headers = { 'session-id' => admin_session } }}

{{# === Счётчики === #}}
{{ total = 0 }}
{{ updated = 0 }}
{{ skipped = 0 }}
{{ errors = 0 }}

{{# === 1. Загружаем карту storage_name -> user_id из admin storage === #}}
{{ storage_uid_map = {} }}
{{ all_storage = http.get(api_url _ '/shm/v1/admin/storage/manage?limit=10000', 'headers', admin_headers) }}
{{ FOREACH st_item IN all_storage.data }}
  {{ IF st_item.name.match('^' _ STORAGE_PREFIX) }}
    {{ storage_uid_map.${st_item.name} = st_item.user_id }}
  {{ END }}
{{ END }}

{{# === 2. Получаем первую страницу для определения total === #}}
{{ first_page = http.get(REMNA_HOST _ '/api/users?start=0&size=1', 'headers', remna_headers) }}
{{ total_users = first_page.response.total || 0 }}

{{ UNLESS total_users }}
{"status": "ok", "message": "No users found in Remnawave", "total": 0}
{{ RETURN }}
{{ END }}

{{# === 3. Пагинация по всем пользователям === #}}
{{ offset = 0 }}
{{ WHILE offset < total_users }}
  {{ page = http.get(REMNA_HOST _ '/api/users?start=' _ offset _ '&size=' _ PAGE_SIZE, 'headers', remna_headers) }}
  {{ users_list = page.response.users }}

  {{ UNLESS users_list && users_list.size }}
    {{ LAST }}
  {{ END }}

  {{# === 4. Обрабатываем каждого пользователя === #}}
  {{ FOREACH remna_user IN users_list }}
    {{ total = total + 1 }}
    {{ username = remna_user.username }}
    {{ user_short_uuid = remna_user.shortUuid }}

    {{# Проверяем префикс #}}
    {{ UNLESS username.match('^' _ NAME_PREFIX _ '(\d+)$') }}
      {{ skipped = skipped + 1 }}
      {{ NEXT }}
    {{ END }}

    {{# Извлекаем us_id из username #}}
    {{ us_id_match = username.match('^' _ NAME_PREFIX _ '(\d+)$') }}
    {{ us_id = us_id_match.0 }}

    {{ UNLESS us_id && user_short_uuid }}
      {{ skipped = skipped + 1 }}
      {{ NEXT }}
    {{ END }}

    {{# Получаем user_id из предзагруженной карты storage #}}
    {{ storage_key = STORAGE_PREFIX _ us_id }}
    {{ target_user_id = storage_uid_map.${storage_key} }}

    {{ UNLESS target_user_id }}
      {{ skipped = skipped + 1 }}
      {{ NEXT }}
    {{ END }}

    {{# Генерируем user session и читаем текущие данные из storage #}}
    {{ user_session_resp = http.put(api_url _ '/shm/v1/admin/user/session?user_id=' _ target_user_id, 'headers', admin_headers) }}
    {{ user_session = user_session_resp.id }}

    {{ UNLESS user_session }}
      {{ errors = errors + 1 }}
      {{ NEXT }}
    {{ END }}

    {{# storage GET возвращает text/plain → http.get возвращает строку, парсим через fromJson #}}
    {{ existing_data_raw = http.get(api_url _ '/shm/v1/storage/manage/' _ storage_key, 'headers', { 'session-id' => user_session }) }}
    {{ existing_data = fromJson(existing_data_raw) }}
    {{ existing_data = existing_data || {} }}

    {{# Получаем свежую подписку #}}
    {{ new_sub_config = http.get(REMNA_HOST _ '/api/sub/' _ user_short_uuid) }}

    {{# Получаем свежую raw конфигурацию #}}
    {{ new_raw_config = http.get(REMNA_HOST _ '/api/sub/' _ user_short_uuid _ '/raw?withDisabledHosts=true', 'headers', remna_headers) }}

    {{# Мержим в существующие данные (сохраняем configs и др.) #}}
    {{ existing_data.response = remna_user }}
    {{ existing_data.subscription_url = remna_user.subscriptionUrl }}
    {{ existing_data.subscription_config = new_sub_config }}
    {{ existing_data.raw_config = new_raw_config }}

    {{# Пишем через user-роут (skip_auto_parse_json), НЕ admin-роут #}}
    {{ payload_json = toJson(existing_data) }}
    {{ save_result = http.post(api_url _ '/shm/v1/storage/manage/' _ storage_key, 'headers', { 'session-id' => user_session, 'Content-Type' => 'application/json' }, 'content', payload_json) }}

    {{ updated = updated + 1 }}
  {{ END }}

  {{ offset = offset + PAGE_SIZE }}
{{ END }}

{"status": "ok", "total_remnawave": {{ total_users }}, "processed": {{ total }}, "updated": {{ updated }}, "skipped": {{ skipped }}, "errors": {{ errors }}}