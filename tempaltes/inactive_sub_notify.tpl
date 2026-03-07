{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║              INACTIVE SUBSCRIPTION NOTIFICATION TEMPLATE v1.0                ║
║     Уведомление пользователей, не подключившихся по Remnawave подписке       ║
║              (Отправка по telegramId из Remnawave напрямую)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Шаблон проверяет всех ACTIVE пользователей в Remnawave и:
  - Находит тех, кто так и не подключился (firstConnectedAt = null)
  - Отправляет напоминание в Telegram с инструкцией по настройке (3 этапа)
    Этап 1: Мягкое приветственное напоминание
    Этап 2: Повторное с акцентом ("всё ещё не настроен")
    Этап 3: Финальное предупреждение + предложение поддержки
  - Повторно напоминает через заданный интервал (не чаще 1 раза в 24ч)
  - Прекращает уведомления после 3 попыток
  - Отправляет сводку администратору

НАСТРОЙКИ:
  config.telegram.telegram_bot.token - токен Telegram бота
  REMNA_HOST / REMNA_TOKEN - доступ к Remnawave API

ЗАПУСК:
  Рекомендуется запускать через spool каждые 6-12 часов.

МЕТКИ В STORAGE (inact_{short_uuid}):
  notified: true/false - было ли уведомление
  notify_count: N - количество отправленных напоминаний
  first_notify_at: timestamp - когда первый раз уведомили
  last_notify_at: timestamp - когда последний раз уведомили
  connected: true - пользователь подключился (уведомления прекращены)
#}}

{{# === НАСТРОЙКИ === #}}
{{ NOTIFY_INTERVAL = 86400 }}            {{# 24 часа между напоминаниями #}}
{{ MIN_AGE_SECONDS = 3600 }}             {{# Не трогать аккаунты моложе 1 часа (дать время на настройку) #}}
{{ MAX_REMINDERS = 3 }}                  {{# Максимум напоминаний, потом прекращаем #}}
{{ STORAGE_PREFIX = "vpn_mrzb_" }}       {{# Префикс storage для связи Remnawave-SHM #}}

{{# Получаем токен бота из конфигурации SHM #}}
{{ TG_TOKEN = config.telegram.telegram_bot.token || config.telegram.token || "" }}

{{# === REMNAWAVE API === #}}
{{ REMNA_HOST = "https://p.z-hq.com" }}
{{ REMNA_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ" }}
{{ auth_header = "Bearer " _ REMNA_TOKEN }}

{{# === АДМИНСКИЙ ЧАТ === #}}
{{ ADMIN_CHAT_ID = -1001965226181 }}
{{ ADMIN_THREAD_ID = 28953 }}

{{# ================================================================ #}}
{{# ===================== ОСНОВНОЙ КОД ============================= #}}
{{# ================================================================ #}}

{{# Получаем всех пользователей из Remnawave #}}
{{ users_url = REMNA_HOST _ "/api/users?size=1000" }}
{{ users_response = http.get(users_url, 'headers', { 'Authorization' => auth_header }) }}
{{ users = users_response.response.users || [] }}

{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}
{{ notified_count = 0 }}
{{ inactive_count = 0 }}
{{ connected_count = 0 }}
{{ skipped_count = 0 }}
{{ results = [] }}
{{ first_notify_this_run = 0 }}

{{# === КУМУЛЯТИВНАЯ СТАТИСТИКА (сохраняется между запусками) === #}}
{{ cum_stats = storage.read('name', 'inact_global_stats') || {} }}
{{ cum_connected = (cum_stats.total_connected || 0) + 0 }}
{{ cum_unique_notified = (cum_stats.unique_notified || 0) + 0 }}

{{ FOREACH u IN users }}
    {{# === Пропускаем неактивных === #}}
    {{ NEXT IF u.status != 'ACTIVE' }}

    {{ user_uuid = u.uuid }}
    {{ username = u.username }}
    {{ short_uuid = user_uuid.substr(0, 8) }}
    {{ user_traffic = u.userTraffic || {} }}
    {{ first_connected = user_traffic.firstConnectedAt || '' }}
    {{ online_at = user_traffic.onlineAt || '' }}
    {{ created_at = u.createdAt || '' }}
    {{ subscription_url = u.subscriptionUrl || '' }}
    {{ short_user_uuid = u.shortUuid || '' }}
    {{ telegram_id_remna = u.telegramId || '' }}

    {{# === Пропускаем пользователей, которые УЖЕ подключались === #}}
    {{ IF first_connected }}
        {{# Проверяем, был ли ранее отмечен как неподключенный — если да, фиксируем "подключился" #}}
        {{ inact_key = "inact_" _ short_uuid }}
        {{ flag_data = storage.read('name', inact_key) }}
        {{ IF flag_data.notified && !flag_data.connected }}
            {{ connected_count = connected_count + 1 }}
            {{ save_connected = storage.save(inact_key, {
                'notified' => 1,
                'connected' => 1,
                'connected_at' => current_time,
                'notify_count' => flag_data.notify_count || 0,
                'username' => username,
                'remna_uuid' => user_uuid
            }) }}
            {{ results.push({
                'user' => username,
                'remna_uuid' => user_uuid,
                'status' => 'connected_after_notify',
                'notify_count' => flag_data.notify_count || 0,
                'shm_user_id' => ''
            }) }}
        {{ END }}
        {{ NEXT }}
    {{ END }}

    {{# === Проверяем, видели ли мы этого пользователя раньше (first_seen) === #}}
    {{ inact_key = "inact_" _ short_uuid }}
    {{ flag_data = storage.read('name', inact_key) || {} }}
    {{ first_seen = (flag_data.first_seen_at || 0) + 0 }}

    {{ IF !flag_data.notified && !first_seen }}
        {{# Первый раз видим — сохраняем метку и пропускаем как "свежего" #}}
        {{ save_first_seen = storage.save(inact_key, {
            'notified' => 0,
            'connected' => 0,
            'notify_count' => 0,
            'first_seen_at' => current_time,
            'username' => username,
            'remna_uuid' => user_uuid
        }) }}
        {{ skipped_count = skipped_count + 1 }}
        {{ NEXT }}
    {{ ELSIF !flag_data.notified && first_seen }}
        {{# Видели раньше, но ещё не уведомляли — проверяем возраст #}}
        {{ seen_age = current_time - first_seen }}
        {{ IF seen_age < MIN_AGE_SECONDS }}
            {{ skipped_count = skipped_count + 1 }}
            {{ NEXT }}
        {{ END }}
    {{ END }}

    {{ shm_user_id = '' }}
    {{ shm_full_name = '' }}
    {{ shm_tg_login = '' }}
    {{ user_service_id = '' }}
    {{ telegram_id = '' }}

    {{# Парсим user_service_id из username (HQVPN_XXX или us_XXX) #}}
    {{ uname_match = username.match('^.+_([0-9]+)$') }}
    {{ IF uname_match.0 }}
        {{ user_service_id = uname_match.0 }}
        {{ tmp_us_obj = us.id(user_service_id) }}
        {{ IF tmp_us_obj }}
            {{ shm_user_id = tmp_us_obj.user_id }}
        {{ END }}
    {{ END }}

    {{# === Парсим user_id из description === #}}
    {{ desc = u.description || '' }}
    {{ uid_match = desc.match('US_ID: *([0-9]+)') }}
    {{ IF uid_match.0 && !shm_user_id }}
        {{ shm_user_id = uid_match.0 }}
    {{ END }}

    {{# === ПОИСК TELEGRAM ID === #}}

    {{# ПРИОРИТЕТ 0: telegramId напрямую из Remnawave #}}
    {{ IF telegram_id_remna }}
        {{ telegram_id = telegram_id_remna }}
    {{ END }}

    {{# ПРИОРИТЕТ 1: ищем в storage по user_service_id #}}
    {{ IF !telegram_id && user_service_id }}
        {{ storage_key = STORAGE_PREFIX _ user_service_id }}
        {{ st_data = storage.read('name', storage_key) }}
        {{ IF st_data }}
            {{ telegram_id = st_data.response.telegramId || '' }}
            {{ IF telegram_id && shm_user_id }}
                {{ shm_user = user.id(shm_user_id) }}
                {{ IF shm_user }}
                    {{ shm_full_name = shm_user.full_name }}
                    {{ shm_tg_login = shm_user.settings.telegram.username || shm_user.settings.telegram.login }}
                {{ END }}
            {{ END }}
        {{ END }}
    {{ END }}

    {{# ПРИОРИТЕТ 2: из description (@TELEGRAM_ID) #}}
    {{ IF !telegram_id }}
        {{ tg_match = desc.match('@([0-9]+)') }}
        {{ IF tg_match.0 }}
            {{ telegram_id = tg_match.0 }}
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

    {{# ПРИОРИТЕТ 3: SHM user данные #}}
    {{ IF !telegram_id && shm_user_id }}
        {{ shm_user = user.id(shm_user_id) }}
        {{ IF shm_user }}
            {{ telegram_id = shm_user.settings.telegram.chat_id || '' }}
            {{ shm_full_name = shm_user.full_name }}
            {{ shm_tg_login = shm_user.settings.telegram.username || shm_user.settings.telegram.login }}
        {{ END }}
    {{ END }}

    {{# =================================================================== #}}
    {{# === ПОЛЬЗОВАТЕЛЬ НЕ ПОДКЛЮЧАЛСЯ — обрабатываем === #}}
    {{# =================================================================== #}}

    {{ inactive_count = inactive_count + 1 }}

    {{# flag_data уже прочитаны при проверке first_seen #}}
    {{ notify_count = (flag_data.notify_count || 0) + 0 }}
    {{ last_notify_time = (flag_data.last_notify_at || 0) + 0 }}

    {{# Проверяем лимит напоминаний #}}
    {{ IF notify_count >= MAX_REMINDERS }}
        {{ results.push({
            'user' => username,
            'remna_uuid' => user_uuid,
            'status' => 'max_reminders',
            'notify_count' => notify_count,
            'tg_id' => telegram_id,
            'shm_user_id' => shm_user_id
        }) }}
        {{ NEXT }}
    {{ END }}

    {{# Проверяем интервал #}}
    {{ time_diff = current_time - last_notify_time }}
    {{ IF last_notify_time > 0 && time_diff < NOTIFY_INTERVAL }}
        {{ results.push({
            'user' => username,
            'remna_uuid' => user_uuid,
            'status' => 'cooldown',
            'notify_count' => notify_count,
            'next_in' => NOTIFY_INTERVAL - time_diff,
            'tg_id' => telegram_id,
            'shm_user_id' => shm_user_id
        }) }}
        {{ NEXT }}
    {{ END }}

    {{# === Нет Telegram ID — пропускаем с пометкой === #}}
    {{ IF !telegram_id }}
        {{ results.push({
            'user' => username,
            'remna_uuid' => user_uuid,
            'status' => 'no_telegram',
            'shm_user_id' => shm_user_id
        }) }}
        {{ NEXT }}
    {{ END }}

    {{# === Формируем сообщение пользователю (3 этапа) === #}}
    {{ new_notify_count = notify_count + 1 }}

    {{# Получаем название услуги из SHM #}}
    {{ service_name = '' }}
    {{ IF user_service_id }}
        {{ tmp_us = us.id(user_service_id) }}
        {{ IF tmp_us }}
            {{ service_name = tmp_us.name || '' }}
        {{ END }}
    {{ END }}

    {{ service_line = '' }}
    {{ IF service_name }}
        {{ service_line = "👤 Услуга: <b>" _ service_name _ "</b>\n\n" }}
    {{ END }}

    {{# ─── ЭТАП 1: Мягкое приветственное напоминание ─── #}}
    {{ IF new_notify_count == 1 }}
        {{ message = "🎉 <b>Вижу что вы не подключались к VPN</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "⚠️ <b>Осталось настроить VPN</b>\n\n" }}
        {{ message = message _ "Нажмите кнопку ниже, чтобы:\n" }}
        {{ message = message _ "• Скачать приложение\n" }}
        {{ message = message _ "• Подключить VPN\n" }}
        {{ message = message _ "• Начать пользоваться" }}

    {{# ─── ЭТАП 2: Повторное напоминание с акцентом ─── #}}
    {{ ELSIF new_notify_count == 2 }}
        {{ message = "👋 <b>Напоминаю — ваш VPN всё ещё не настроен</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "Подписка активна, но вы ещё ни разу не подключались.\n\n" }}
        {{ message = message _ "Настройка займёт <b>пару минут</b> — нажмите кнопку ниже 👇" }}

    {{# ─── ЭТАП 3: Финальное предупреждение + промокод ─── #}}
    {{ ELSE }}
        {{ message = "⚠️ <b>Последнее напоминание о VPN</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "Ваша подписка активна, но VPN так и не был настроен.\n\n" }}
        {{ message = message _ "🎁 Активируйте промокод <code>100_HQVPN</code> и получите <b>100 ₽</b> на баланс!\n\n" }}
        {{ message = message _ "Если возникли сложности — напишите в поддержку, мы поможем!\n\n" }}
        {{ message = message _ "👇 Нажмите кнопку и настройте за 2 минуты:" }}
    {{ END }}

    {{# Кнопки (общие для всех этапов) #}}
    {{ keyboard = {
        'inline_keyboard' => [
            [
                {
                    'text' => '📲 Настроить VPN',
                    'url' => 'https://t.me/hq_vpn_bot/web'
                }
            ],
            [
                {
                    'text' => '🔄 Обновить меню',
                    'callback_data' => '/start'
                }
            ]
        ]
    } }}

    {{# === Отправляем === #}}
    {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
    {{ send_result = http.post(tg_url, 'content', {
        'chat_id' => telegram_id,
        'text' => message,
        'parse_mode' => 'HTML',
        'reply_markup' => keyboard
    }) }}
    {{ send_ok = send_result.ok || 0 }}

    {{ IF send_ok }}
        {{ notified_count = notified_count + 1 }}

        {{# Считаем впервые уведомлённых для кумулятивной статистики #}}
        {{ IF new_notify_count == 1 }}
            {{ first_notify_this_run = first_notify_this_run + 1 }}
        {{ END }}

        {{# Сохраняем состояние #}}
        {{ save_flag = storage.save(inact_key, {
            'notified' => 1,
            'connected' => 0,
            'notify_count' => new_notify_count,
            'first_seen_at' => flag_data.first_seen_at || current_time,
            'first_notify_at' => flag_data.first_notify_at || current_time,
            'last_notify_at' => current_time,
            'username' => username,
            'remna_uuid' => user_uuid
        }) }}

        {{ results.push({
            'user' => username,
            'remna_uuid' => user_uuid,
            'status' => 'notified',
            'notify_num' => new_notify_count,
            'tg_id' => telegram_id,
            'full_name' => shm_full_name,
            'tg_login' => shm_tg_login,
            'shm_user_id' => shm_user_id
        }) }}
    {{ ELSE }}
        {{ results.push({
            'user' => username,
            'remna_uuid' => user_uuid,
            'status' => 'send_failed',
            'error' => send_result.description || 'unknown',
            'tg_id' => telegram_id,
            'shm_user_id' => shm_user_id
        }) }}
    {{ END }}

{{ END }}


{{# ================================================================ #}}
{{# ===================== СВОДКА ДЛЯ АДМИНА ======================== #}}
{{# ================================================================ #}}

{{# Всегда отправляем сводку админу #}}

    {{# === Обновляем кумулятивную статистику === #}}
    {{ new_cum_connected = cum_connected + connected_count }}
    {{ new_cum_unique_notified = cum_unique_notified + first_notify_this_run }}
    {{ save_cum = storage.save('inact_global_stats', {
        'total_connected' => new_cum_connected,
        'unique_notified' => new_cum_unique_notified,
        'last_run' => current_time,
        'last_inactive' => inactive_count
    }) }}

    {{# Считаем статистику по статусам #}}
    {{ cooldown_count = 0 }}
    {{ no_tg_count = 0 }}
    {{ max_rem_count = 0 }}
    {{ failed_count = 0 }}
    {{ FOREACH r IN results }}
        {{ IF r.status == 'cooldown' }}
            {{ cooldown_count = cooldown_count + 1 }}
        {{ ELSIF r.status == 'no_telegram' }}
            {{ no_tg_count = no_tg_count + 1 }}
        {{ ELSIF r.status == 'max_reminders' }}
            {{ max_rem_count = max_rem_count + 1 }}
        {{ ELSIF r.status == 'send_failed' }}
            {{ failed_count = failed_count + 1 }}
        {{ END }}
    {{ END }}

    {{# Формируем сводку (HTML — надёжнее Markdown с именами) #}}
    {{ admin_msg = "📡 <b>Неактивные подписки — Сводка</b>\n\n" }}
    {{ admin_msg = admin_msg _ "👥 Всего в Remna: " _ users.size _ "\n" }}
    {{ admin_msg = admin_msg _ "😴 Не подключались: <b>" _ inactive_count _ "</b>\n" }}
    {{ admin_msg = admin_msg _ "🎯 Подключились: <b>" _ connected_count _ "</b> (всего: <b>" _ new_cum_connected _ "</b>)\n" }}
    {{ IF new_cum_unique_notified > 0 }}
        {{ effectiveness = (new_cum_connected * 100) / new_cum_unique_notified }}
        {{ admin_msg = admin_msg _ "📊 Эффективность: <b>" _ effectiveness _ "%</b> (" _ new_cum_connected _ "/" _ new_cum_unique_notified _ ")\n" }}
    {{ END }}
    {{ admin_msg = admin_msg _ "⏭ Пропущено (свежие): " _ skipped_count _ "\n\n" }}

    {{ admin_msg = admin_msg _ "📨 <b>Уведомления:</b>\n" }}
    {{ admin_msg = admin_msg _ "✉️ Отправлено сейчас: " _ notified_count _ "\n" }}
    {{ admin_msg = admin_msg _ "⏳ Cooldown (ждут 24ч): " _ cooldown_count _ "\n" }}
    {{ admin_msg = admin_msg _ "🔇 Лимит (3/3): " _ max_rem_count _ "\n" }}
    {{ admin_msg = admin_msg _ "🚫 Нет TG ID: " _ no_tg_count _ "\n" }}
    {{ IF failed_count > 0 }}
        {{ admin_msg = admin_msg _ "❌ Ошибки: " _ failed_count _ "\n" }}
    {{ END }}

    {{# Отправляем админу #}}
    {{ admin_tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
    {{ admin_send = http.post(admin_tg_url, 'content', {
        'chat_id' => ADMIN_CHAT_ID,
        'message_thread_id' => ADMIN_THREAD_ID,
        'text' => admin_msg,
        'parse_mode' => 'HTML'
    }) }}


{{# ================================================================ #}}
{{# ===================== РЕЗУЛЬТАТ JSON =========================== #}}
{{# ================================================================ #}}

{
    "status": 1,
    "summary": {
        "total_users": {{ users.size }},
        "inactive_count": {{ inactive_count }},
        "connected_after_notify": {{ connected_count }},
        "connected_cumulative": {{ new_cum_connected }},
        "unique_notified_cumulative": {{ new_cum_unique_notified }},
        "notified_count": {{ notified_count }},
        "skipped_fresh": {{ skipped_count }},
        "no_telegram": {{ no_tg_count }},
        "max_reminders": {{ max_rem_count }},
        "cooldown": {{ cooldown_count }},
        "failed": {{ failed_count }}
    },
    "results": {{ toJson(results) }}
}
