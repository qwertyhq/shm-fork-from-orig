{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    TRAFFIC RESET TEMPLATE v1.0                                ║
║   Автоматический сброс трафика + уведомления + списание с баланса            ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Скрипт для управления лимитами трафика пользователей в Remna:
  
  1. МОНИТОРИНГ: Проверяет пользователей, достигших лимита трафика
  2. УВЕДОМЛЕНИЯ: Отправляет в Telegram уведомление при достижении лимита
  3. СБРОС ТРАФИКА: Пользователь может запросить сброс через бота
  4. СПИСАНИЕ: При сбросе списывается сумма с баланса пользователя

РЕЖИМЫ РАБОТЫ:
  - action=check   - Проверка лимитов (запускать по cron каждые 5-10 минут)
  - action=reset   - Сброс трафика конкретного пользователя (с списанием)
  - action=status  - Статус трафика пользователя

API ENDPOINTS:
  GET  /shm/v1/template/traffic_reset?action=check
  GET  /shm/v1/template/traffic_reset?action=status&session_id=...
  POST /shm/v1/template/traffic_reset?action=reset&confirm=1&session_id=...
#}}

{{# ============== НАСТРОЙКИ ============== #}}

{{# ID мгновенной услуги "Сброс трафика" (period=0, next=-1) #}}
{{ TRAFFIC_RESET_SERVICE_ID = 30 }}

{{# Получаем цену из услуги #}}
{{ reset_service = service.id(TRAFFIC_RESET_SERVICE_ID) }}
{{ RESET_COST = reset_service.cost || 250 }}

{{# Порог уведомления (процент от лимита) - уведомить когда использовано >= X% #}}
{{ NOTIFY_THRESHOLD = 95 }}

{{# Cooldown между сбросами (секунды, 3600 = 1 час) #}}
{{ RESET_COOLDOWN = 3600 }}

{{# Telegram настройки #}}
{{ TG_TOKEN = config.telegram.telegram_bot.token || config.telegram.token || "" }}

{{# Админский чат для логов #}}
{{ ADMIN_CHAT_ID = -1001965226181 }}
{{ ADMIN_THREAD_ID = 28953 }}

{{# REMNAWAVE API #}}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ" }}
{{ auth_header = "Bearer " _ REMNA_TOKEN }}

{{# Storage prefix #}}
{{ STORAGE_PREFIX = "traffic_" }}

{{# ============== УТИЛИТЫ ============== #}}

{{# Форматирование байтов в читаемый вид #}}
{{ MACRO format_bytes(bytes) BLOCK }}
    {{ USE String }}
    {{ IF bytes >= 1073741824 }}
        {{ gb = bytes / 1073741824 }}{{ gb | format('%.2f') }} GB
    {{ ELSIF bytes >= 1048576 }}
        {{ mb = bytes / 1048576 }}{{ mb | format('%.2f') }} MB
    {{ ELSIF bytes >= 1024 }}
        {{ kb = bytes / 1024 }}{{ kb | format('%.2f') }} KB
    {{ ELSE }}
        {{ bytes }} B
    {{ END }}
{{ END }}

{{# Процент использования #}}
{{ MACRO get_usage_percent(used, limit) BLOCK }}
    {{ IF limit > 0 }}
        {{ pct = (used / limit) * 100 }}{{ pct | format('%.1f') }}
    {{ ELSE }}
        0
    {{ END }}
{{ END }}

{{# ============== ОСНОВНОЙ КОД ============== #}}

{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}
{{ req = request() }}
{{ action = req.params.action || 'status' }}
{{ confirm = req.params.confirm || 0 }}

{{# ============== ACTION: CHECK (CRON) ============== #}}
{{# Проверяем всех пользователей на превышение лимита трафика #}}

{{ IF action == 'check' }}

    {{# Получаем всех пользователей из Remna #}}
    {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
    {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
    {{ users = users_response.response.users || [] }}
    
    {{ notified_count = 0 }}
    {{ limited_users = [] }}
    {{ results = [] }}
    
    {{ FOREACH u IN users }}
        {{ user_uuid = u.uuid }}
        {{ username = u.username }}
        {{ user_status = u.status }}
        {{ traffic_limit = u.trafficLimitBytes || 0 }}
        {{# Трафик находится во вложенном объекте userTraffic #}}
        {{ user_traffic_obj = u.userTraffic || {} }}
        {{ used_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
        
        {{# Пропускаем пользователей без лимита #}}
        {{ NEXT UNLESS traffic_limit > 0 }}
        
        {{# Вычисляем процент использования #}}
        {{ usage_percent = 0 }}
        {{ IF traffic_limit > 0 }}
            {{ usage_percent = (used_traffic / traffic_limit) * 100 }}
        {{ END }}
        
        {{# Проверяем достижение порога #}}
        {{ IF usage_percent >= NOTIFY_THRESHOLD }}
            
            {{ short_uuid = user_uuid.substr(0, 8) }}
            {{ traffic_storage_key = STORAGE_PREFIX _ short_uuid }}
            {{ notify_data = storage.read('name', traffic_storage_key) || {} }}
            {{ last_notify_time = notify_data.last_notify_time || 0 }}
            
            {{# Проверяем не уведомляли ли уже недавно (раз в час) #}}
            {{ time_since_notify = current_time - last_notify_time }}
            
            {{# === ПОИСК TELEGRAM ID === #}}
            {{ telegram_id = '' }}
            {{ user_service_id = '' }}
            {{ shm_user_id = '' }}
            
            {{# 1. Парсим user_service_id из username (HQVPN_XXX, us_XXX и т.д.) #}}
            {{ uname_match = username.match('^.+_([0-9]+)$') }}
            {{ IF uname_match.0 }}
                {{ user_service_id = uname_match.0 }}
                {{# Получаем shm_user_id через us.id() #}}
                {{ tmp_us_obj = us.id(user_service_id) }}
                {{ IF tmp_us_obj }}
                    {{ shm_user_id = tmp_us_obj.user_id }}
                {{ END }}
            {{ END }}
            
            {{# 2. Ищем в storage по user_service_id #}}
            {{ IF user_service_id }}
                {{ vpn_storage_key = "vpn_mrzb_" _ user_service_id }}
                {{ st_data = storage.read('name', vpn_storage_key) }}
                {{ IF st_data && st_data.response }}
                    {{ telegram_id = st_data.response.telegramId || '' }}
                {{ END }}
            {{ END }}
            
            {{# 3. Fallback: парсим @TELEGRAM_ID из description #}}
            {{ IF !telegram_id }}
                {{ desc = u.description || '' }}
                {{ tg_match = desc.match('@([0-9]+)') }}
                {{ IF tg_match.0 }}
                    {{ telegram_id = tg_match.0 }}
                {{ END }}
            {{ END }}
            
            {{# Добавляем в список лимитированных #}}
            {{ limited_users.push({
                'username' => username,
                'uuid' => user_uuid,
                'status' => user_status,
                'used' => used_traffic,
                'limit' => traffic_limit,
                'percent' => usage_percent,
                'telegram_id' => telegram_id
            }) }}
            
            {{# Уведомляем если: 1) давно не уведомляли, 2) статус LIMITED #}}
            {{ should_notify = 0 }}
            
            {{# Уведомляем при достижении 95% (первый раз) #}}
            {{ IF usage_percent >= NOTIFY_THRESHOLD && usage_percent < 100 && !notify_data.notified_95 }}
                {{ should_notify = 1 }}
                {{ notify_type = '95' }}
            {{ END }}
            
            {{# Уведомляем при достижении лимита (статус LIMITED) #}}
            {{ IF user_status == 'LIMITED' && !notify_data.notified_limit }}
                {{ should_notify = 1 }}
                {{ notify_type = 'limit' }}
            {{ END }}
            
            {{# Отправляем уведомление #}}
            {{ IF should_notify && telegram_id && TG_TOKEN }}
                
                {{ used_formatted = format_bytes(used_traffic) }}
                {{ limit_formatted = format_bytes(traffic_limit) }}
                {{ usage_pct_str = usage_percent | format('%.1f') }}
                
                {{ IF notify_type == '95' }}
                    {{ msg = "⚠️ <b>Предупреждение о трафике!</b>\n\n" }}
                    {{ msg = msg _ "Вы использовали <b>" _ usage_pct_str _ "%</b> лимита трафика.\n\n" }}
                    {{ msg = msg _ "📊 Использовано: " _ used_formatted _ "\n" }}
                    {{ msg = msg _ "📦 Лимит: " _ limit_formatted _ "\n\n" }}
                    {{ msg = msg _ "💡 Когда трафик закончится, доступ будет ограничен.\n" }}
                    {{ msg = msg _ "Вы можете сбросить трафик за " _ RESET_COST _ "₽" }}
                    
                    {{ notify_data.notified_95 = 1 }}
                {{ ELSE }}
                    {{ msg = "🚫 <b>Лимит трафика исчерпан!</b>\n\n" }}
                    {{ msg = msg _ "📊 Использовано: " _ used_formatted _ "\n" }}
                    {{ msg = msg _ "📦 Лимит: " _ limit_formatted _ "\n\n" }}
                    {{ msg = msg _ "Ваш доступ к VPN ограничен.\n\n" }}
                    {{ msg = msg _ "💰 <b>Сбросить трафик за " _ RESET_COST _ "₽?</b>\n" }}
                    {{ msg = msg _ "Нажмите кнопку ниже для сброса." }}
                    
                    {{ notify_data.notified_limit = 1 }}
                {{ END }}
                
                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                
                {{# Кнопки для сброса трафика #}}
                {{ webapp_url = config.api.url _ '/shm/v1/public/payment?format=html&user_id=' _ shm_user_id }}
                {{ keyboard = {
                    'inline_keyboard' => [
                        [
                            { 'text' => '🔄 Сбросить трафик за ' _ RESET_COST _ '₽', 'callback_data' => '/reset_traffic' }
                        ],
                        [
                            { 'text' => '✚ Пополнить баланс', 'web_app' => { 'url' => webapp_url } }
                        ],
                        [
                            { 'text' => '📊 Статус трафика', 'callback_data' => '/traffic_status' }
                        ]
                    ]
                } }}
                
                {{ send_result = http.post(tg_url, 'content', { 
                    'chat_id' => telegram_id, 
                    'text' => msg, 
                    'parse_mode' => 'HTML',
                    'reply_markup' => keyboard
                }) }}
                
                {{ IF send_result.ok }}
                    {{ notified_count = notified_count + 1 }}
                    {{ notify_data.last_notify_time = current_time }}
                    {{ notify_data.notify_type = notify_type }}
                {{ END }}
                
                {{# Сохраняем данные #}}
                {{ save_result = storage.save(traffic_storage_key, notify_data) }}
                
                {{ results.push({
                    'user' => username,
                    'action' => 'NOTIFIED',
                    'type' => notify_type,
                    'percent' => usage_percent
                }) }}
            {{ END }}
        {{ END }}
    {{ END }}
    
    {{# Результат #}}
    {
        "status": 1,
        "action": "check",
        "summary": {
            "total_users": {{ users.size }},
            "limited_users": {{ limited_users.size }},
            "notified": {{ notified_count }}
        },
        "threshold_percent": {{ NOTIFY_THRESHOLD }},
        "reset_cost": {{ RESET_COST }},
        "limited_users": {{ toJson(limited_users) }},
        "results": {{ toJson(results) }}
    }

{{# ============== ACTION: STATUS ============== #}}
{{# Получить статус трафика текущего пользователя #}}

{{ ELSIF action == 'status' }}

    {{ IF !user.id }}
        { "status": 0, "error": "Authorization required", "code": "AUTH_REQUIRED" }
    {{ ELSE }}
        
        {{# Находим пользователя в Remna по username паттерну #}}
        {{ shm_username = user.login _ "_" _ user.id }}
        {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
        {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
        {{ users = users_response.response.users || [] }}
        
        {{ remna_user = {} }}
        {{ FOREACH u IN users }}
            {{ IF u.username == shm_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
        
        {{ IF !remna_user.uuid }}
            { "status": 0, "error": "User not found in Remna", "code": "USER_NOT_FOUND" }
        {{ ELSE }}
            {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
            {{# Трафик находится во вложенном объекте userTraffic #}}
            {{ user_traffic_obj = remna_user.userTraffic || {} }}
            {{ used_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
            {{ usage_percent = 0 }}
            {{ IF traffic_limit > 0 }}
                {{ usage_percent = (used_traffic / traffic_limit) * 100 }}
            {{ END }}
            
            {{ short_uuid = remna_user.uuid.substr(0, 8) }}
            {{ storage_key = STORAGE_PREFIX _ short_uuid }}
            {{ traffic_data = storage.read('name', storage_key) || {} }}
            {{ last_reset_time = traffic_data.last_reset_time || 0 }}
            
            {{# Проверяем cooldown #}}
            {{ time_since_reset = current_time - last_reset_time }}
            {{ can_reset = time_since_reset >= RESET_COOLDOWN }}
            {{ cooldown_remaining = 0 }}
            {{ IF !can_reset }}
                {{ cooldown_remaining = RESET_COOLDOWN - time_since_reset }}
            {{ END }}
            
            {
                "status": 1,
                "action": "status",
                "user": {
                    "shm_id": {{ user.id }},
                    "shm_login": "{{ user.login }}",
                    "balance": {{ user.balance }},
                    "remna_uuid": "{{ remna_user.uuid }}",
                    "remna_username": "{{ remna_user.username }}",
                    "remna_status": "{{ remna_user.status }}"
                },
                "traffic": {
                    "used_bytes": {{ used_traffic }},
                    "limit_bytes": {{ traffic_limit }},
                    "used_formatted": "{{ format_bytes(used_traffic) }}",
                    "limit_formatted": "{{ format_bytes(traffic_limit) }}",
                    "usage_percent": {{ usage_percent | format('%.2f') }},
                    "is_limited": {{ IF remna_user.status == 'LIMITED' }}true{{ ELSE }}false{{ END }}
                },
                "reset": {
                    "cost": {{ RESET_COST }},
                    "can_reset": {{ IF can_reset }}true{{ ELSE }}false{{ END }},
                    "cooldown_seconds": {{ RESET_COOLDOWN }},
                    "cooldown_remaining": {{ cooldown_remaining }},
                    "last_reset_time": {{ last_reset_time }},
                    "has_balance": {{ IF user.balance >= RESET_COST }}true{{ ELSE }}false{{ END }}
                }
            }
        {{ END }}
    {{ END }}

{{# ============== ACTION: TRAFFIC_STATUS (Telegram callback) ============== #}}
{{# Отправляет статус трафика в Telegram с кнопками #}}

{{ ELSIF action == 'traffic_status' }}

    {{ IF !user.id }}
        { "status": 0, "error": "Authorization required", "code": "AUTH_REQUIRED" }
    {{ ELSE }}
        
        {{# Находим telegram_id и user_service_id #}}
        {{ telegram_id = '' }}
        {{ user_service_id = '' }}
        {{ vpn_services = user.services.list({'category' => 'vpn', 'status' => 'ACTIVE'}) }}
        {{ FOREACH vs IN vpn_services }}
            {{ vpn_storage_key = "vpn_mrzb_" _ vs.user_service_id }}
            {{ vpn_data = storage.read(vpn_storage_key) }}
            {{ IF vpn_data.response.telegramId }}
                {{ user_service_id = vs.user_service_id }}
                {{ telegram_id = vpn_data.response.telegramId }}
                {{ LAST }}
            {{ END }}
        {{ END }}
        
        {{# Fallback: vpn-m-% #}}
        {{ IF !user_service_id }}
            {{ vpn_services2 = ref(user.services.list_for_api('category', 'vpn-m-%')) }}
            {{ FOREACH vs IN vpn_services2 }}
                {{ IF vs.status == 'ACTIVE' }}
                    {{ user_service_id = vs.user_service_id }}
                    {{ vpn_storage_key = "vpn_mrzb_" _ vs.user_service_id }}
                    {{ vpn_data = storage.read(vpn_storage_key) }}
                    {{ IF vpn_data.response.telegramId }}
                        {{ telegram_id = vpn_data.response.telegramId }}
                    {{ END }}
                    {{ LAST }}
                {{ END }}
            {{ END }}
        {{ END }}
        
        {{# Ищем пользователя в Remna #}}
        {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
        {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
        {{ users = users_response.response.users || [] }}
        
        {{ remna_user = {} }}
        {{ shm_username = 'HQVPN_' _ user_service_id }}
        {{ FOREACH u IN users }}
            {{ IF u.username == shm_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
        
        {{# Пробуем us_ формат #}}
        {{ IF !remna_user.uuid }}
            {{ shm_username = 'us_' _ user_service_id }}
            {{ FOREACH u IN users }}
                {{ IF u.username == shm_username }}
                    {{ remna_user = u }}
                {{ END }}
            {{ END }}
        {{ END }}
        
        {{ IF !remna_user.uuid }}
            { "status": 0, "error": "User not found in Remna", "code": "USER_NOT_FOUND" }
        {{ ELSIF !telegram_id }}
            { "status": 0, "error": "Telegram ID not found", "code": "NO_TELEGRAM" }
        {{ ELSE }}
            
            {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
            {{ user_traffic_obj = remna_user.userTraffic || {} }}
            {{ used_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
            {{ usage_percent = 0 }}
            {{ IF traffic_limit > 0 }}
                {{ usage_percent = (used_traffic / traffic_limit) * 100 }}
            {{ END }}
            
            {{# Форматируем #}}
            {{ used_gb = used_traffic / 1073741824 }}
            {{ limit_gb = traffic_limit / 1073741824 }}
            {{ used_str = used_gb | format('%.2f') }}
            {{ limit_str = limit_gb | format('%.2f') }}
            {{ pct_str = usage_percent | format('%.1f') }}
            
            {{# Формируем сообщение #}}
            {{ msg = "📊 <b>Статус трафика</b>\n\n" }}
            {{ msg = msg _ "├ Использовано: <b>" _ used_str _ " GB</b>\n" }}
            {{ msg = msg _ "├ Лимит: <b>" _ limit_str _ " GB</b>\n" }}
            {{ msg = msg _ "└ Процент: <b>" _ pct_str _ "%</b>\n\n" }}
            
            {{ IF remna_user.status == 'LIMITED' }}
                {{ msg = msg _ "🚫 <b>Статус: лимит исчерпан!</b>\n\n" }}
            {{ ELSIF usage_percent >= 90 }}
                {{ msg = msg _ "⚠️ <b>Статус: почти исчерпан!</b>\n\n" }}
            {{ ELSE }}
                {{ msg = msg _ "✅ <b>Статус: активен</b>\n\n" }}
            {{ END }}
            
            {{ msg = msg _ "💰 Сброс трафика: <b>" _ RESET_COST _ "₽</b>\n" }}
            {{ msg = msg _ "💳 Ваш баланс: <b>" _ user.balance _ "₽</b>" }}
            
            {{# Кнопки #}}
            {{ webapp_url = config.api.url _ '/shm/v1/public/payment?format=html&user_id=' _ user.user_id }}
            {{ keyboard = {
                'inline_keyboard' => [
                    [
                        { 'text' => '🔄 Сбросить трафик за ' _ RESET_COST _ '₽', 'callback_data' => '/reset_traffic' }
                    ],
                    [
                        { 'text' => '✚ Пополнить баланс', 'web_app' => { 'url' => webapp_url } }
                    ],
                    [
                        { 'text' => '🔙 Назад', 'callback_data' => '/start' }
                    ]
                ]
            } }}
            
            {{# Отправляем #}}
            {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
            {{ send_result = http.post(tg_url, 'content', { 
                'chat_id' => telegram_id, 
                'text' => msg, 
                'parse_mode' => 'HTML',
                'reply_markup' => keyboard
            }) }}
            
            {
                "status": 1,
                "action": "traffic_status",
                "message": "Status sent to Telegram",
                "telegram_id": "{{ telegram_id }}",
                "traffic": {
                    "used_gb": {{ used_str }},
                    "limit_gb": {{ limit_str }},
                    "percent": {{ pct_str }}
                }
            }
        {{ END }}
    {{ END }}

{{# ============== ACTION: RESET ============== #}}
{{# Сброс трафика с созданием мгновенной услуги (учёт в биллинге) #}}

{{ ELSIF action == 'reset' }}

    {{ IF !user.id }}
        { "status": 0, "error": "Authorization required", "code": "AUTH_REQUIRED" }
    {{ ELSIF !confirm }}
        { 
            "status": 0, 
            "error": "Confirmation required. Add confirm=1 to proceed", 
            "code": "CONFIRM_REQUIRED",
            "cost": {{ RESET_COST }},
            "message": "Сброс трафика будет стоить {{ RESET_COST }}₽. Подтвердите действие."
        }
    {{ ELSE }}
        
        {{# ID мгновенной услуги "Сброс трафика" (period=0, next=-1) #}}
        {{ TRAFFIC_RESET_SERVICE_ID = 30 }}
        
        {{# Находим активную VPN услугу пользователя для поиска в Remna #}}
        {{ user_service_id = '' }}
        {{ telegram_id = '' }}
        {{ vpn_services = user.services.list({'category' => 'vpn', 'status' => 'ACTIVE'}) }}
        {{ FOREACH vs IN vpn_services }}
            {{ vpn_storage_key = "vpn_mrzb_" _ vs.user_service_id }}
            {{ vpn_data = storage.read(vpn_storage_key) }}
            {{ IF vpn_data.response.telegramId }}
                {{ user_service_id = vs.user_service_id }}
                {{ telegram_id = vpn_data.response.telegramId }}
                {{ LAST }}
            {{ END }}
        {{ END }}
        
        {{# Если не нашли через storage, пробуем по категории vpn-m-% #}}
        {{ IF !user_service_id }}
            {{ vpn_services2 = ref(user.services.list_for_api('category', 'vpn-m-%')) }}
            {{ FOREACH vs IN vpn_services2 }}
                {{ IF vs.status == 'ACTIVE' }}
                    {{ user_service_id = vs.user_service_id }}
                    {{ vpn_storage_key = "vpn_mrzb_" _ vs.user_service_id }}
                    {{ vpn_data = storage.read(vpn_storage_key) }}
                    {{ IF vpn_data.response.telegramId }}
                        {{ telegram_id = vpn_data.response.telegramId }}
                    {{ END }}
                    {{ LAST }}
                {{ END }}
            {{ END }}
        {{ END }}
        
        {{ IF !user_service_id }}
            { "status": 0, "error": "No active VPN service found", "code": "NO_VPN_SERVICE" }
        {{ ELSE }}
        
            {{# Ищем пользователя в Remna #}}
            {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
            {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
            {{ users = users_response.response.users || [] }}
            
            {{ remna_user = {} }}
            {{ shm_username = 'HQVPN_' _ user_service_id }}
            {{ FOREACH u IN users }}
                {{ IF u.username == shm_username }}
                    {{ remna_user = u }}
                {{ END }}
            {{ END }}
            
            {{# Пробуем us_ формат #}}
            {{ IF !remna_user.uuid }}
                {{ shm_username = 'us_' _ user_service_id }}
                {{ FOREACH u IN users }}
                    {{ IF u.username == shm_username }}
                        {{ remna_user = u }}
                    {{ END }}
                {{ END }}
            {{ END }}
            
            {{ IF !remna_user.uuid }}
                { "status": 0, "error": "User not found in Remna", "code": "USER_NOT_FOUND", "searched": "{{ shm_username }}" }
            {{ ELSIF user.balance < RESET_COST }}
                { 
                    "status": 0, 
                    "error": "Insufficient balance", 
                    "code": "NO_BALANCE",
                    "balance": {{ user.balance }},
                    "required": {{ RESET_COST }}
                }
            {{ ELSE }}
                
                {{ short_uuid = remna_user.uuid.substr(0, 8) }}
                {{ storage_key = STORAGE_PREFIX _ short_uuid }}
                {{ traffic_data = storage.read('name', storage_key) || {} }}
                {{ last_reset_time = traffic_data.last_reset_time || 0 }}
                
                {{# Проверяем cooldown #}}
                {{ time_since_reset = current_time - last_reset_time }}
                
                {{ IF time_since_reset < RESET_COOLDOWN && last_reset_time > 0 }}
                    {{ cooldown_remaining = RESET_COOLDOWN - time_since_reset }}
                    { 
                        "status": 0, 
                        "error": "Reset cooldown active", 
                        "code": "COOLDOWN",
                        "cooldown_remaining": {{ cooldown_remaining }},
                        "message": "Сброс доступен через {{ cooldown_remaining }} сек."
                    }
                {{ ELSE }}
                    
                    {{# Сохраняем старое значение трафика для логов #}}
                    {{ user_traffic_obj = remna_user.userTraffic || {} }}
                    {{ old_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
                    {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
                    {{ old_status = remna_user.status }}
                    {{ old_balance = user.balance }}
                    {{ old_bonus = user.get_bonus }}
                    {{ total_available = old_balance + old_bonus }}
                    
                    {{# Проверка достаточности средств #}}
                    {{ IF total_available < RESET_COST }}
                        {{ need_more = RESET_COST - total_available }}
                        
                        {{# Уведомляем пользователя что не хватает средств #}}
                        {{ IF telegram_id && TG_TOKEN }}
                            {{ msg = "❌ <b>Недостаточно средств для сброса трафика</b>\n\n" }}
                            {{ msg = msg _ "💰 Стоимость сброса: <b>" _ RESET_COST _ "₽</b>\n" }}
                            {{ msg = msg _ "💳 Ваш баланс: <b>" _ old_balance _ "₽</b>\n" }}
                            {{ msg = msg _ "🎁 Бонусы: <b>" _ old_bonus _ "₽</b>\n" }}
                            {{ msg = msg _ "📊 Всего доступно: <b>" _ total_available _ "₽</b>\n\n" }}
                            {{ msg = msg _ "⚠️ Не хватает: <b>" _ need_more _ "₽</b>\n\n" }}
                            {{ msg = msg _ "👉 Пополните баланс и попробуйте снова!" }}
                            
                            {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                            {{ send = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => msg, 'parse_mode' => 'HTML' }) }}
                        {{ END }}
                        
                        { 
                            "status": 0, 
                            "error": "Insufficient funds", 
                            "code": "INSUFFICIENT_FUNDS",
                            "message": "Недостаточно средств. Пополните баланс.",
                            "balance": {{ old_balance }},
                            "bonus": {{ old_bonus }},
                            "total_available": {{ total_available }},
                            "required": {{ RESET_COST }},
                            "need_more": {{ need_more }}
                        }
                    {{ ELSE }}
                    
                    {{# 1. Создаём мгновенную услугу (учёт в биллинге) #}}
                    {{ created_us = user.us.create('service_id', TRAFFIC_RESET_SERVICE_ID, 'check_allow_to_order', 0) }}
                    
                    {{# 2. Принудительно обрабатываем услугу биллингом (списание денег) #}}
                    {{ IF created_us }}
                        {{ us_obj = us.id(created_us.user_service_id) }}
                        
                        {{# Меняем статус с PROGRESS на INIT чтобы биллинг обработал #}}
                        {{ set_init = us_obj.set('status', 'INIT') }}
                        
                        {{ billing_result = us_obj.touch() }}
                        
                        {{# Перезагружаем данные пользователя для проверки баланса #}}
                        {{ user_reloaded = user.id(user.user_id) }}
                        {{ new_balance = user_reloaded.balance }}
                        {{ paid = (old_balance > new_balance) }}
                    {{ END }}
                    
                    {{ IF created_us && paid }}
                        
                        {{# 3. Сбрасываем трафик в Remna #}}
                        {{ reset_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid _ "/actions/reset-traffic" }}
                        {{ reset_result = http.post(reset_url, 'headers', { 'Authorization' => auth_header }) }}
                        
                        {{ IF reset_result.response }}
                            
                            {{# 3. Если статус был LIMITED, меняем на ACTIVE #}}
                            {{ IF old_status == 'LIMITED' }}
                                {{ activate_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid }}
                                {{ activate_result = http.patch(activate_url, 'headers', { 'Authorization' => auth_header }, 'content', { 'status' => 'ACTIVE' }) }}
                            {{ END }}
                            
                            {{# 4. Обновляем storage #}}
                            {{ traffic_data.last_reset_time = current_time }}
                            {{ traffic_data.reset_count = (traffic_data.reset_count || 0) + 1 }}
                            {{ traffic_data.notified_95 = 0 }}
                            {{ traffic_data.notified_limit = 0 }}
                            {{ save_storage = storage.save(storage_key, traffic_data) }}
                            
                            {{# Форматируем для сообщений #}}
                            {{ old_gb = old_traffic / 1073741824 }}
                            {{ limit_gb = traffic_limit / 1073741824 }}
                            {{ old_gb_str = old_gb | format('%.2f') }}
                            {{ limit_gb_str = limit_gb | format('%.2f') }}
                            
                            {{# 5. Уведомляем пользователя в Telegram #}}
                            {{ IF telegram_id && TG_TOKEN }}
                                {{ msg = "✅ <b>Трафик успешно сброшен!</b>\n\n" }}
                                {{ msg = msg _ "💰 Списано: <b>" _ RESET_COST _ "₽</b>\n" }}
                                {{ msg = msg _ "💳 Остаток: <b>" _ new_balance _ "₽</b>\n\n" }}
                                {{ msg = msg _ "📊 Было использовано: <b>" _ old_gb_str _ " GB</b>\n" }}
                                {{ msg = msg _ "📦 Лимит: <b>" _ limit_gb_str _ " GB</b>\n\n" }}
                                {{ msg = msg _ "🎉 Приятного использования!" }}
                                
                                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                                {{ send = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => msg, 'parse_mode' => 'HTML' }) }}
                            {{ END }}
                            
                            {{# 6. Логируем админу #}}
                            {{ IF ADMIN_CHAT_ID && TG_TOKEN }}
                                {{ admin_msg = "🔄 <b>Сброс трафика</b>\n\n" }}
                                {{ admin_msg = admin_msg _ "👤 Пользователь: <code>" _ remna_user.username _ "</code>\n" }}
                                {{ admin_msg = admin_msg _ "🆔 SHM ID: " _ user.id _ "\n" }}
                                {{ admin_msg = admin_msg _ "💰 Списано: " _ RESET_COST _ "₽\n" }}
                                {{ admin_msg = admin_msg _ "📊 Было: " _ old_gb_str _ " GB / " _ limit_gb_str _ " GB\n" }}
                                {{ admin_msg = admin_msg _ "🔢 Всего сбросов: " _ traffic_data.reset_count }}
                                
                                {{ admin_tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                                {{ admin_send = http.post(admin_tg_url, 'content', { 
                                    'chat_id' => ADMIN_CHAT_ID, 
                                    'message_thread_id' => ADMIN_THREAD_ID,
                                    'text' => admin_msg, 
                                    'parse_mode' => 'HTML' 
                                }) }}
                            {{ END }}
                            
                            {
                                "status": 1,
                                "action": "reset",
                                "message": "Traffic reset successful",
                                "user": {
                                    "shm_id": {{ user.id }},
                                    "remna_uuid": "{{ remna_user.uuid }}",
                                    "remna_username": "{{ remna_user.username }}",
                                    "telegram_id": "{{ telegram_id }}"
                                },
                                "billing": {
                                    "service_id": {{ TRAFFIC_RESET_SERVICE_ID }},
                                    "cost": {{ RESET_COST }},
                                    "old_balance": {{ old_balance }},
                                    "new_balance": {{ new_balance }}
                                },
                                "traffic": {
                                    "old_used_gb": "{{ old_gb_str }}",
                                    "limit_gb": "{{ limit_gb_str }}",
                                    "was_limited": {{ IF old_status == 'LIMITED' }}true{{ ELSE }}false{{ END }}
                                },
                                "stats": {
                                    "reset_count": {{ traffic_data.reset_count }}
                                }
                            }
                        {{ ELSE }}
                            {{# Remna API ошибка #}}
                            { 
                                "status": 0, 
                                "error": "Failed to reset traffic in Remna", 
                                "code": "REMNA_ERROR",
                                "message": "Произошла ошибка при сбросе трафика. Услуга создана, обратитесь в поддержку."
                            }
                        {{ END }}
                    {{ ELSE }}
                        {{# Услуга не создана или не оплачена #}}
                        { 
                            "status": 0, 
                            "error": "Failed to create or pay for service", 
                            "code": "SERVICE_ERROR",
                            "message": "Не удалось создать или оплатить услугу. Проверьте баланс.",
                            "balance": {{ user.balance }},
                            "required": {{ RESET_COST }}
                        }
                    {{ END }}
                    {{ END }} {{# END IF total_available >= RESET_COST #}}
                {{ END }}
            {{ END }}
        {{ END }}
    {{ END }}

{{# ============== ACTION: TEST ============== #}}
{{# Тестовое уведомление для конкретного пользователя по username Remna #}}
{{# ?action=test&username=HQVPN_5627 #}}

{{ ELSIF action == 'test' }}

    {{ test_username = req.params.username || '' }}
    
    {{ IF !test_username }}
        { "status": 0, "error": "Parameter 'username' required", "code": "MISSING_PARAM" }
    {{ ELSE }}
        
        {{# Получаем пользователя из Remna #}}
        {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
        {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
        {{ users = users_response.response.users || [] }}
        
        {{ remna_user = {} }}
        {{ FOREACH u IN users }}
            {{ IF u.username == test_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
        
        {{ IF !remna_user.uuid }}
            { "status": 0, "error": "User not found in Remna", "code": "USER_NOT_FOUND", "username": "{{ test_username }}" }
        {{ ELSE }}
            
            {{ username = remna_user.username }}
            {{ user_uuid = remna_user.uuid }}
            {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
            {{# Трафик находится во вложенном объекте userTraffic #}}
            {{ user_traffic_obj = remna_user.userTraffic || {} }}
            {{ used_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
            {{ usage_percent = 0 }}
            {{ IF traffic_limit > 0 }}
                {{ usage_percent = (used_traffic / traffic_limit) * 100 }}
            {{ END }}
            
            {{# === ПОИСК TELEGRAM ID === #}}
            {{ telegram_id = '' }}
            {{ user_service_id = '' }}
            {{ shm_user_id = '' }}
            {{ shm_full_name = '' }}
            
            {{# 1. Парсим user_service_id из username #}}
            {{ uname_match = username.match('^.+_([0-9]+)$') }}
            {{ IF uname_match.0 }}
                {{ user_service_id = uname_match.0 }}
                {{ tmp_us_obj = us.id(user_service_id) }}
                {{ IF tmp_us_obj }}
                    {{ shm_user_id = tmp_us_obj.user_id }}
                    {{ shm_user_obj = user.id(shm_user_id) }}
                    {{ IF shm_user_obj }}
                        {{ shm_full_name = shm_user_obj.full_name }}
                    {{ END }}
                {{ END }}
            {{ END }}
            
            {{# 2. Ищем в storage #}}
            {{ IF user_service_id }}
                {{ vpn_storage_key = "vpn_mrzb_" _ user_service_id }}
                {{ st_data = storage.read('name', vpn_storage_key) }}
                {{ IF st_data && st_data.response }}
                    {{ telegram_id = st_data.response.telegramId || '' }}
                {{ END }}
            {{ END }}
            
            {{# 3. Fallback: description #}}
            {{ IF !telegram_id }}
                {{ desc = remna_user.description || '' }}
                {{ tg_match = desc.match('@([0-9]+)') }}
                {{ IF tg_match.0 }}
                    {{ telegram_id = tg_match.0 }}
                {{ END }}
            {{ END }}
            
            {{ IF !telegram_id }}
                { 
                    "status": 0, 
                    "error": "Telegram ID not found for user", 
                    "code": "NO_TELEGRAM",
                    "username": "{{ username }}",
                    "user_service_id": "{{ user_service_id }}",
                    "shm_user_id": "{{ shm_user_id }}"
                }
            {{ ELSE }}
                
                {{# Форматируем трафик #}}
                {{ used_gb = used_traffic / 1073741824 }}
                {{ limit_gb = traffic_limit / 1073741824 }}
                {{ used_str = used_gb | format('%.2f') }}
                {{ limit_str = limit_gb | format('%.2f') }}
                {{ pct_str = usage_percent | format('%.1f') }}
                
                {{# Формируем тестовое сообщение #}}
                {{ msg = "🧪 <b>ТЕСТОВОЕ УВЕДОМЛЕНИЕ</b>\n\n" }}
                {{ IF shm_full_name }}
                    {{ msg = msg _ "👤 " _ shm_full_name _ "\n\n" }}
                {{ END }}
                {{ msg = msg _ "📊 <b>Статус трафика:</b>\n" }}
                {{ msg = msg _ "├ Использовано: <b>" _ used_str _ " GB</b>\n" }}
                {{ msg = msg _ "├ Лимит: <b>" _ limit_str _ " GB</b>\n" }}
                {{ msg = msg _ "└ Процент: <b>" _ pct_str _ "%</b>\n\n" }}
                
                {{ IF remna_user.status == 'LIMITED' }}
                    {{ msg = msg _ "🚫 <b>Лимит исчерпан!</b>\n\n" }}
                {{ ELSIF usage_percent >= 90 }}
                    {{ msg = msg _ "⚠️ <b>Почти исчерпан!</b>\n\n" }}
                {{ ELSE }}
                    {{ msg = msg _ "✅ <b>Статус: активен</b>\n\n" }}
                {{ END }}
                
                {{ msg = msg _ "💰 Сброс трафика: <b>" _ RESET_COST _ "₽</b>" }}
                
                {{# Кнопка для сброса #}}
                {{ webapp_url = config.api.url _ '/shm/v1/public/payment?format=html&user_id=' _ shm_user_id }}
                {{ keyboard = {
                    'inline_keyboard' => [
                        [
                            { 'text' => '🔄 Сбросить трафик за ' _ RESET_COST _ '₽', 'callback_data' => '/reset_traffic' }
                        ],
                        [
                            { 'text' => '✚ Пополнить баланс', 'web_app' => { 'url' => webapp_url } }
                        ],
                        [
                            { 'text' => '📊 Статус трафика', 'callback_data' => '/traffic_status' }
                        ],
                        [
                            { 'text' => '🔙 Назад', 'callback_data' => '/start' }
                        ]
                    ]
                } }}
                
                {{# Отправляем #}}
                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                {{ send_result = http.post(tg_url, 'content', { 
                    'chat_id' => telegram_id, 
                    'text' => msg, 
                    'parse_mode' => 'HTML',
                    'reply_markup' => keyboard
                }) }}
                
                {
                    "status": 1,
                    "action": "test",
                    "message": "Test notification sent",
                    "user": {
                        "remna_username": "{{ username }}",
                        "remna_uuid": "{{ user_uuid }}",
                        "remna_status": "{{ remna_user.status }}",
                        "user_service_id": "{{ user_service_id }}",
                        "shm_user_id": "{{ shm_user_id }}",
                        "shm_full_name": "{{ shm_full_name }}",
                        "telegram_id": "{{ telegram_id }}"
                    },
                    "traffic": {
                        "used_gb": {{ used_str }},
                        "limit_gb": {{ limit_str }},
                        "usage_percent": {{ pct_str }}
                    },
                    "telegram_response": {{ IF send_result.ok }}true{{ ELSE }}false{{ END }}
                }
            {{ END }}
        {{ END }}
    {{ END }}

{{# ============== ACTION: TEST_RESET ============== #}}
{{# Тестовый сброс трафика (без списания денег) #}}
{{# ?action=test_reset&username=HQVPN_5627 #}}

{{ ELSIF action == 'test_reset' }}

    {{ test_username = req.params.username || '' }}
    
    {{ IF !test_username }}
        { "status": 0, "error": "Parameter 'username' required", "code": "MISSING_PARAM" }
    {{ ELSE }}
        
        {{# Получаем пользователя из Remna #}}
        {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
        {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
        {{ users = users_response.response.users || [] }}
        
        {{ remna_user = {} }}
        {{ FOREACH u IN users }}
            {{ IF u.username == test_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
        
        {{ IF !remna_user.uuid }}
            { "status": 0, "error": "User not found in Remna", "code": "USER_NOT_FOUND", "username": "{{ test_username }}" }
        {{ ELSE }}
            
            {{ user_traffic_obj = remna_user.userTraffic || {} }}
            {{ old_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
            {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
            {{ old_status = remna_user.status }}
            
            {{# Сбрасываем трафик в Remna #}}
            {{ reset_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid _ "/actions/reset-traffic" }}
            {{ reset_result = http.post(reset_url, 'headers', { 'Authorization' => auth_header }) }}
            
            {{# Если статус LIMITED - активируем #}}
            {{ activate_result = {} }}
            {{ IF remna_user.status == 'LIMITED' }}
                {{ activate_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid }}
                {{ activate_result = http.patch(activate_url, 'headers', { 'Authorization' => auth_header }, 'content', { 'status' => 'ACTIVE' }) }}
            {{ END }}
            
            {{# Получаем обновлённые данные #}}
            {{ user_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid }}
            {{ updated_user = http.get(user_url, 'headers', { 'Authorization' => auth_header }) }}
            {{ new_traffic_obj = updated_user.response.userTraffic || {} }}
            {{ new_traffic = new_traffic_obj.usedTrafficBytes || 0 }}
            {{ new_status = updated_user.response.status || old_status }}
            
            {
                "status": 1,
                "action": "test_reset",
                "message": "Traffic reset test completed",
                "user": {
                    "username": "{{ test_username }}",
                    "uuid": "{{ remna_user.uuid }}"
                },
                "before": {
                    "used_bytes": {{ old_traffic }},
                    "status": "{{ old_status }}"
                },
                "after": {
                    "used_bytes": {{ new_traffic }},
                    "status": "{{ new_status }}"
                },
                "api_responses": {
                    "reset": {{ toJson(reset_result) }},
                    "activate": {{ toJson(activate_result) }}
                }
            }
        {{ END }}
    {{ END }}

{{# ============== ACTION: TEST_BILLING ============== #}}
{{# Тест биллинга - создание услуги и списание (без сброса трафика) #}}
{{# ?action=test_billing #}}

{{ ELSIF action == 'test_billing' }}

    {{ old_balance = user.balance }}
    {{ old_bonus = user.get_bonus }}
    {{ total_available = old_balance + old_bonus }}
    
    {{ IF total_available < RESET_COST }}
        {
            "status": 0,
            "error": "Insufficient funds for test",
            "balance": {{ old_balance }},
            "bonus": {{ old_bonus }},
            "total_available": {{ total_available }},
            "required": {{ RESET_COST }}
        }
    {{ ELSE }}
        {{ created_us = user.us.create('service_id', TRAFFIC_RESET_SERVICE_ID, 'check_allow_to_order', 0) }}
        
        {{ IF created_us }}
            {{ us_obj = us.id(created_us.user_service_id) }}
            {{ set_init = us_obj.set('status', 'INIT') }}
            {{ billing_result = us_obj.touch() }}
            {{ user_reloaded = user.id(user.user_id) }}
            {{ new_balance = user_reloaded.balance }}
            {{ new_bonus = user_reloaded.get_bonus }}
            {{ paid = (old_balance + old_bonus) > (new_balance + new_bonus) }}
            {{ amount_deducted = (old_balance + old_bonus) - (new_balance + new_bonus) }}
            
            {
                "status": 1,
                "action": "test_billing",
                "user_id": {{ user.user_id }},
                "service_id": {{ TRAFFIC_RESET_SERVICE_ID }},
                "user_service_id": {{ created_us.user_service_id }},
                "before": {
                    "balance": {{ old_balance }},
                    "bonus": {{ old_bonus }},
                    "total": {{ total_available }}
                },
                "after": {
                    "balance": {{ new_balance }},
                    "bonus": {{ new_bonus }},
                    "total": {{ new_balance + new_bonus }}
                },
                "paid": {{ IF paid }}true{{ ELSE }}false{{ END }},
                "amount_deducted": {{ amount_deducted }}
            }
        {{ ELSE }}
            {
                "status": 0,
                "error": "Failed to create service"
            }
        {{ END }}
    {{ END }}

{{# ============== ACTION: DEBUG ============== #}}
{{# Показать полную структуру данных пользователя #}}
{{# ?action=debug&username=HQVPN_5627 #}}

{{ ELSIF action == 'debug' }}

    {{ test_username = req.params.username || '' }}
    
    {{ IF !test_username }}
        { "status": 0, "error": "Parameter 'username' required", "code": "MISSING_PARAM" }
    {{ ELSE }}
        
        {{# Получаем пользователя из Remna #}}
        {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
        {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
        {{ users = users_response.response.users || [] }}
        
        {{ remna_user = {} }}
        {{ FOREACH u IN users }}
            {{ IF u.username == test_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
        
        {{ IF !remna_user.uuid }}
            { "status": 0, "error": "User not found", "username": "{{ test_username }}" }
        {{ ELSE }}
            {{# Получаем детальную информацию по UUID #}}
            {{ user_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid }}
            {{ user_detail = http.get(user_url, 'headers', { 'Authorization' => auth_header }) }}
            
            {
                "status": 1,
                "action": "debug",
                "from_list": {{ toJson(remna_user) }},
                "from_detail": {{ toJson(user_detail) }}
            }
        {{ END }}
    {{ END }}

{{# ============== UNKNOWN ACTION ============== #}}

{{ ELSE }}
    { 
        "status": 0, 
        "error": "Unknown action: {{ action }}", 
        "code": "UNKNOWN_ACTION",
        "available_actions": ["check", "status", "reset", "test", "test_reset", "debug"]
    }
{{ END }}
