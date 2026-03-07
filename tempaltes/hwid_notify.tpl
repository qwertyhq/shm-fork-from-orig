{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    HWID LIMIT NOTIFICATION TEMPLATE v1.3                      ║
║         Уведомление пользователей о превышении лимита устройств              ║
║              (Отправка по telegramId из Remnawave напрямую)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Шаблон проверяет всех пользователей в Remnawave и:
  - Ставит метку hwid_exceeded в storage при превышении
  - Убирает метку когда пользователь исправил ситуацию
  - Отправляет уведомления в Telegram каждый час

НАСТРОЙКИ:
  config.telegram.token - токен Telegram бота из конфигурации SHM
  config.telegram.telegram_bot.token - альтернативный путь к токену

ЗАПУСК:
  Рекомендуется запускать через spool каждый час.
  
МЕТКИ В STORAGE (hwid_flag_{remna_uuid}):
  hwid_exceeded: true/false - превышен ли лимит
  hwid_exceeded_at: timestamp - когда было превышение
  hwid_device_count: N - текущее количество устройств
  hwid_device_limit: N - лимит устройств
#}}

{{# === НАСТРОЙКИ === #}}
{{ NOTIFY_INTERVAL = 3600 }}  {{# Тест: отправлять всегда. Для прода: 3600 #}}
{{ STORAGE_PREFIX = "vpn_mrzb_" }}  {{# Префикс storage для связи Remnawave-SHM #}}
{{ TEST_ADMIN_PREVIEW = 1 }}  {{# 1 = отправить админу пример сообщения для пользователя #}}

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

{{# Получаем токен бота из конфигурации SHM #}}
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

{{# Считаем устройства по пользователям и группируем #}}
{{ device_counts = {} }}
{{ user_devices = {} }}
{{ FOREACH device IN devices }}
    {{ dev_user_uuid = device.userUuid }}
    {{ IF !device_counts.$dev_user_uuid }}
        {{ device_counts.$dev_user_uuid = 0 }}
        {{ user_devices.$dev_user_uuid = [] }}
    {{ END }}
    {{ device_counts.$dev_user_uuid = device_counts.$dev_user_uuid + 1 }}
    {{ user_devices.$dev_user_uuid.push(device) }}
{{ END }}

{{# === ПРОВЕРЯЕМ КАЖДОГО ПОЛЬЗОВАТЕЛЯ === #}}  

{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}
{{ notified_count = 0 }}
{{ exceeded_count = 0 }}
{{ fixed_count = 0 }}
{{ results = [] }}
{{ skipped_family_next = [] }}  {{# Для отладки: кто пропущен из-за next семейного #}}

{{ FOREACH u IN users }}
    {{# Пропускаем неактивных #}}
    {{ NEXT IF u.status != 'ACTIVE' }}
    
    {{ user_uuid = u.uuid }}
    {{ username = u.username }}
    
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
            {{# Проверяем NEXT услугу на семейный тариф #}}
            {{ next_us = check_us_obj.next }}
            {{ IF next_us }}
                {{ next_sid = next_us.service_id + 0 }}
                {{ FOREACH fam_sid IN FAMILY_SERVICES }}
                    {{ IF next_sid == fam_sid }}
                        {{ is_family = 1 }}
                        {{# Сохраняем для отладки #}}
                        {{ skipped_family_next.push({
                            'username' => username,
                            'us_id' => check_us_id,
                            'current_service_id' => check_sid,
                            'next_service_id' => next_sid
                        }) }}
                    {{ END }}
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
    {{ shm_user = '' }}
    {{ shm_full_name = '' }}
    {{ shm_tg_login = '' }}
    {{ shm_user_id = '' }}
    {{ telegram_id = '' }}
    {{ user_service_id = '' }}
    
    {{# Сначала парсим user_service_id из username (HQVPN_XXX или us_XXX) #}}
    {{ uname_match = username.match('^.+_([0-9]+)$') }}
    {{ IF uname_match.0 }}
        {{ user_service_id = uname_match.0 }}
        {{# Получаем shm_user_id через us.id() #}}
        {{ tmp_us_obj = us.id(user_service_id) }}
        {{ IF tmp_us_obj }}
            {{ shm_user_id = tmp_us_obj.user_id }}
        {{ END }}
    {{ END }}
    
    {{# Также парсим US_ID из description (это user_id SHM, не user_service_id!) #}}
    {{ desc = u.description || '' }}
    {{ uid_match = desc.match('US_ID: *([0-9]+)') }}
    {{ IF uid_match.0 && !shm_user_id }}
        {{ shm_user_id = uid_match.0 }}
    {{ END }}
    
    {{# ПРИОРИТЕТ 1: ищем в storage по user_service_id из username #}}
    {{ IF user_service_id }}
        {{ storage_key = STORAGE_PREFIX _ user_service_id }}
        {{ st_data = storage.read('name', storage_key) }}
        {{ IF st_data }}
            {{# telegramId внутри response #}}
            {{ telegram_id = st_data.response.telegramId || '' }}
            {{ IF telegram_id && shm_user_id }}
                {{# Получаем SHM данные для отчёта #}}
                {{ shm_user = user.id(shm_user_id) }}
                {{ IF shm_user }}
                    {{ shm_full_name = shm_user.full_name }}
                    {{ shm_tg_login = shm_user.settings.telegram.username || shm_user.settings.telegram.login }}
                {{ END }}
            {{ END }}
        {{ END }}
    {{ END }}
    
    {{# ПРИОРИТЕТ 2: парсим @TELEGRAM_ID напрямую из description #}}
    {{ IF !telegram_id }}
        {{ tg_match = desc.match('@([0-9]+)') }}
        {{ IF tg_match.0 }}
            {{ telegram_id = tg_match.0 }}
            {{# Парсим имя и username из description для отчёта #}}
            {{ name_match = desc.match('@[0-9]+, *([^,]+)') }}
            {{ IF name_match.0 }}
                {{ shm_full_name = name_match.0 }}
            {{ END }}
            {{ login_match = desc.match('t\\.me/([a-zA-Z0-9_]+)') }}
            {{ IF login_match.0 }}
                {{ shm_tg_login = login_match.0 }}
            {{ END }}
        {{ END }}
    {{ END }}
    
    {{# ПРИОРИТЕТ 3: ищем через storage по username (для пользователей без стандартного формата имени) #}}
    {{ IF !telegram_id }}
        {{# Ищем storage запись по username Remnawave #}}
        {{ FOREACH st_item IN storage.list }}
            {{ IF st_item.name.match('^' _ STORAGE_PREFIX) }}
                {{ st_data = storage.read('name', st_item.name) }}
                {{ IF st_data.response.username == username }}
                    {{# Нашли! Берём telegramId #}}
                    {{ telegram_id = st_data.response.telegramId }}
                    {{# Извлекаем user_service_id из имени storage ключа #}}
                    {{ st_us_id = st_item.name.replace(STORAGE_PREFIX, '') }}
                    {{ IF st_us_id && !shm_user_id }}
                        {{ st_us_obj = us.id(st_us_id) }}
                        {{ IF st_us_obj }}
                            {{ shm_user_id = st_us_obj.user_id }}
                        {{ END }}
                    {{ END }}
                    {{# Получаем SHM пользователя для имени/логина #}}
                    {{ IF shm_user_id }}
                        {{ shm_user = user.id(shm_user_id) }}
                        {{ IF shm_user }}
                            {{ shm_full_name = shm_user.full_name }}
                            {{ shm_tg_login = shm_user.settings.telegram.username || shm_user.settings.telegram.login }}
                        {{ END }}
                    {{ END }}
                    {{ LAST }}
                {{ END }}
            {{ END }}
        {{ END }}
    {{ END }}
    
    {{# Проверяем превышение #}}
    {{# Короткий UUID для ключей storage (первые 8 символов) #}}
    {{ short_uuid = user_uuid.substr(0, 8) }}
    
    {{ IF device_count > hwid_limit }}
        {{ exceeded_count = exceeded_count + 1 }}
        
        {{# Читаем текущий флаг из storage #}}
        {{ hwid_flag_key = "hf_" _ short_uuid }}
        {{ flag_data = storage.read('name', hwid_flag_key) }}
        {{ warn_count = (flag_data.hwid_warn_count || 0) + 0 }}  {{# +0 для преобразования строки в число #}}
        {{ is_blocked = (flag_data.hwid_blocked || 0) + 0 }}
        
        {{# Есть ли Telegram ID для уведомления? #}}
        {{ IF telegram_id }}
            
            {{# Проверяем время последнего уведомления #}}
            {{ notify_key = "hn_" _ short_uuid }}
            {{ last_notify_data = storage.read('name', notify_key) }}
            {{ last_notify_time = last_notify_data.last_notify || 0 }}
            {{ time_diff = current_time - last_notify_time }}
            
            {{ IF time_diff >= NOTIFY_INTERVAL }}
                {{# Получаем список устройств пользователя #}}
                {{ my_devices = user_devices.$user_uuid || [] }}
                {{ excess = device_count - hwid_limit }}
                {{ new_warn_count = warn_count + 1 }}
                
                {{# Формируем красивое сообщение (HTML формат) #}}
                {{ IF shm_full_name }}
                    {{ message = "👋 <b>" _ shm_full_name _ "</b>, внимание!\n\n" }}
                {{ ELSE }}
                    {{ message = "" }}
                {{ END }}
                {{ message = message _ "🚨 <b>Превышен лимит устройств!</b>\n" }}
                {{ message = message _ "━━━━━━━━━━━━━━━━━━━━━\n\n" }}
                
                {{ message = message _ "📊 <b>Статистика:</b>\n" }}
                {{ message = message _ "├ 📱 Подключено: <b>" _ device_count _ "</b> из <b>" _ hwid_limit _ "</b>\n" }}
                {{ message = message _ "├ 🚫 Лишних: <b>" _ excess _ "</b>\n" }}
                {{ message = message _ "└ ⚠️ Предупреждение: <b>" _ new_warn_count _ "</b>/5\n\n" }}
                
                {{ IF new_warn_count >= 4 }}
                    {{ message = message _ "🔴 <b>ПОСЛЕДНЕЕ ПРЕДУПРЕЖДЕНИЕ!</b>\n" }}
                    {{ message = message _ "<i>Следующий шаг — блокировка аккаунта</i>\n\n" }}
                {{ END }}
                
                {{ message = message _ "📋 <b>Ваши устройства:</b>\n" }}
                
                {{# Список устройств #}}
                {{ dev_num = 0 }}
                {{ FOREACH dev IN my_devices }}
                    {{ dev_num = dev_num + 1 }}
                    {{ dev_name = dev.deviceModel || dev.platform || 'Неизвестно' }}
                    {{ dev_os = dev.osVersion || '' }}
                    {{ IF dev_os }}
                        {{ dev_info = dev_name _ " · " _ dev_os }}
                    {{ ELSE }}
                        {{ dev_info = dev_name }}
                    {{ END }}
                    {{ IF dev_num == my_devices.size }}
                        {{ message = message _ "└ " _ dev_num _ ". " _ dev_info _ "\n" }}
                    {{ ELSE }}
                        {{ message = message _ "├ " _ dev_num _ ". " _ dev_info _ "\n" }}
                    {{ END }}
                {{ END }}
                
                {{ message = message _ "\n━━━━━━━━━━━━━━━━━━━━━\n" }}
                {{ message = message _ "⏰ <b>Что делать?</b>\n" }}
                {{ message = message _ "├ Удалите лишние устройства в приложении\n" }}
                {{ message = message _ "└ Или перейдите на семейный тариф\n\n" }}
                
                {{ message = message _ "⚠️ <b>Важно:</b> если проигнорировать это сообщение,\n" }}
                {{ message = message _ "доступ к VPN будет <b>заблокирован</b>!\n\n" }}
                
                {{ message = message _ "👨‍👩‍👧‍👦 <b>Семейный тариф — лучшее решение!</b>\n" }}
                {{ message = message _ "├ 📱 <b>10 устройств</b> для всей семьи\n" }}
                {{ message = message _ "├ ♾️ <b>Безлимитный трафик</b>\n" }}
                {{ message = message _ "└ 🚫 <b>Без блокировок</b> за устройства\n\n" }}
                {{ message = message _ "💡 <i>После смены тарифа на семейный эти уведомления прекратятся автоматически!</i>" }}
                
                {{# Inline-кнопка для открытия веб-приложения #}}
                {{ keyboard = {
                    'inline_keyboard' => [
                        [
                            {
                                'text' => '👨‍👩‍👧‍👦 Перейти на семейный тариф',
                                'url' => 'https://t.me/hq_vpn_bot/web'
                            }
                        ]
                    ]
                } }}
                
                {{# Формируем список устройств для отчёта #}}
                {{ devices_list = [] }}
                {{ FOREACH dev IN my_devices }}
                    {{ devices_list.push({
                        'platform' => dev.platform,
                        'model' => dev.deviceModel,
                        'os' => dev.osVersion
                    }) }}
                {{ END }}
                
                {{# Отправляем через Telegram API с parse_mode HTML и кнопкой #}}
                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                {{ send_result = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => message, 'parse_mode' => 'HTML', 'reply_markup' => keyboard }) }}
                {{ send_ok = send_result.ok || 0 }}
                
                {{ IF send_ok }}
                    {{ notified_count = notified_count + 1 }}
                    
                    {{# Увеличиваем счётчик предупреждений #}}
                    {{ new_warn_count = warn_count + 1 }}
                    
                    {{# Сохраняем флаг и счётчик #}}
                    {{ save_flag = storage.save(hwid_flag_key, {
                        'hwid_exceeded' => 1,
                        'hwid_exceeded_at' => current_time,
                        'hwid_warn_count' => new_warn_count,
                        'hwid_blocked' => is_blocked,
                        'hwid_device_count' => device_count,
                        'hwid_device_limit' => hwid_limit,
                        'username' => username,
                        'remna_uuid' => user_uuid
                    }) }}
                    
                    {{# Сохраняем время уведомления #}}
                    {{ save_notify = storage.save(notify_key, {
                        'last_notify' => current_time,
                        'device_count' => device_count,
                        'limit' => hwid_limit
                    }) }}
                    {{ results.push({ 
                user => username,
                remna_uuid => user_uuid,
                devices => device_count, 
                limit => hwid_limit,
                status => 'notified',
                warn_num => new_warn_count,
                tg_id => telegram_id,
                full_name => shm_full_name,
                tg_login => shm_tg_login,
                shm_user_id => shm_user_id,
                devices_list => devices_list
                    }) }}
                {{ ELSE }}
                    {{ results.push({ 
                        user => username,
                        remna_uuid => user_uuid,
                        devices => device_count, 
                        limit => hwid_limit,
                        status => 'send_failed',
                        error => send_result.description || 'unknown',
                        tg_id => telegram_id,
                        shm_user_id => shm_user_id,
                        devices_list => devices_list
                    }) }}
                {{ END }}
                
            {{ ELSE }}
                {{ results.push({ 
                    user => username,
                    remna_uuid => user_uuid,
                    devices => device_count, 
                    limit => hwid_limit,
                    status => 'skipped_recent',
                    warn_count => warn_count,
                    full_name => shm_full_name,
                    tg_login => shm_tg_login,
                    shm_user_id => shm_user_id,
                    next_notify_in => NOTIFY_INTERVAL - time_diff
                }) }}
            {{ END }}
            
        {{ ELSE }}
            {{ results.push({ 
                user => username,
                remna_uuid => user_uuid,
                devices => device_count, 
                limit => hwid_limit,
                status => 'exceeded_no_tg',
                warn_count => warn_count,
                shm_user_id => shm_user_id
            }) }}
        {{ END }}
        
    {{ ELSE }}
        {{# Лимит НЕ превышен — проверяем, была ли метка раньше #}}
        {{ hwid_flag_key = "hf_" _ short_uuid }}
        {{ flag_data = storage.read('name', hwid_flag_key) }}
        
        {{ IF flag_data.hwid_exceeded }}
            {{# Пользователь исправил ситуацию — убираем метку #}}
            {{ fixed_count = fixed_count + 1 }}
            
            {{# Обновляем флаг #}}
            {{ save_flag = storage.save(hwid_flag_key, {
                'hwid_exceeded' => 0,
                'hwid_fixed_at' => current_time,
                'hwid_device_count' => device_count,
                'hwid_device_limit' => hwid_limit,
                'username' => username,
                'remna_uuid' => user_uuid
            }) }}
            
            {{# Отправляем уведомление что всё ок #}}
            {{ IF telegram_id }}
                {{ message = "Лимит устройств восстановлен! Теперь у вас " _ device_count _ " устройств из " _ hwid_limit _ " разрешенных. Спасибо за понимание!" }}
                
                {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
                {{ send_result = http.post(tg_url, 'content', { 'chat_id' => telegram_id, 'text' => message }) }}
            {{ END }}
            
            {{ results.push({ 
                user => username,
                remna_uuid => user_uuid,
                devices => device_count, 
                limit => hwid_limit,
                status => 'fixed'
            }) }}
        {{ END }}
    {{ END }}
{{ END }}

{{# === СВОДКА ДЛЯ АДМИНА === #}}
{{ ADMIN_CHAT_ID = -1001965226181 }}
{{ ADMIN_THREAD_ID = 28953 }}

{{# Тестовый превью сообщения для админа #}}
{{ IF TEST_ADMIN_PREVIEW }}
    {{ test_message = "👋 <b>Тестовый Пользователь</b>, внимание!\n\n" }}
    {{ test_message = test_message _ "🚨 <b>Превышен лимит устройств!</b>\n" }}
    {{ test_message = test_message _ "━━━━━━━━━━━━━━━━━━━━━\n\n" }}
    {{ test_message = test_message _ "📊 <b>Статистика:</b>\n" }}
    {{ test_message = test_message _ "├ 📱 Подключено: <b>7</b> из <b>5</b>\n" }}
    {{ test_message = test_message _ "├ 🚫 Лишних: <b>2</b>\n" }}
    {{ test_message = test_message _ "└ ⚠️ Предупреждение: <b>3</b>/5\n\n" }}
    {{ test_message = test_message _ "📋 <b>Ваши устройства:</b>\n" }}
    {{ test_message = test_message _ "├ 1. iPhone 15 Pro · iOS 18.2\n" }}
    {{ test_message = test_message _ "├ 2. Samsung S24 · Android 14\n" }}
    {{ test_message = test_message _ "├ 3. MacBook Pro · macOS 15.1\n" }}
    {{ test_message = test_message _ "├ 4. Windows PC · Windows 11\n" }}
    {{ test_message = test_message _ "├ 5. iPad Pro · iPadOS 18.2\n" }}
    {{ test_message = test_message _ "├ 6. Xiaomi · Android 14\n" }}
    {{ test_message = test_message _ "└ 7. Linux Server · Ubuntu 24.04\n" }}
    {{ test_message = test_message _ "\n━━━━━━━━━━━━━━━━━━━━━\n" }}
    {{ test_message = test_message _ "⏰ <b>Что делать?</b>\n" }}
    {{ test_message = test_message _ "├ Удалите лишние устройства в приложении\n" }}
    {{ test_message = test_message _ "└ Или перейдите на семейный тариф\n\n" }}
    {{ test_message = test_message _ "⚠️ <b>Важно:</b> если проигнорировать это сообщение,\n" }}
    {{ test_message = test_message _ "доступ к VPN будет <b>заблокирован</b>!\n\n" }}
    {{ test_message = test_message _ "👨‍👩‍👧‍👦 <b>Семейный тариф — лучшее решение!</b>\n" }}
    {{ test_message = test_message _ "├ 📱 <b>10 устройств</b> для всей семьи\n" }}
    {{ test_message = test_message _ "├ ♾️ <b>Безлимитный трафик</b>\n" }}
    {{ test_message = test_message _ "└ 🚫 <b>Без блокировок</b> за устройства\n\n" }}
    {{ test_message = test_message _ "💡 <i>После смены тарифа на семейный эти уведомления прекратятся автоматически!</i>" }}
    
    {{ test_keyboard = {
        'inline_keyboard' => [
            [
                {
                    'text' => '👨‍👩‍👧‍👦 Перейти на семейный тариф',
                    'url' => 'https://t.me/hq_vpn_bot/web'
                }
            ]
        ]
    } }}
    
    {{ test_tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
    {{ test_send = http.post(test_tg_url, 'content', { 
        'chat_id' => ADMIN_CHAT_ID, 
        'message_thread_id' => ADMIN_THREAD_ID,
        'text' => "🧪 <b>ТЕСТОВЫЙ ПРЕВЬЮ</b>\n\nТак выглядит сообщение для пользователей:\n\n━━━━━━━━━━━━━━━━━━━━━\n\n" _ test_message, 
        'parse_mode' => 'HTML',
        'reply_markup' => test_keyboard
    }) }}
{{ END }}

{{ IF exceeded_count > 0 }}
    {{# Считаем статистику #}}
    {{ cooldown_count = 0 }}
    {{ FOREACH r IN results }}
        {{ IF r.status == 'skipped_recent' }}
            {{ cooldown_count = cooldown_count + 1 }}
        {{ END }}
    {{ END }}
    
    {{# Формируем сводку #}}
    {{ admin_msg = "📊 *HWID Сводка*\n\n" }}
    {{ admin_msg = admin_msg _ "👥 Всего пользователей: " _ users.size _ "\n" }}
    {{ admin_msg = admin_msg _ "📱 Всего устройств: " _ devices.size _ "\n" }}
    {{ admin_msg = admin_msg _ "⚠️ Превысили лимит: *" _ exceeded_count _ "*\n" }}
    {{ admin_msg = admin_msg _ "✅ Исправились: " _ fixed_count _ "\n\n" }}
    {{ admin_msg = admin_msg _ "📨 *Статус уведомлений:*\n" }}
    {{ admin_msg = admin_msg _ "✅ Доставлено: " _ notified_count _ "\n" }}
    {{ admin_msg = admin_msg _ "⏭ Cooldown: " _ cooldown_count _ "\n\n" }}
    
    {{ IF results.size > 0 }}
        {{ admin_msg = admin_msg _ "📋 *Список нарушителей:*\n" }}
        {{ FOREACH r IN results }}
            {{ IF r.status == 'notified' || r.status == 'send_failed' || r.status == 'exceeded_no_tg' || r.status == 'skipped_recent' }}
                {{# Экранируем _ во всех полях для Markdown #}}
                {{ r_name_raw = r.full_name || r.user }}
                {{ r_name = r_name_raw.replace('_', '\\_') }}
                {{ r_tg_raw = r.tg_login || '' }}
                {{ r_tg = r_tg_raw ? ' (@' _ r_tg_raw.replace('_', '\\_') _ ')' : '' }}
                {{ r_warn = r.warn_count || r.warn_num || 0 }}
                {{ r_shm_id = r.shm_user_id || '' }}
                {{ r_shm_part = r_shm_id ? ' [' _ r_shm_id _ ']' : '' }}
                {{ admin_msg = admin_msg _ "• " _ r_name _ r_tg _ r_shm_part _ " — *" _ r.devices _ "*/" _ r.limit _ " ⚠️" _ r_warn }}
                {{ IF r.status == 'notified' }}
                    {{ admin_msg = admin_msg _ " ✅" }}
                {{ ELSIF r.status == 'send_failed' }}
                    {{ admin_msg = admin_msg _ " ❌" }}
                {{ ELSIF r.status == 'exceeded_no_tg' }}
                    {{ admin_msg = admin_msg _ " 🚫" }}
                {{ ELSIF r.status == 'skipped_recent' }}
                    {{ admin_msg = admin_msg _ " ⏭" }}
                {{ END }}
                {{ admin_msg = admin_msg _ "\n" }}
            {{ END }}
        {{ END }}
        {{ admin_msg = admin_msg _ "\n✅=уведомлен ❌=ошибка 🚫=нет TG ⏭=недавно" }}
    {{ END }}
    
    {{# Отправляем админу #}}
    {{ admin_tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
    {{ admin_send = http.post(admin_tg_url, 'content', { 
        'chat_id' => ADMIN_CHAT_ID, 
        'message_thread_id' => ADMIN_THREAD_ID,
        'text' => admin_msg, 
        'parse_mode' => 'Markdown' 
    }) }}
    {{ admin_send_result = admin_send }}
{{ END }}

{{# === РЕЗУЛЬТАТ === #}}
{
    "status": 1,
    "summary": {
        "total_users": {{ users.size }},
        "total_devices": {{ devices.size }},
        "exceeded_count": {{ exceeded_count }},
        "fixed_count": {{ fixed_count }},
        "notified_count": {{ notified_count }},
        "skipped_family_next_count": {{ skipped_family_next.size }}
    },
    "skipped_family_next": {{ toJson(skipped_family_next) }},
    "results": {{ toJson(results) }}
}
