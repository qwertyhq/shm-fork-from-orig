{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    HWID BLOCKER TEMPLATE v1.0                                 ║
║         Автоматическая блокировка/разблокировка при превышении HWID          ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Быстрая проверка HWID лимитов и автоблокировка.
  Запускать каждые 30-60 секунд через spool/cron.
  
  - devices > limit → БЛОК (после 5 предупреждений)
  - devices <= limit И был заблокирован нами → РАЗБЛОК

STORAGE КЛЮЧИ (hf_{short_uuid}):
  hwid_exceeded: 1/0
  hwid_warn_count: 0-5 (счётчик предупреждений)
  hwid_blocked: 1/0 (заблокирован ли нами)
  hwid_blocked_at: timestamp
#}}

{{# === НАСТРОЙКИ === #}}
{{ BLOCK_ENABLED = true }}      {{# Включить автоблокировку #}}
{{ BLOCK_AFTER_WARNS = 5 }}     {{# После скольки предупреждений блокировать #}}
{{ STORAGE_PREFIX = "vpn_mrzb_" }}

{{# === WHITELIST: персональные лимиты устройств === #}}
{{# Формат: username Remnawave => лимит устройств #}}
{{ WHITELIST = {
    'us_1174' => 10
} }}

{{# === ПОЛНОЕ ИСКЛЮЧЕНИЕ ПО USERNAME REMNAWAVE === #}}
{{# Эти пользователи полностью исключены из проверки HWID #}}
{{ REMNA_WHITELIST = ['Kris_Family', 'ABZ_TEAM'] }}

{{# === СЕМЕЙНЫЕ ПОДПИСКИ: не проверять HWID === #}}
{{# service_id услуг с безлимитом устройств #}}
{{ FAMILY_SERVICES = [28, 29] }}

{{# === ИСКЛЮЧЕНИЯ ПО USER_ID: не проверять HWID === #}}
{{# SHM user_id пользователей которых не трогаем #}}
{{ USER_WHITELIST = [197,3545,1878] }}

{{# Telegram для уведомлений о блокировке #}}
{{ TG_TOKEN = config.telegram.telegram_bot.token || config.telegram.token || "" }}

{{# === REMNAWAVE API === #}}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ" }}
{{ auth_header = "Bearer " _ REMNA_TOKEN }}

{{# Получаем всех пользователей #}}
{{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
{{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
{{ users = users_response.response.users || [] }}

{{# Получаем все HWID устройства #}}
{{ hwid_url = REMNA_HOST _ "/api/hwid/devices?size=1000" }}
{{ hwid_response = http.get(hwid_url, 'headers', { 'Authorization' => auth_header }) }}
{{ devices = hwid_response.response.devices || [] }}

{{# Считаем устройства по пользователям #}}
{{ device_counts = {} }}
{{ FOREACH device IN devices }}
    {{ dev_user_uuid = device.userUuid }}
    {{ IF !device_counts.$dev_user_uuid }}
        {{ device_counts.$dev_user_uuid = 0 }}
    {{ END }}
    {{ device_counts.$dev_user_uuid = device_counts.$dev_user_uuid + 1 }}
{{ END }}

{{# === ПРОВЕРЯЕМ КАЖДОГО ПОЛЬЗОВАТЕЛЯ === #}}
{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}
{{ blocked_count = 0 }}
{{ unblocked_count = 0 }}
{{ results = [] }}
{{ exceeding_users = [] }}

{{ FOREACH u IN users }}
    {{ user_uuid = u.uuid }}
    {{ username = u.username }}
    {{ user_status = u.status }}
    
    {{# Проверяем полное исключение по username Remnawave #}}
    {{ is_remna_whitelisted = 0 }}
    {{ FOREACH rw_user IN REMNA_WHITELIST }}
        {{ IF username == rw_user }}
            {{ is_remna_whitelisted = 1 }}
        {{ END }}
    {{ END }}
    {{ NEXT IF is_remna_whitelisted }}
    
    {{# Проверяем семейную подписку и whitelist по user_id - пропускаем проверку HWID #}}
    {{ is_family = 0 }}
    {{ is_whitelisted_user = 0 }}
    {{ uname_check = username.match('^.+_([0-9]+)$') }}
    {{ IF uname_check.0 }}
        {{ check_us_id = uname_check.0 }}
        {{ check_us_obj = us.id(check_us_id) }}
        {{ IF check_us_obj }}
            {{# Проверяем service_id на семейную подписку #}}
            {{ check_sid = check_us_obj.service_id + 0 }}
            {{ FOREACH fam_sid IN FAMILY_SERVICES }}
                {{ IF check_sid == fam_sid }}
                    {{ is_family = 1 }}
                {{ END }}
            {{ END }}
            {{# Проверяем user_id на whitelist #}}
            {{ check_uid = check_us_obj.user_id + 0 }}
            {{ FOREACH wl_uid IN USER_WHITELIST }}
                {{ IF check_uid == wl_uid }}
                    {{ is_whitelisted_user = 1 }}
                {{ END }}
            {{ END }}
        {{ END }}
    {{ END }}
    {{ NEXT IF is_family }}
    {{ NEXT IF is_whitelisted_user }}
    {{# Проверяем whitelist, иначе берём лимит из API или дефолт 5 #}}
    {{ hwid_limit = WHITELIST.$username || u.hwidDeviceLimit || 5 }}
    {{ device_count = device_counts.$user_uuid || 0 }}
    {{ short_uuid = user_uuid.substr(0, 8) }}
    {{ hwid_flag_key = "hf_" _ short_uuid }}
    
    {{# Читаем флаг из storage #}}
    {{ flag_data = storage.read('name', hwid_flag_key) }}
    {{ warn_count = (flag_data.hwid_warn_count || 0) + 0 }}  {{# +0 для преобразования строки в число #}}
    {{ is_blocked_by_us = (flag_data.hwid_blocked || 0) + 0 }}
    
    {{# Парсим telegram_id из description #}}
    {{ telegram_id = '' }}
    {{ desc = u.description || '' }}
    {{ tg_match = desc.match('@([0-9]+)') }}
    {{ IF tg_match.0 }}
        {{ telegram_id = tg_match.0 }}
    {{ END }}
    
    {{# === ПРОВЕРКА ПРЕВЫШЕНИЯ === #}}
    {{ IF device_count > hwid_limit }}
        
        {{# Добавляем в debug список #}}
        {{ exceeding_users.push({
            'user' => username,
            'devices' => device_count,
            'limit' => hwid_limit,
            'warns' => warn_count,
            'status' => user_status,
            'blocked_by_us' => is_blocked_by_us,
            'needs_warns' => BLOCK_AFTER_WARNS - warn_count,
            'storage_key' => hwid_flag_key,
            'short_uuid' => short_uuid,
            'flag_data_raw' => flag_data
        }) }}
        
        {{# Пользователь превышает лимит #}}
        {{ IF BLOCK_ENABLED && warn_count >= BLOCK_AFTER_WARNS && user_status == 'ACTIVE' }}
            
            {{# БЛОКИРУЕМ! #}}
            {{ block_url = REMNA_HOST _ "/api/users/" _ user_uuid }}
            {{ block_result = http.patch(block_url, 'headers', { 'Authorization' => auth_header }, 'content', { 'status' => 'DISABLED' }) }}
            
            {{ IF block_result.response }}
                {{ blocked_count = blocked_count + 1 }}
                
                {{# Обновляем флаг в storage #}}
                {{ save_flag = storage.save(hwid_flag_key, {
                    'hwid_exceeded' => 1,
                    'hwid_warn_count' => warn_count,
                    'hwid_blocked' => 1,
                    'hwid_blocked_at' => current_time,
                    'hwid_device_count' => device_count,
                    'hwid_device_limit' => hwid_limit,
                    'username' => username,
                    'remna_uuid' => user_uuid
                }) }}
                
                {{# Уведомляем пользователя о блокировке #}}
                {{ IF telegram_id }}
                    {{ block_msg = "🚫 <b>Ваш аккаунт заблокирован!</b>\n\n" }}
                    {{ block_msg = block_msg _ "Причина: превышение лимита устройств после " _ warn_count _ " предупреждений.\n\n" }}
                    {{ block_msg = block_msg _ "📱 Устройств: <b>" _ device_count _ "</b> из <b>" _ hwid_limit _ "</b> разрешенных\n\n" }}
                    {{ block_msg = block_msg _ "━━━━━━━━━━━━━━━━━━━━━\n" }}
                    {{ block_msg = block_msg _ "<b>Чтобы разблокировать:</b>\n" }}
                    {{ block_msg = block_msg _ "1️⃣ Удалите лишние устройства\n" }}
                    {{ block_msg = block_msg _ "2️⃣ Разблокировка автоматически (до 1 мин)\n\n" }}
                    {{ block_msg = block_msg _ "━━━━━━━━━━━━━━━━━━━━━\n" }}
                    {{ block_msg = block_msg _ "👨‍👩‍👧‍👦 <b>Надоели ограничения?</b>\n" }}
                    {{ block_msg = block_msg _ "Переходите на семейный тариф:\n" }}
                    {{ block_msg = block_msg _ "├ 📱 <b>10 устройств</b>\n" }}
                    {{ block_msg = block_msg _ "├ ♾️ <b>Безлимитный трафик</b>\n" }}
                    {{ block_msg = block_msg _ "└ 🚫 <b>Без блокировок</b>" }}
                    
                    {{# Inline-кнопка для открытия веб-приложения #}}
                    {{ block_keyboard = {
                        'inline_keyboard' => [
                            [
                                {
                                    'text' => '👨‍👩‍👧‍👦 Оформить семейный тариф',
                                    'url' => 'https://t.me/hq_vpn_bot/web'
                                }
                            ]
                        ]
                    } }}
                    
                    {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                    {{ send = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => block_msg, 'parse_mode' => 'HTML', 'reply_markup' => block_keyboard }) }}
                {{ END }}
                
                {{ results.push({
                    'user' => username,
                    'action' => 'BLOCKED',
                    'devices' => device_count,
                    'limit' => hwid_limit,
                    'warns' => warn_count
                }) }}
            {{ END }}
        {{ END }}
        
    {{ ELSE }}
        
        {{# Устройств <= лимита #}}
        {{ IF is_blocked_by_us && user_status == 'DISABLED' }}
            
            {{# РАЗБЛОКИРУЕМ! #}}
            {{ unblock_url = REMNA_HOST _ "/api/users/" _ user_uuid }}
            {{ unblock_result = http.patch(unblock_url, 'headers', { 'Authorization' => auth_header }, 'content', { 'status' => 'ACTIVE' }) }}
            
            {{ IF unblock_result.response }}
                {{ unblocked_count = unblocked_count + 1 }}
                
                {{# Сбрасываем флаги в storage #}}
                {{ save_flag = storage.save(hwid_flag_key, {
                    'hwid_exceeded' => 0,
                    'hwid_warn_count' => 0,
                    'hwid_blocked' => 0,
                    'hwid_unblocked_at' => current_time,
                    'hwid_device_count' => device_count,
                    'hwid_device_limit' => hwid_limit,
                    'username' => username,
                    'remna_uuid' => user_uuid
                }) }}
                
                {{# Уведомляем пользователя о разблокировке #}}
                {{ IF telegram_id }}
                    {{ msg = "✅ <b>Подписка восстановлена!</b>\n\n" }}
                    {{ msg = msg _ "Спасибо что привели аккаунт в норму.\n" }}
                    {{ msg = msg _ "📱 Устройств: <b>" _ device_count _ "</b> из <b>" _ hwid_limit _ "</b>\n\n" }}
                    {{ msg = msg _ "Приятного использования! 🎉" }}
                    
                    {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                    {{ send = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => msg, 'parse_mode' => 'HTML' }) }}
                {{ END }}
                
                {{ results.push({
                    'user' => username,
                    'action' => 'UNBLOCKED',
                    'devices' => device_count,
                    'limit' => hwid_limit
                }) }}
            {{ END }}
        {{ END }}
    {{ END }}
{{ END }}

{{# === РЕЗУЛЬТАТ === #}}
{
    "status": 1,
    "block_enabled": {{ BLOCK_ENABLED ? 'true' : 'false' }},
    "block_after_warns": {{ BLOCK_AFTER_WARNS }},
    "summary": {
        "total_users": {{ users.size }},
        "exceeding": {{ exceeding_users.size }},
        "blocked": {{ blocked_count }},
        "unblocked": {{ unblocked_count }}
    },
    "exceeding_users": {{ toJson(exceeding_users) }},
    "results": {{ toJson(results) }}
}
