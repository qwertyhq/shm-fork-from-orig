{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║          REMNAWAVE WEBHOOK ROUTER — обработчик всех вебхуков                 ║
║                                                                              ║
║  URL: https://admin.ev-agency.io/shm/v1/public/remnawave-webhook            ║
║  Один эндпоинт принимает ВСЕ события и маршрутизирует по event type          ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОБРАБАТЫВАЕМЫЕ СОБЫТИЯ:
  user.not_connected         — юзер не подключился (3 стадии: 6ч, 24ч, 48ч)
  user.first_connected       — первое подключение (поздравление + отмена напоминаний)
  user.bandwidth_usage_threshold_reached — трафик 80%/95% (предупреждение юзеру)
  user.limited               — трафик 100%, VPN заблокирован (уведомление о сбросе)
  *                          — все остальные: лог в админку

НАСТРОЙКА В REMNAWAVE (.env):
  WEBHOOK_ENABLED=true
  WEBHOOK_URL=https://admin.ev-agency.io/shm/v1/public/remnawave-webhook
  WEBHOOK_SECRET_HEADER=<64 символа>
  NOT_CONNECTED_USERS_NOTIFICATIONS_ENABLED=true
  NOT_CONNECTED_USERS_NOTIFICATIONS_AFTER_HOURS=[6, 24, 48]
  BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=true
  BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[80, 95]

WEBHOOK PAYLOAD:
  { "scope": "user",
    "event": "user.not_connected",
    "timestamp": "2026-03-08T17:00:00Z",
    "data": { "uuid", "username", "telegramId", "status", "subscriptionUrl",
              "userTraffic": { "firstConnectedAt", "onlineAt", "usedTrafficBytes" },
              "trafficLimitBytes", ... },
    "meta": { "notConnectedAfterHours": 24 } }
#}}

{{# ═══════════════════════════════════════════════════════ #}}
{{#                      НАСТРОЙКИ                          #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ TG_TOKEN  = config.telegram.telegram_bot.token || config.telegram.token || '' }}
{{ ADMIN_CHAT_ID  = -1001965226181 }}
{{ ADMIN_THREAD_ID = 28953 }}
{{ STORAGE_PREFIX = "vpn_mrzb_" }}

{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}

{{# ═══════════════════════════════════════════════════════ #}}
{{#              ПАРСИНГ ВХОДЯЩЕГО ВЕБХУКА                  #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{# Верификация: Remnawave шлёт HMAC-SHA256 подпись в X-Remnawave-Signature.
    TT2 не имеет криптографических функций, поэтому полная проверка HMAC невозможна.
    Проверяем наличие заголовка — это отсекает случайные/бот запросы.
    Полная верификация HMAC возможна только на уровне nginx или middleware. #}}
{{ wh_signature = request.headers.x_remnawave_signature || '' }}
{{ IF !wh_signature }}
{{ toJson({ error => 'Unauthorized: missing signature' }) }}
{{ STOP }}
{{ END }}

{{ scope    = request.params.scope    || '' }}
{{ event    = request.params.event    || '' }}
{{ wh_data  = request.params.data     || {} }}
{{ wh_meta  = request.params.meta     || {} }}
{{ wh_ts    = request.params.timestamp || '' }}

{{# Базовая валидация #}}
{{ IF !event }}
{{ toJson({ error => 'Missing event field' }) }}
{{ STOP }}
{{ END }}

{{# ═══════════════════════════════════════════════════════ #}}
{{#              ОБЩИЕ ДАННЫЕ ИЗ ВЕБХУКА                    #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ user_uuid      = wh_data.uuid          || '' }}
{{ username       = wh_data.username       || '' }}
{{ remna_status   = wh_data.status         || '' }}
{{ telegram_id    = wh_data.telegramId     || '' }}
{{ subscription_url = wh_data.subscriptionUrl || '' }}
{{ user_traffic   = wh_data.userTraffic    || {} }}
{{ short_uuid     = user_uuid.substr(0, 8) }}

{{# Парсим USI из username (HQVPN_1056 → 1056) #}}
{{ user_service_id = '' }}
{{ shm_user_id     = '' }}
{{ service_name    = '' }}
{{ shm_tg_login    = '' }}
{{ uname_match = username.match('^.+_([0-9]+)$') }}
{{ IF uname_match.0 }}
    {{ user_service_id = uname_match.0 }}
    {{ tmp_us = us.id(user_service_id) }}
    {{ IF tmp_us }}
        {{ shm_user_id  = tmp_us.user_id }}
        {{ service_name = tmp_us.name || '' }}
    {{ END }}
{{ END }}

{{# Загружаем полный профиль из SHM #}}
{{ shm_user_balance  = '' }}
{{ shm_partner_id    = '' }}
{{ shm_partner_login = '' }}
{{ IF shm_user_id }}
    {{ shm_user = user.id(shm_user_id) }}
    {{ IF shm_user }}
        {{ IF !telegram_id }}
            {{ telegram_id = shm_user.settings.telegram.chat_id || '' }}
        {{ END }}
        {{ IF !shm_tg_login }}
            {{ shm_tg_login = shm_user.settings.telegram.username || shm_user.settings.telegram.login || '' }}
        {{ END }}
        {{ shm_user_balance = shm_user.balance }}
        {{ shm_partner_id   = shm_user.partner_id || '' }}
    {{ END }}
{{ END }}

{{# Загружаем логин реферала #}}
{{ IF shm_partner_id }}
    {{ partner_user = user.id(shm_partner_id) }}
    {{ IF partner_user }}
        {{ shm_partner_login = partner_user.settings.telegram.username || partner_user.settings.telegram.login || partner_user.login || '' }}
    {{ END }}
{{ END }}

{{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}


{{# ═══════════════════════════════════════════════════════════════════ #}}
{{#                                                                     #}}
{{#               МАРШРУТИЗАЦИЯ ПО ТИПУ СОБЫТИЯ                         #}}
{{#                                                                     #}}
{{# ═══════════════════════════════════════════════════════════════════ #}}


{{# ═══════════════════════════════════════════════════════ #}}
{{#          EVENT: user.not_connected                      #}}
{{#   Ремна шлёт 3 раза: через 6ч, 24ч, 48ч              #}}
{{#   meta.notConnectedAfterHours определяет стадию        #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ IF event == 'user.not_connected' }}

    {{ not_connected_hours = wh_meta.notConnectedAfterHours || 0 }}
    {{ inact_key = "inact_" _ short_uuid }}
    {{ flag_data = storage.read('name', inact_key) || {} }}

    {{# Уже подключился — пропускаем #}}
    {{ IF flag_data.connected }}
    {{ toJson({ skip => 'already_connected', username => username }) }}
    {{ STOP }}
    {{ END }}

    {{# Не ACTIVE — пропускаем #}}
    {{ IF remna_status != 'ACTIVE' }}
    {{ toJson({ skip => 'not_active', username => username, status => remna_status }) }}
    {{ STOP }}
    {{ END }}

    {{# Нет Telegram ID #}}
    {{ IF !telegram_id }}
    {{# Считаем пропуски без TG ID в статистике #}}
    {{ stats = storage.read('name', 'inact_webhook_stats') || {} }}
    {{ save_stats = storage.save('inact_webhook_stats', {
        'total_connected'  => (stats.total_connected  || 0),
        'unique_notified'  => (stats.unique_notified  || 0),
        'no_telegram'      => (stats.no_telegram      || 0) + 1,
        'send_failed'      => (stats.send_failed      || 0),
        'last_event'       => current_time
    }) }}
    {{ toJson({ skip => 'no_telegram_id', username => username }) }}
    {{ STOP }}
    {{ END }}

    {{# Стадия по часам: 6ч→1, 24ч→2, 48ч→3 #}}
    {{ IF not_connected_hours <= 6 }}
        {{ stage = 1 }}
    {{ ELSIF not_connected_hours <= 24 }}
        {{ stage = 2 }}
    {{ ELSE }}
        {{ stage = 3 }}
    {{ END }}

    {{ service_line = '' }}
    {{ IF service_name }}
        {{ service_line = "👤 Услуга: <b>" _ service_name _ "</b>\n\n" }}
    {{ END }}

    {{# ─── СТАДИЯ 1 (6ч): Мягкое приветственное ─── #}}
    {{ IF stage == 1 }}
        {{ message = "🎉 <b>Вижу что вы не подключались к VPN</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "⚠️ <b>Осталось настроить VPN</b>\n\n" }}
        {{ message = message _ "Нажмите кнопку ниже, чтобы:\n" }}
        {{ message = message _ "• Скачать приложение\n" }}
        {{ message = message _ "• Подключить VPN\n" }}
        {{ message = message _ "• Начать пользоваться" }}

    {{# ─── СТАДИЯ 2 (24ч): Повторное с акцентом ─── #}}
    {{ ELSIF stage == 2 }}
        {{ message = "👋 <b>Напоминаю — ваш VPN всё ещё не настроен</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "Подписка активна, но вы ещё ни разу не подключались.\n\n" }}
        {{ message = message _ "Настройка займёт <b>пару минут</b> — нажмите кнопку ниже 👇" }}

    {{# ─── СТАДИЯ 3 (48ч): Финальное + промокод ─── #}}
    {{ ELSE }}
        {{ message = "⚠️ <b>Последнее напоминание о VPN</b>\n\n" }}
        {{ message = message _ service_line }}
        {{ message = message _ "Ваша подписка активна, но VPN так и не был настроен.\n\n" }}
        {{ message = message _ "🎁 Активируйте промокод <code>100_HQVPN</code> и получите <b>100 ₽</b> на баланс!\n\n" }}
        {{ message = message _ "Если возникли сложности — напишите в поддержку, мы поможем!\n\n" }}
        {{ message = message _ "👇 Нажмите кнопку и настройте за 2 минуты:" }}
    {{ END }}

    {{# Отправка юзеру #}}
    {{ send_result = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
        'chat_id'      => telegram_id,
        'text'         => message,
        'parse_mode'   => 'HTML',
        'reply_markup' => { 'inline_keyboard' => [
            [{ 'text' => '📲 Настроить VPN', 'url' => 'https://t.me/hq_vpn_bot/web', 'style' => 'primary' }],
            [{ 'text' => '💬 Поддержка', 'url' => 'https://t.me/hq_vpn_support_bot' }]
        ]}
    })) }}
    {{ send_ok = send_result.ok || 0 }}

    {{# Сохраняем состояние #}}
    {{ IF send_ok }}
        {{ save = storage.save(inact_key, {
            'notified'       => 1,
            'connected'      => 0,
            'notify_count'   => stage,
            'stage'          => stage,
            'hours'          => not_connected_hours,
            'first_notify_at' => (flag_data.first_notify_at || current_time),
            'last_notify_at' => current_time,
            'username'       => username,
            'remna_uuid'     => user_uuid
        }) }}

        {{# Кумулятивная статистика (только при stage 1) #}}
        {{ IF stage == 1 }}
            {{ stats = storage.read('name', 'inact_webhook_stats') || {} }}
            {{ save_stats = storage.save('inact_webhook_stats', {
                'total_connected'  => (stats.total_connected  || 0),
                'unique_notified'  => (stats.unique_notified  || 0) + 1,
                'no_telegram'      => (stats.no_telegram      || 0),
                'send_failed'      => (stats.send_failed      || 0),
                'last_event'       => current_time
            }) }}
        {{ END }}
    {{ ELSE }}
        {{# Ошибка отправки — считаем #}}
        {{ stats = storage.read('name', 'inact_webhook_stats') || {} }}
        {{ save_stats = storage.save('inact_webhook_stats', {
            'total_connected'  => (stats.total_connected  || 0),
            'unique_notified'  => (stats.unique_notified  || 0),
            'no_telegram'      => (stats.no_telegram      || 0),
            'send_failed'      => (stats.send_failed      || 0) + 1,
            'last_event'       => current_time
        }) }}
    {{ END }}

    {{# Уведомление админу со статистикой #}}
    {{ stats = storage.read('name', 'inact_webhook_stats') || {} }}
    {{ cum_notified  = (stats.unique_notified  || 0) + 0 }}
    {{ cum_connected = (stats.total_connected  || 0) + 0 }}
    {{ cum_no_tg     = (stats.no_telegram      || 0) + 0 }}
    {{ cum_failed    = (stats.send_failed      || 0) + 0 }}
    {{ effectiveness = 0 }}
    {{ IF cum_notified > 0 }}
        {{ effectiveness = (cum_connected * 100) / cum_notified }}
    {{ END }}

    {{ stage_icon = stage == 1 ? '1️⃣' : stage == 2 ? '2️⃣' : '3️⃣' }}
    {{ admin_msg = "📡 <b>Не подключён</b> " _ stage_icon _ "\n\n" }}
    {{ admin_msg = admin_msg _ "👤 <code>" _ username _ "</code>" }}
    {{ IF shm_tg_login }}
        {{ admin_msg = admin_msg _ ' (<a href="https://t.me/' _ shm_tg_login _ '">@' _ shm_tg_login _ '</a>)' }}
    {{ END }}
    {{ admin_msg = admin_msg _ "\n" }}
    {{ IF service_name }}
        {{ admin_msg = admin_msg _ "📦 " _ service_name _ "\n" }}
    {{ END }}
    {{ IF shm_user_id }}
        {{ admin_msg = admin_msg _ "💰 Баланс: " _ shm_user_balance _ " ₽\n" }}
    {{ END }}
    {{ IF shm_partner_login }}
        {{ admin_msg = admin_msg _ "🤝 Реферал: @" _ shm_partner_login _ "\n" }}
    {{ END }}
    {{ admin_msg = admin_msg _ "⏰ Не подключался: " _ not_connected_hours _ "ч\n" }}
    {{ admin_msg = admin_msg _ "📨 Стадия: " _ stage _ "/3\n" }}
    {{ admin_msg = admin_msg _ "✉️ Отправка: " _ (send_ok ? '✅' : '❌') _ "\n\n" }}
    {{ admin_msg = admin_msg _ "📊 <b>Статистика:</b>\n" }}
    {{ admin_msg = admin_msg _ "😴 Уведомлено: " _ cum_notified _ "\n" }}
    {{ admin_msg = admin_msg _ "🎯 Подключились: " _ cum_connected }}
    {{ IF cum_notified > 0 }}
        {{ admin_msg = admin_msg _ " (<b>" _ effectiveness _ "%</b>)" }}
    {{ END }}
    {{ IF cum_no_tg > 0 }}
        {{ admin_msg = admin_msg _ "\n🚫 Без TG ID: " _ cum_no_tg }}
    {{ END }}
    {{ IF cum_failed > 0 }}
        {{ admin_msg = admin_msg _ "\n❌ Ошибки: " _ cum_failed }}
    {{ END }}

    {{ admin_payload = {
        'chat_id'           => ADMIN_CHAT_ID,
        'message_thread_id' => ADMIN_THREAD_ID,
        'text'              => admin_msg,
        'parse_mode'        => 'HTML'
    } }}
    {{ IF subscription_url }}
        {{ admin_payload.reply_markup = { 'inline_keyboard' => [
            [{ 'text' => '🔗 Подписка', 'url' => subscription_url }]
        ]} }}
    {{ END }}
    {{ admin_send = http.post(tg_url, 'content_type', 'application/json', 'content', toJson(admin_payload)) }}

    {{ toJson({ success => 1, event => event, username => username, stage => stage, hours => not_connected_hours, sent => send_ok }) }}
    {{ STOP }}

{{ END }}


{{# ═══════════════════════════════════════════════════════ #}}
{{#          EVENT: user.first_connected                    #}}
{{#   Юзер впервые подключился — поздравляем               #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ IF event == 'user.first_connected' }}

    {{ inact_key = "inact_" _ short_uuid }}
    {{ flag_data = storage.read('name', inact_key) || {} }}
    {{ was_notified = (flag_data.notify_count || 0) + 0 }}

    {{# Отмечаем подключение #}}
    {{ save = storage.save(inact_key, {
        'connected'    => 1,
        'connected_at' => current_time,
        'notify_count' => was_notified,
        'username'     => username,
        'remna_uuid'   => user_uuid
    }) }}

    {{# Обновляем статистику #}}
    {{ stats = storage.read('name', 'inact_webhook_stats') || {} }}
    {{ new_connected = (stats.total_connected || 0) + 1 }}
    {{ save_stats = storage.save('inact_webhook_stats', {
        'total_connected'  => new_connected,
        'unique_notified'  => (stats.unique_notified || 0),
        'last_event'       => current_time
    }) }}

    {{# Поздравление юзеру #}}
    {{ sent_user = 0 }}
    {{ IF telegram_id && TG_TOKEN }}

        {{ msg = "🎉 <b>VPN успешно подключён!</b>\n\n" }}
        {{ IF service_name }}
            {{ msg = msg _ "📦 Услуга: <b>" _ service_name _ "</b>\n\n" }}
        {{ END }}
        {{ msg = msg _ "✅ Всё работает! Теперь ваш интернет защищён." }}

        {{ send_result = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
            'chat_id'      => telegram_id,
            'text'         => msg,
            'parse_mode'   => 'HTML',
            'reply_markup' => { 'inline_keyboard' => [
                [{ 'text' => '📱 Открыть приложение', 'url' => 'https://t.me/hq_vpn_bot/web', 'style' => 'success' }],
                [{ 'text' => '🌐 Главное меню', 'callback_data' => '/menu' }]
            ]}
        })) }}
        {{ sent_user = send_result.ok || 0 }}
    {{ END }}

    {{# Уведомление админу со статистикой #}}
    {{ cum_notified = (stats.unique_notified || 0) + 0 }}
    {{ effectiveness = 0 }}
    {{ IF cum_notified > 0 }}
        {{ effectiveness = (new_connected * 100) / cum_notified }}
    {{ END }}

    {{ admin_msg = "✅ <b>Первое подключение!</b>\n\n" }}
    {{ admin_msg = admin_msg _ "👤 <code>" _ username _ "</code>" }}
    {{ IF shm_tg_login }}
        {{ admin_msg = admin_msg _ ' (<a href="https://t.me/' _ shm_tg_login _ '">@' _ shm_tg_login _ '</a>)' }}
    {{ END }}
    {{ admin_msg = admin_msg _ "\n" }}
    {{ IF service_name }}
        {{ admin_msg = admin_msg _ "📦 " _ service_name _ "\n" }}
    {{ END }}
    {{ IF shm_user_id }}
        {{ admin_msg = admin_msg _ "💰 Баланс: " _ shm_user_balance _ " ₽\n" }}
    {{ END }}
    {{ IF shm_partner_login }}
        {{ admin_msg = admin_msg _ "🤝 Реферал: @" _ shm_partner_login _ "\n" }}
    {{ END }}
    {{ IF was_notified > 0 }}
        {{ admin_msg = admin_msg _ "📨 Напоминаний до подключения: " _ was_notified _ "\n" }}
    {{ ELSE }}
        {{ admin_msg = admin_msg _ "🎯 Подключился без напоминаний!\n" }}
    {{ END }}
    {{ admin_msg = admin_msg _ "\n📊 <b>Статистика:</b>\n" }}
    {{ admin_msg = admin_msg _ "🎯 Подключились: " _ new_connected }}
    {{ IF cum_notified > 0 }}
        {{ admin_msg = admin_msg _ " из " _ cum_notified _ " (<b>" _ effectiveness _ "%</b>)" }}
    {{ END }}

    {{ admin_send = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
        'chat_id'           => ADMIN_CHAT_ID,
        'message_thread_id' => ADMIN_THREAD_ID,
        'text'              => admin_msg,
        'parse_mode'        => 'HTML'
    })) }}

    {{ toJson({ success => 1, event => event, username => username, notified_before => was_notified, sent => sent_user }) }}
    {{ STOP }}

{{ END }}


{{# ═══════════════════════════════════════════════════════ #}}
{{#  EVENT: user.bandwidth_usage_threshold_reached          #}}
{{#  Трафик достиг порога (80% / 95%)                      #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ IF event == 'user.bandwidth_usage_threshold_reached' }}

    {{ threshold = wh_meta.thresholdPercent || wh_meta.threshold || 0 }}
    {{ used_bytes   = user_traffic.usedTrafficBytes || 0 }}
    {{ limit_bytes  = wh_data.trafficLimitBytes || 0 }}

    {{# Форматируем трафик в ГБ #}}
    {{ IF limit_bytes > 0 }}
        {{ used_gb  = (used_bytes / 1073741824) }}
        {{ limit_gb = (limit_bytes / 1073741824) }}
    {{ ELSE }}
        {{ used_gb  = 0 }}
        {{ limit_gb = 0 }}
    {{ END }}

    {{# Отправляем юзеру #}}
    {{ sent_user = 0 }}
    {{ IF telegram_id && TG_TOKEN }}

        {{ IF threshold >= 90 }}
            {{ msg = "🔴 <b>Трафик почти исчерпан!</b>\n\n" }}
            {{ msg = msg _ "Использовано <b>" _ threshold _ "%</b> от лимита" }}
            {{ IF limit_gb > 0 }}
                {{ msg = msg _ " (" _ used_gb _ " / " _ limit_gb _ " ГБ)" }}
            {{ END }}
            {{ msg = msg _ ".\n\n" }}
            {{ msg = msg _ "⚠️ Скоро трафик закончится.\n\n" }}
            {{ msg = msg _ "Нажмите кнопку ниже, чтобы сбросить трафик 👇" }}
            {{ btn_style = 'danger' }}
        {{ ELSE }}
            {{ msg = "⚠️ <b>Трафик " _ threshold _ "% использован</b>\n\n" }}
            {{ msg = msg _ "Использовано <b>" _ threshold _ "%</b> от лимита" }}
            {{ IF limit_gb > 0 }}
                {{ msg = msg _ " (" _ used_gb _ " / " _ limit_gb _ " ГБ)" }}
            {{ END }}
            {{ msg = msg _ ".\n\n" }}
            {{ msg = msg _ "💡 При исчерпании трафик сбросится автоматически с баланса.\n" }}
            {{ msg = msg _ "Или сбросьте сейчас вручную 👇" }}
            {{ btn_style = 'primary' }}
        {{ END }}

        {{ send_result = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
            'chat_id'      => telegram_id,
            'text'         => msg,
            'parse_mode'   => 'HTML',
            'reply_markup' => { 'inline_keyboard' => [
                [{ 'text' => '🔄 Сбросить трафик', 'url' => 'https://t.me/hq_vpn_bot/web', 'style' => btn_style }]
            ]}
        })) }}
        {{ sent_user = send_result.ok || 0 }}
    {{ END }}

    {{# Обновляем статистику трафика #}}
    {{ tr_stats = storage.read('name', 'wh_traffic_stats') || {} }}
    {{ IF threshold >= 90 }}
        {{ new_critical = (tr_stats.critical_count || 0) + 1 }}
        {{ save_tr = storage.save('wh_traffic_stats', {
            'warning_count'  => (tr_stats.warning_count  || 0),
            'critical_count' => new_critical,
            'last_event'     => current_time
        }) }}
    {{ ELSE }}
        {{ new_warning = (tr_stats.warning_count || 0) + 1 }}
        {{ save_tr = storage.save('wh_traffic_stats', {
            'warning_count'  => new_warning,
            'critical_count' => (tr_stats.critical_count || 0),
            'last_event'     => current_time
        }) }}
    {{ END }}

    {{# Админу со статистикой #}}
    {{ warn_total = (tr_stats.warning_count || 0) + (threshold < 90 ? 1 : 0) }}
    {{ crit_total = (tr_stats.critical_count || 0) + (threshold >= 90 ? 1 : 0) }}

    {{ admin_msg = "📊 <b>Трафик " _ threshold _ "%</b>\n\n" }}
    {{ admin_msg = admin_msg _ "👤 <code>" _ username _ "</code>" }}
    {{ IF shm_tg_login }}
        {{ admin_msg = admin_msg _ ' (<a href="https://t.me/' _ shm_tg_login _ '">@' _ shm_tg_login _ '</a>)' }}
    {{ END }}
    {{ admin_msg = admin_msg _ "\n" }}
    {{ IF service_name }}
        {{ admin_msg = admin_msg _ "📦 " _ service_name _ "\n" }}
    {{ END }}
    {{ IF shm_user_id }}
        {{ admin_msg = admin_msg _ "💰 Баланс: " _ shm_user_balance _ " ₽\n" }}
    {{ END }}
    {{ IF shm_partner_login }}
        {{ admin_msg = admin_msg _ "🤝 Реферал: @" _ shm_partner_login _ "\n" }}
    {{ END }}
    {{ IF limit_gb > 0 }}
        {{ admin_msg = admin_msg _ "📈 " _ used_gb _ " / " _ limit_gb _ " ГБ\n" }}
    {{ END }}
    {{ admin_msg = admin_msg _ "✉️ Уведомление: " _ (sent_user ? '✅' : '❌') _ "\n\n" }}
    {{ admin_msg = admin_msg _ "📊 <b>Статистика трафика:</b>\n" }}
    {{ admin_msg = admin_msg _ "⚠️ Предупреждений (80%): " _ warn_total _ "\n" }}
    {{ admin_msg = admin_msg _ "🔴 Критических (95%): " _ crit_total }}

    {{ admin_payload = {
        'chat_id'           => ADMIN_CHAT_ID,
        'message_thread_id' => ADMIN_THREAD_ID,
        'text'              => admin_msg,
        'parse_mode'        => 'HTML'
    } }}
    {{ IF subscription_url }}
        {{ admin_payload.reply_markup = { 'inline_keyboard' => [
            [{ 'text' => '🔗 Подписка', 'url' => subscription_url }]
        ]} }}
    {{ END }}
    {{ admin_send = http.post(tg_url, 'content_type', 'application/json', 'content', toJson(admin_payload)) }}

    {{ toJson({ success => 1, event => event, username => username, threshold => threshold, sent => sent_user }) }}
    {{ STOP }}

{{ END }}


{{# ═══════════════════════════════════════════════════════ #}}
{{#  EVENT: user.limited                                    #}}
{{#  Трафик 100% — VPN заблокирован, нужен сброс           #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ IF event == 'user.limited' }}

    {{ used_bytes   = user_traffic.usedTrafficBytes || 0 }}
    {{ limit_bytes  = wh_data.trafficLimitBytes || 0 }}

    {{ IF limit_bytes > 0 }}
        {{ used_gb  = (used_bytes / 1073741824) }}
        {{ limit_gb = (limit_bytes / 1073741824) }}
    {{ ELSE }}
        {{ used_gb  = 0 }}
        {{ limit_gb = 0 }}
    {{ END }}

    {{# Отправляем юзеру #}}
    {{ sent_user = 0 }}
    {{ IF telegram_id && TG_TOKEN }}

        {{ msg = "🚫 <b>Трафик исчерпан — VPN заблокирован</b>\n\n" }}
        {{ IF limit_gb > 0 }}
            {{ msg = msg _ "Использовано: <b>" _ used_gb _ " / " _ limit_gb _ " ГБ</b>\n\n" }}
        {{ END }}
        {{ msg = msg _ "Чтобы продолжить пользоваться VPN, сбросьте трафик в приложении 👇" }}

        {{ send_result = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
            'chat_id'      => telegram_id,
            'text'         => msg,
            'parse_mode'   => 'HTML',
            'reply_markup' => { 'inline_keyboard' => [
                [{ 'text' => '🔄 Сбросить трафик', 'url' => 'https://t.me/hq_vpn_bot/web', 'style' => 'danger' }]
            ]}
        })) }}
        {{ sent_user = send_result.ok || 0 }}
    {{ END }}

    {{# Статистика #}}
    {{ tr_stats = storage.read('name', 'wh_traffic_stats') || {} }}
    {{ new_limited = (tr_stats.limited_count || 0) + 1 }}
    {{ save_tr = storage.save('wh_traffic_stats', {
        'warning_count'  => (tr_stats.warning_count  || 0),
        'critical_count' => (tr_stats.critical_count || 0),
        'limited_count'  => new_limited,
        'last_event'     => current_time
    }) }}

    {{# Админу #}}
    {{ admin_msg = "🚫 <b>Трафик исчерпан (100%)</b>\n\n" }}
    {{ admin_msg = admin_msg _ "👤 <code>" _ username _ "</code>" }}
    {{ IF shm_tg_login }}
        {{ admin_msg = admin_msg _ ' (<a href="https://t.me/' _ shm_tg_login _ '">@' _ shm_tg_login _ '</a>)' }}
    {{ END }}
    {{ admin_msg = admin_msg _ "\n" }}
    {{ IF service_name }}
        {{ admin_msg = admin_msg _ "📦 " _ service_name _ "\n" }}
    {{ END }}
    {{ IF shm_user_id }}
        {{ admin_msg = admin_msg _ "💰 Баланс: " _ shm_user_balance _ " ₽\n" }}
    {{ END }}
    {{ IF shm_partner_login }}
        {{ admin_msg = admin_msg _ "🤝 Реферал: @" _ shm_partner_login _ "\n" }}
    {{ END }}
    {{ IF limit_gb > 0 }}
        {{ admin_msg = admin_msg _ "📈 " _ used_gb _ " / " _ limit_gb _ " ГБ\n" }}
    {{ END }}
    {{ admin_msg = admin_msg _ "✉️ Уведомление: " _ (sent_user ? '✅' : '❌') _ "\n\n" }}
    {{ admin_msg = admin_msg _ "📊 <b>Статистика:</b>\n" }}
    {{ admin_msg = admin_msg _ "⚠️ Предупреждений: " _ (tr_stats.warning_count || 0) _ "\n" }}
    {{ admin_msg = admin_msg _ "🔴 Критических: " _ (tr_stats.critical_count || 0) _ "\n" }}
    {{ admin_msg = admin_msg _ "🚫 Заблокировано: " _ new_limited }}

    {{ admin_payload = {
        'chat_id'           => ADMIN_CHAT_ID,
        'message_thread_id' => ADMIN_THREAD_ID,
        'text'              => admin_msg,
        'parse_mode'        => 'HTML'
    } }}
    {{ IF subscription_url }}
        {{ admin_payload.reply_markup = { 'inline_keyboard' => [
            [{ 'text' => '🔗 Подписка', 'url' => subscription_url }]
        ]} }}
    {{ END }}
    {{ admin_send = http.post(tg_url, 'content_type', 'application/json', 'content', toJson(admin_payload)) }}

    {{ toJson({ success => 1, event => event, username => username, sent => sent_user }) }}
    {{ STOP }}

{{ END }}


{{# ═══════════════════════════════════════════════════════ #}}
{{#  Игнорируем все user.* события, не обработанные выше    #}}
{{#  (not_connected, first_connected, bandwidth, limited    #}}
{{#   уже обработаны и завершены через STOP)                #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ IF event.match('^user\\.') }}
{{ toJson({ skip => 'ignored_user_event', event => event }) }}
{{ STOP }}
{{ END }}


{{# ═══════════════════════════════════════════════════════ #}}
{{#  ОСТАЛЬНЫЕ СОБЫТИЯ — лог в админку                      #}}
{{# ═══════════════════════════════════════════════════════ #}}

{{ admin_msg = "📨 <b>Webhook:</b> <code>" _ event _ "</code>\n\n" }}
{{ IF username }}
    {{ admin_msg = admin_msg _ "👤 <code>" _ username _ "</code>\n" }}
{{ END }}
{{ IF wh_data.keys.size > 0 }}
    {{ admin_msg = admin_msg _ "📦 scope: " _ scope }}
{{ END }}

{{ admin_send = http.post(tg_url, 'content_type', 'application/json', 'content', toJson({
    'chat_id'           => ADMIN_CHAT_ID,
    'message_thread_id' => ADMIN_THREAD_ID,
    'text'              => admin_msg,
    'parse_mode'        => 'HTML'
})) }}

{{ toJson({ success => 1, event => event, routed_to => 'admin_log' }) }}
