{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    TRAFFIC RESET EVENT TEMPLATE                               ║
║   Шаблон для события ACTIVATE мгновенной услуги "Сброс трафика VPN"          ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Этот шаблон срабатывает при активации (оплате) услуги "Сброс трафика VPN".
  Выполняет:
  1. Находит VPN аккаунт пользователя в Remna
  2. Сбрасывает трафик через API
  3. Активирует пользователя если был LIMITED
  4. Отправляет уведомление в Telegram

ПРИВЯЗКА:
  Услуга: "Сброс трафика VPN" (period=0, next=-1, cost=50)
  Событие: ACTIVATE
#}}

{{# ============== НАСТРОЙКИ ============== #}}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ" }}
{{ auth_header = "Bearer " _ REMNA_TOKEN }}

{{ TG_TOKEN = config.telegram.telegram_bot.token || "" }}
{{ VPN_STORAGE_PREFIX = "vpn_mrzb_" }}
{{ TRAFFIC_STORAGE_PREFIX = "traffic_" }}

{{# ============== ОСНОВНОЙ КОД ============== #}}
{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}

{{# Ищем активную VPN услугу пользователя #}}
{{ user_services = user.services.list({'category' => 'vpn', 'status' => 'ACTIVE'}) }}
{{ vpn_us = {} }}
{{ telegram_id = '' }}

{{ FOREACH us_item IN user_services }}
    {{ storage_key = VPN_STORAGE_PREFIX _ us_item.user_service_id }}
    {{ storage_data = storage.read(storage_key) }}
    {{ IF storage_data.response.telegramId }}
        {{ vpn_us = us_item }}
        {{ telegram_id = storage_data.response.telegramId }}
        {{ LAST }}
    {{ END }}
{{ END }}

{{# Если не нашли через storage, пробуем по категории vpn-m-% #}}
{{ IF !vpn_us.user_service_id }}
    {{ user_services = ref(user.services.list_for_api('category', 'vpn-m-%')) }}
    {{ FOREACH us_item IN user_services }}
        {{ IF us_item.status == 'ACTIVE' }}
            {{ vpn_us = us_item }}
            {{ storage_key = VPN_STORAGE_PREFIX _ us_item.user_service_id }}
            {{ storage_data = storage.read(storage_key) }}
            {{ IF storage_data.response.telegramId }}
                {{ telegram_id = storage_data.response.telegramId }}
            {{ END }}
            {{ LAST }}
        {{ END }}
    {{ END }}
{{ END }}

{{ IF vpn_us.user_service_id }}
    {{# Получаем пользователя из Remna #}}
    {{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
    {{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
    {{ users = users_response.response.users || [] }}
    
    {{ remna_user = {} }}
    {{ shm_username = 'HQVPN_' _ vpn_us.user_service_id }}
    
    {{ FOREACH u IN users }}
        {{ IF u.username == shm_username }}
            {{ remna_user = u }}
        {{ END }}
    {{ END }}
    
    {{# Пробуем us_ формат #}}
    {{ IF !remna_user.uuid }}
        {{ shm_username = 'us_' _ vpn_us.user_service_id }}
        {{ FOREACH u IN users }}
            {{ IF u.username == shm_username }}
                {{ remna_user = u }}
            {{ END }}
        {{ END }}
    {{ END }}
    
    {{ IF remna_user.uuid }}
        {{# Сохраняем старое значение трафика #}}
        {{ user_traffic_obj = remna_user.userTraffic || {} }}
        {{ old_traffic = user_traffic_obj.usedTrafficBytes || 0 }}
        {{ traffic_limit = remna_user.trafficLimitBytes || 0 }}
        {{ old_status = remna_user.status }}
        
        {{# Сбрасываем трафик #}}
        {{ reset_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid _ "/actions/reset-traffic" }}
        {{ reset_result = http.post(reset_url, 'headers', { 'Authorization' => auth_header }) }}
        
        {{ IF reset_result.response }}
            {{# Активируем если был LIMITED #}}
            {{ IF old_status == 'LIMITED' }}
                {{ activate_url = REMNA_HOST _ "/api/users/" _ remna_user.uuid }}
                {{ activate_result = http.patch(activate_url, 'headers', { 'Authorization' => auth_header }, 'content', { 'status' => 'ACTIVE' }) }}
            {{ END }}
            
            {{# Обновляем storage #}}
            {{ short_uuid = remna_user.uuid.substr(0, 8) }}
            {{ traffic_key = TRAFFIC_STORAGE_PREFIX _ short_uuid }}
            {{ traffic_data = storage.read(traffic_key) || {} }}
            {{ traffic_data.last_reset_time = current_time }}
            {{ traffic_data.reset_count = (traffic_data.reset_count || 0) + 1 }}
            {{ traffic_data.notified_95 = 0 }}
            {{ traffic_data.notified_limit = 0 }}
            {{ save_storage = storage.save(traffic_key, traffic_data) }}
            
            {{# Форматируем для уведомления #}}
            {{ old_gb = old_traffic / 1073741824 }}
            {{ limit_gb = traffic_limit / 1073741824 }}
            {{ old_gb_str = old_gb | format('%.2f') }}
            {{ limit_gb_str = limit_gb | format('%.2f') }}
            {{ cost = uss.cost || 50 }}
            
            {{# Отправляем уведомление в Telegram если есть telegram_id #}}
            {{ IF telegram_id && TG_TOKEN }}
                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                {{ tg_text = "✅ <b>Трафик успешно сброшен!</b>\n\n💰 Списано: <b>" _ cost _ "₽</b>\n📊 Было использовано: " _ old_gb_str _ " GB\n📦 Лимит: " _ limit_gb_str _ " GB\n\n🎉 Приятного использования!" }}
                {{ tg_result = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => tg_text, 'parse_mode' => 'HTML' }) }}
            {{ END }}
            
{
    "status": "success",
    "message": "Traffic reset successful",
    "old_traffic_bytes": {{ old_traffic }},
    "old_traffic_gb": "{{ old_gb_str }}",
    "limit_gb": "{{ limit_gb_str }}",
    "was_limited": {{ IF old_status == 'LIMITED' }}true{{ ELSE }}false{{ END }},
    "telegram_notified": {{ IF telegram_id }}true{{ ELSE }}false{{ END }}
}
        {{ ELSE }}
{
    "status": "error",
    "message": "Failed to reset traffic in Remna",
    "error": "{{ reset_result.error || 'Unknown error' }}"
}
        {{ END }}
    {{ ELSE }}
{
    "status": "error", 
    "message": "User not found in Remna",
    "searched_username": "{{ shm_username }}"
}
    {{ END }}
{{ ELSE }}
{
    "status": "error",
    "message": "No active VPN service found for user"
}
{{ END }}
