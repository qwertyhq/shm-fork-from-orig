{{ #
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              CHARGE & RESET TRAFFIC — АВТОМАТИЧЕСКИЙ СБРОС ТРАФИКА          ║
# ║         Списание средств с баланса пользователя + сброс через Remnawave     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ВЕРСИЯ: v1.0.0 (26.02.2026)

# DESCRIPTION:
# Шаблон для автоматического/ручного списания денег с баланса юзера
# и сброса трафика через Remnawave API. Расчёт стоимости полностью
# повторяет логику из telegram_bot и webhook-handler:
#   - СЦЕНАРИЙ 0 (DAY): дневной тариф → стоимость = 1 день
#   - СЦЕНАРИЙ 1 (calendar): expire > конец месяца → по дню календаря
#   - СЦЕНАРИЙ 2 (period): expire в этом месяце → по % оставшегося периода
#   - Минимальная стоимость: 1 руб.
#   - Списание: сначала бонусы, потом баланс
#   - Refund при ошибке API
#   - Уведомление пользователю и админу в Telegram

# ВЫЗОВ:
# Шаблон принимает параметры через request.params:
#   usi        (обязательно) - ID услуги пользователя
#   user_id    (обязательно) - ID пользователя в SHM
#   force      (опционально) - 1 = пропустить проверку использования >= 95%
#   dry_run    (опционально) - 1 = только рассчитать стоимость, не списывать
#   notify     (опционально) - 1 = отправить уведомление в Telegram (default: 1)

# ПРИМЕР ВЫЗОВА (HTTP):
# POST /shm/v1/public/charge-reset-traffic
# Content-Type: application/json
# { "usi": "1056", "user_id": "123", "force": 0, "dry_run": 0 }

# ПРИМЕР ВЫЗОВА (из другого шаблона):
# {{ result = http.post(config.api.url _ '/shm/v1/public/charge-reset-traffic',
#     'content_type', 'application/json',
#     'content', toJson({ 'usi' => usi, 'user_id' => user_id })
# ) }}

# ОТВЕТ (JSON):
# Успех:
# { "success": 1, "charged": 50.0, "from_bonus": 10, "from_balance": 40,
#   "new_balance": 160, "new_bonus": 0, "traffic_reset": 1,
#   "calc_mode": "calendar", "discount_percent": 25 }
# Dry-run:
# { "success": 1, "dry_run": 1, "reset_cost": 50.0, "calc_mode": "calendar",
#   "discount_percent": 25, "can_afford": 1 }
# Ошибка:
# { "error": "описание", "code": 400 }
# }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                              НАСТРОЙКИ                                      #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ storage_prefix = config.remnawave.storage_prefix || 'vpn_mrzb_' }}
{{ telegram_bot_token = config.remnawave.telegram_bot_token || config.telegram.telegram_bot.token || '' }}

{{# Настройки администратора (приоритет: tpls -> config -> хардкод) #}}
{{ admin_group_chat_id = tpl.settings.admin_group.chat_id || config.remnawave.admin_group_chat_id || -1001965226181 }}
{{ admin_group_thread_id = tpl.settings.admin_group.thread_id || config.remnawave.admin_group_thread_id || 28953 }}
{{ admin_chat_id = admin_group_chat_id || tpl.settings.admin.chat_id || config.remnawave.admin_chat_id || '' }}
{{ admin_thread_id = admin_group_thread_id || '' }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                    ФУНКЦИЯ ОТПРАВКИ ОШИБОК АДМИНУ                           #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ BLOCK send_error_to_admin }}
{{ IF admin_chat_id && telegram_bot_token }}
    {{ err_tg_url = 'https://api.telegram.org/bot' _ telegram_bot_token _ '/sendMessage' }}
    {{ err_payload = {
        'chat_id' => admin_chat_id,
        'text' => err_text,
        'parse_mode' => 'HTML'
    } }}
    {{ IF admin_thread_id && admin_thread_id != '' }}
        {{ err_payload.message_thread_id = admin_thread_id }}
    {{ END }}
    {{ err_result = http.post(err_tg_url, 'content_type', 'application/json', 'content', toJson(err_payload)) }}
{{ END }}
{{ END }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                       ПАРСИНГ ВХОДНЫХ ПАРАМЕТРОВ                            #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ usi = request.params.usi || '' }}
{{ req_user_id = request.params.user_id || '' }}
{{ force_reset = request.params.force || 0 }}
{{ dry_run = request.params.dry_run || 0 }}
{{ notify_user = request.params.notify }}
{{ IF notify_user == '' }}{{ notify_user = 1 }}{{ END }}

{{# Валидация обязательных полей #}}
{{ IF usi == '' }}
{{ toJson({ error => 'Missing required parameter: usi', code => 400 }) }}
{{ STOP }}
{{ END }}

{{ IF req_user_id == '' }}
{{ toJson({ error => 'Missing required parameter: user_id', code => 400 }) }}
{{ STOP }}
{{ END }}

{{# Валидация: usi должен быть числом #}}
{{ IF !usi.match('^\d+$') }}
{{ toJson({ error => 'Invalid usi format - must be a number', code => 400, usi => usi }) }}
{{ STOP }}
{{ END }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                       ЗАГРУЗКА ДАННЫХ ПОЛЬЗОВАТЕЛЯ                          #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{# Загружаем услугу и пользователя из SHM #}}
{{ shm_service = us.id(usi) }}
{{ IF !shm_service.user_id }}
{{ toJson({ error => 'Service not found', code => 404, usi => usi }) }}
{{ STOP }}
{{ END }}

{{# Проверяем что user_id совпадает (безопасность) #}}
{{ IF shm_service.user_id != req_user_id }}
{{ toJson({ error => 'User ID mismatch', code => 403 }) }}
{{ STOP }}
{{ END }}

{{ shm_user = user.id(shm_service.user_id) }}
{{ IF !shm_user.id }}
{{ toJson({ error => 'User not found', code => 404, user_id => req_user_id }) }}
{{ STOP }}
{{ END }}

{{ tg_chat_id = shm_user.settings.telegram.chat_id || '' }}

{{# Загружаем storage #}}
{{ storage_key = storage_prefix _ usi }}
{{ storage_data = storage.read('name', storage_key) }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#              ПОЛУЧЕНИЕ ДАННЫХ ИЗ REMNAWAVE ПО USERNAME                      #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{# Получаем HOST/TOKEN: config → server → hardcoded fallback #}}
{{ HOST = config.remnawave.api_host || server.id(1).settings.api.host || 'https://p.z-hq.com' }}
{{ TOKEN = config.remnawave.api_token || server.id(1).settings.api.token || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1dWlkIjoiZGI0MGFhYTctOTQwNi00ZTVhLWFmMzYtN2UxYTcyYjEzZjlkIiwidXNlcm5hbWUiOm51bGwsInJvbGUiOiJBUEkiLCJpYXQiOjE3NDc3NjgxNTAsImV4cCI6MTAzODc2ODE3NTB9.h_ylJtAkaaTu00YNfCv-iClafd3unN3dEHWlwVqNOhQ' }}
{{ headers = { 'Authorization' => 'Bearer ' _ TOKEN } }}

{{# Имя услуги в Remnawave: HQVPN_{usi} #}}
{{ remna_username = 'HQVPN_' _ usi }}

{{# Ищем пользователя по username в Remnawave API #}}
{{ URL_check = HOST _ '/api/users/by-username/' _ remna_username }}
{{ api_user = http.get(URL_check, 'headers', headers) }}

{{ IF !api_user.response || !api_user.response.uuid }}
{{ err_text = BLOCK }}🚨 <b>CHARGE-RESET ERROR</b>

❌ Пользователь не найден в Remnawave
🆔 USI: <code>{{ usi }}</code>
👤 User ID: <code>{{ req_user_id }}</code>
🔎 Username: <code>{{ remna_username }}</code>
🔗 URL: <code>{{ URL_check }}</code>{{ END }}
{{ INCLUDE send_error_to_admin }}
{{ toJson({ error => 'User not found in Remnawave', code => 404, usi => usi, username => remna_username, url => URL_check, api_response => api_user }) }}
{{ STOP }}
{{ END }}

{{# UUID берём из ответа API #}}
{{ user_uuid = api_user.response.uuid }}

{{# Дата последнего сброса трафика (начало текущего цикла) #}}
{{ last_reset_at = api_user.response.lastTrafficResetAt || api_user.response.createdAt || '' }}

{{ used_bytes = api_user.response.userTraffic.usedTrafficBytes || 0 }}
{{ limit_bytes = api_user.response.trafficLimitBytes || 0 }}
{{ used_gb = (used_bytes / 1073741824) }}
{{ limit_gb = (limit_bytes / 1073741824) }}
{{ IF limit_bytes > 0 }}
    {{ used_percent = ((used_bytes / limit_bytes) * 100) }}
{{ ELSE }}
    {{ used_percent = 0 }}
{{ END }}
{{ used_gb_fmt = used_gb FILTER format("%.2f") }}
{{ limit_gb_fmt = limit_gb FILTER format("%.0f") }}
{{ used_percent_fmt = used_percent FILTER format("%.1f") }}
{{ used_percent_num = used_percent + 0 }}

{{# Проверка: трафик уже сброшен? #}}
{{ IF used_percent_num < 5 && !force_reset }}
{{ toJson({ error => 'Traffic already reset', code => 409, used_percent => used_percent_fmt, used_gb => used_gb_fmt, limit_gb => limit_gb_fmt }) }}
{{ STOP }}
{{ END }}

{{# Проверка: потребление >= 95% (или force) #}}
{{ IF used_percent_num < 95 && !force_reset }}
{{ toJson({ error => 'Usage below 95% threshold', code => 400, used_percent => used_percent_fmt, required => '95%', hint => 'Use force=1 to override' }) }}
{{ STOP }}
{{ END }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                    РАСЧЁТ СТОИМОСТИ СБРОСА ТРАФИКА                          #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ USE date }}
{{ current_day = date.format(date.now, '%d') + 0 }}
{{ current_month = date.format(date.now, '%m') + 0 }}
{{ current_year = date.format(date.now, '%Y') + 0 }}
{{ current_hour = date.format(date.now, '%H') + 0 }}

{{# Получаем данные услуги #}}
{{ u_service = shm_user.services.list_for_api('usi', usi) }}
{{ srv = service.list_for_api('service_id', u_service.service_id) }}
{{ srv_period = srv.period || 1 }}
{{ user_discount = shm_user.discount || 0 }}
{{ discount_mult = user_discount > 0 ? (1 - 0.01 * user_discount) : 1 }}

{{# Стратегия сброса (приоритет: услуга → config → MONTH) #}}
{{ reset_strategy = u_service.service.settings.data_limit_reset_strategy || config.remnawave.data_limit_reset_strategy || 'MONTH' }}

{{# Парсим период M.DDHH для расчёта дней в периоде #}}
{{ period_int = srv_period FILTER format("%.0f") }}
{{ period_frac = srv_period - period_int }}
{{ period_frac_num = (period_frac * 10000) FILTER format("%.0f") }}
{{ extra_days_p = (period_frac_num / 100) FILTER format("%.0f") }}
{{ extra_hours_p = period_frac_num - (extra_days_p * 100) }}
{{ period_days_total = (period_int * 30) + extra_days_p + (extra_hours_p / 24) }}
{{ IF period_days_total < 1 }}{{ period_days_total = 1 }}{{ END }}

{{# Авто-fallback: при периоде < 1 месяца → дневной расчёт #}}
{{ IF reset_strategy == 'MONTH' && period_int < 1 }}
    {{ reset_strategy = 'DAY' }}
{{ END }}

{{# Расчёт базовой стоимости #}}
{{ IF reset_strategy == 'DAY' }}
    {{# DAY: стоимость одного дня = полная стоимость / дни в периоде #}}
    {{ daily_cost = (u_service.cost * discount_mult) / period_days_total }}
    {{ base_cost = daily_cost FILTER format("%.0f") }}
    {{ IF base_cost < 1 }}{{ base_cost = 1 }}{{ END }}
{{ ELSE }}
    {{# MONTH: месячная стоимость = полная / период #}}
    {{ monthly_cost = (u_service.cost / srv_period) * discount_mult }}
    {{ base_cost = monthly_cost FILTER format("%.0f") }}
    {{# Защита: base_cost не может быть больше полной стоимости #}}
    {{ full_cost = (u_service.cost * discount_mult) FILTER format("%.0f") }}
    {{ IF base_cost > full_cost }}{{ base_cost = full_cost }}{{ END }}
{{ END }}

{{# Определяем, заканчивается ли подписка в этом месяце #}}
{{ expire_day = date.format(u_service.expire, '%d') + 0 }}
{{ expire_month = date.format(u_service.expire, '%m') + 0 }}
{{ expire_year = date.format(u_service.expire, '%Y') + 0 }}
{{ expires_this_month = (expire_month == current_month && expire_year == current_year) ? 1 : 0 }}

{{# Расчёт стоимости по сценариям #}}
{{ IF reset_strategy == 'DAY' }}
    {{# СЦЕНАРИЙ 0: Дневной тариф — фиксированная стоимость #}}
    {{ calc_mode = 'daily' }}
    {{ reset_percent = 100 }}
    {{ discount_percent = 0 }}
    {{ reset_cost = base_cost }}
{{ ELSIF expires_this_month }}
    {{# СЦЕНАРИЙ 2: Подписка заканчивается в этом месяце → по % оставшегося периода #}}
    {{ expire_ts = date.format(u_service.expire, '%s') }}
    {{ now_ts = date.now }}
    {{ days_left = ((expire_ts - now_ts) / 86400) FILTER format("%.0f") }}
    {{ days_left = days_left + 0 }}
    {{ IF days_left < 0 }}{{ days_left = 0 }}{{ END }}
    {{ period_days = expire_day }}
    {{ IF period_days < 1 }}{{ period_days = 1 }}{{ END }}
    {{ remaining_percent = (days_left / period_days) * 100 }}
    {{ calc_mode = 'period' }}
    {{# 5 зон по % оставшегося периода #}}
    {{ IF remaining_percent > 80 }}
        {{ reset_percent = 100 }}
        {{ discount_percent = 0 }}
        {{ reset_cost = base_cost }}
    {{ ELSIF remaining_percent > 60 }}
        {{ reset_percent = 75 }}
        {{ discount_percent = 25 }}
        {{ reset_cost = (base_cost * 0.75) }}
    {{ ELSIF remaining_percent > 40 }}
        {{ reset_percent = 50 }}
        {{ discount_percent = 50 }}
        {{ reset_cost = (base_cost * 0.5) }}
    {{ ELSIF remaining_percent > 20 }}
        {{ reset_percent = 25 }}
        {{ discount_percent = 75 }}
        {{ reset_cost = (base_cost * 0.25) }}
    {{ ELSE }}
        {{ reset_percent = 10 }}
        {{ discount_percent = 90 }}
        {{ reset_cost = (base_cost * 0.1) }}
    {{ END }}
{{ ELSE }}
    {{# СЦЕНАРИЙ 1: Подписка НЕ в этом месяце → по циклу трафика (lastTrafficResetAt) #}}
    {{# Определяем начало текущего цикла и вычисляем прогресс #}}
    {{ now_ts = date.now }}
    {{ IF last_reset_at != '' }}
        {{ cycle_start_ts = date.format(last_reset_at, '%s') }}
    {{ ELSE }}
        {{# Fallback: начало текущего месяца #}}
        {{ fallback_date = current_year _ '-' _ (current_month < 10 ? '0' : '') _ current_month _ '-01' }}
        {{ cycle_start_ts = date.format(fallback_date, '%s') }}
    {{ END }}

    {{# Длительность цикла: 30 дней для MONTH strategy #}}
    {{ cycle_days = 30 }}
    {{ cycle_seconds = cycle_days * 86400 }}
    {{ elapsed_seconds = now_ts - cycle_start_ts }}
    {{ IF elapsed_seconds < 0 }}{{ elapsed_seconds = 0 }}{{ END }}

    {{ days_since_reset = (elapsed_seconds / 86400) }}
    {{ days_since_reset_int = days_since_reset FILTER format("%.0f") }}
    {{ days_since_reset_int = days_since_reset_int + 0 }}
    {{ days_until_next_reset = cycle_days - days_since_reset }}
    {{ IF days_until_next_reset < 0 }}{{ days_until_next_reset = 0 }}{{ END }}
    {{ hours_until_next_reset = days_until_next_reset * 24 }}
    {{ cycle_percent = (elapsed_seconds / cycle_seconds) * 100 }}
    {{ cycle_percent_fmt = cycle_percent FILTER format("%.1f") }}

    {{ IF hours_until_next_reset < 12 }}
        {{# Меньше 12 часов до автосброса — бесплатно #}}
        {{ calc_mode = 'free_reset' }}
        {{ reset_cost = 0 }}
        {{ reset_percent = 0 }}
        {{ discount_percent = 100 }}
    {{ ELSIF days_until_next_reset < 3 }}
        {{# Меньше 3 дней до автосброса — по оставшимся дням #}}
        {{ calc_mode = 'daily_until_reset' }}
        {{ daily_cost_calc = base_cost / cycle_days }}
        {{ reset_cost = (daily_cost_calc * days_until_next_reset) }}
        {{ reset_percent = 0 }}
        {{ discount_percent = 0 }}
    {{ ELSIF cycle_percent > 83 }}
        {{# >83% цикла прошло (25+ дней из 30) #}}
        {{ calc_mode = 'cycle' }}
        {{ reset_percent = 25 }}
        {{ discount_percent = 75 }}
        {{ reset_cost = (base_cost * 0.25) }}
    {{ ELSIF cycle_percent > 66 }}
        {{# >66% цикла прошло (20+ дней из 30) #}}
        {{ calc_mode = 'cycle' }}
        {{ reset_percent = 50 }}
        {{ discount_percent = 50 }}
        {{ reset_cost = (base_cost * 0.5) }}
    {{ ELSIF cycle_percent > 50 }}
        {{# >50% цикла прошло (15+ дней из 30) #}}
        {{ calc_mode = 'cycle' }}
        {{ reset_percent = 75 }}
        {{ discount_percent = 25 }}
        {{ reset_cost = (base_cost * 0.75) }}
    {{ ELSE }}
        {{# Первая половина цикла — полная стоимость #}}
        {{ calc_mode = 'cycle' }}
        {{ reset_percent = 100 }}
        {{ discount_percent = 0 }}
        {{ reset_cost = base_cost }}
    {{ END }}
{{ END }}

{{# Минимальная стоимость — не меньше 1 рубля (кроме бесплатного сброса) #}}
{{ IF calc_mode != 'free_reset' && reset_cost < 1 }}{{ reset_cost = 1 }}{{ END }}
{{ reset_cost_fmt = reset_cost FILTER format("%.1f") }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                            ПРОВЕРКА БАЛАНСА                                 #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ user_balance = shm_user.balance + 0 }}
{{ user_bonus = shm_user.get_bonus + 0 }}
{{ total_available = user_balance + user_bonus }}

{{# DRY RUN — только расчёт, без списания #}}
{{ IF dry_run }}
{{ toJson({
    success => 1,
    dry_run => 1,
    reset_cost => reset_cost + 0,
    reset_cost_fmt => reset_cost_fmt,
    calc_mode => calc_mode,
    base_cost => base_cost + 0,
    discount_percent => discount_percent,
    reset_percent => reset_percent,
    reset_strategy => reset_strategy,
    last_reset_at => last_reset_at,
    cycle_percent => cycle_percent_fmt || '',
    days_since_reset => days_since_reset_int || 0,
    balance => user_balance,
    bonus => user_bonus,
    total_available => total_available,
    can_afford => (total_available >= reset_cost) ? 1 : 0,
    used_percent => used_percent_fmt,
    used_gb => used_gb_fmt,
    limit_gb => limit_gb_fmt,
    usi => usi,
    user_id => req_user_id
}) }}
{{ STOP }}
{{ END }}

{{# Проверка достаточности средств #}}
{{ IF total_available < reset_cost }}
{{ shortfall_val = (reset_cost - total_available) FILTER format("%.1f") }}
{{ toJson({
    error => 'Insufficient funds',
    code => 402,
    required => reset_cost + 0,
    available => total_available,
    balance => user_balance,
    bonus => user_bonus,
    shortfall => shortfall_val
}) }}
{{ STOP }}
{{ END }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                         СПИСАНИЕ СРЕДСТВ                                    #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{# Списываем: сначала бонусы, потом основной баланс #}}
{{ reset_cost_num = reset_cost + 0 }}
{{ from_bonus = 0 }}
{{ from_balance = 0 }}

{{ IF reset_cost_num == 0 }}
    {{# Бесплатный сброс (< 12 часов до конца месяца) — ничего не списываем #}}
    {{ from_bonus = 0 }}
    {{ from_balance = 0 }}
{{ ELSIF user_bonus > 0 }}
    {{# Есть бонусы — списываем сначала их #}}
    {{ IF user_bonus >= reset_cost_num }}
        {{# Хватает бонусов полностью #}}
        {{ bonus_payment = shm_user.add_bonus(0 - reset_cost_num, 'Сброс трафика (бонусы) для услуги #' _ usi) }}
        {{ from_bonus = reset_cost_num }}
        {{ from_balance = 0 }}
    {{ ELSE }}
        {{# Бонусов не хватает — все бонусы + остаток с баланса #}}
        {{ bonus_payment = shm_user.add_bonus(0 - user_bonus, 'Сброс трафика (бонусы) для услуги #' _ usi) }}
        {{ remaining_to_pay = reset_cost_num - user_bonus }}
        {{ new_balance = user_balance - remaining_to_pay }}
        {{ balance_payment = shm_user.set(balance = new_balance) }}
        {{ from_bonus = user_bonus }}
        {{ from_balance = remaining_to_pay }}
    {{ END }}
{{ ELSE }}
    {{# Бонусов нет — списываем с основного баланса #}}
    {{ new_balance = user_balance - reset_cost_num }}
    {{ payment_result = shm_user.set(balance = new_balance) }}
    {{ from_bonus = 0 }}
    {{ from_balance = reset_cost_num }}
{{ END }}

{{# ═══════════════════════════════════════════════════════════════════════════ #}}
{{#                   ВЫЗОВ API СБРОСА ТРАФИКА REMNAWAVE                        #}}
{{# ═══════════════════════════════════════════════════════════════════════════ #}}

{{ URL_reset = HOST _ '/api/users/' _ user_uuid _ '/actions/reset-traffic' }}
{{ api_result = http.post(URL_reset, 'headers', headers) }}

{{ IF api_result.response.status == 'ACTIVE' || api_result.response.uuid }}
    {{# ═══════════════════════ СБРОС УСПЕШЕН ═══════════════════════ #}}

    {{# Безопасное обновление storage #}}
    {{ IF storage_data.response }}
        {{ IF api_result.response.status }}
            {{ storage_data.response.status = api_result.response.status }}
        {{ END }}
        {{ IF api_result.response.trafficLimitBytes }}
            {{ storage_data.response.trafficLimitBytes = api_result.response.trafficLimitBytes }}
        {{ END }}
        {{ IF api_result.response.expireAt }}
            {{ storage_data.response.expireAt = api_result.response.expireAt }}
        {{ END }}
        {{ IF api_result.response.lastTrafficResetAt }}
            {{ storage_data.response.lastTrafficResetAt = api_result.response.lastTrafficResetAt }}
        {{ END }}
        {{# lastTriggeredThreshold сбрасывается в null при сбросе трафика #}}
        {{ storage_data.response.lastTriggeredThreshold = api_result.response.lastTriggeredThreshold }}

        {{# Безопасный мерж userTraffic #}}
        {{ IF api_result.response.userTraffic }}
            {{ IF !storage_data.response.userTraffic }}
                {{ storage_data.response.userTraffic = {} }}
            {{ END }}
            {{ IF api_result.response.userTraffic.usedTrafficBytes != null }}
                {{ storage_data.response.userTraffic.usedTrafficBytes = api_result.response.userTraffic.usedTrafficBytes }}
            {{ END }}
            {{ IF api_result.response.userTraffic.lifetimeUsedTrafficBytes != null }}
                {{ storage_data.response.userTraffic.lifetimeUsedTrafficBytes = api_result.response.userTraffic.lifetimeUsedTrafficBytes }}
            {{ END }}
            {{ IF api_result.response.userTraffic.onlineAt }}
                {{ storage_data.response.userTraffic.onlineAt = api_result.response.userTraffic.onlineAt }}
            {{ END }}
            {{ IF api_result.response.userTraffic.firstConnectedAt }}
                {{ storage_data.response.userTraffic.firstConnectedAt = api_result.response.userTraffic.firstConnectedAt }}
            {{ END }}
            {{ IF api_result.response.userTraffic.lastConnectedNodeUuid }}
                {{ storage_data.response.userTraffic.lastConnectedNodeUuid = api_result.response.userTraffic.lastConnectedNodeUuid }}
            {{ END }}
        {{ END }}

        {{ save_result = storage.save(storage_key, storage_data) }}
    {{ END }}

    {{# ═══════════════════════ УВЕДОМЛЕНИЕ ПОЛЬЗОВАТЕЛЮ ═══════════════════════ #}}
    {{ IF notify_user && tg_chat_id != '' && telegram_bot_token != '' }}
        {{ tg_text = BLOCK }}
✅ <b>Трафик успешно сброшен!</b>

📦 <b>Тариф:</b> {{ u_service.name }}

💳 <b>Списано:</b> {{ reset_cost_fmt }} руб.{{ IF discount_percent > 0 }} <i>(скидка {{ discount_percent }}%)</i>{{ END }}
{{ IF from_bonus > 0 && from_balance > 0 }}├ С бонусов: {{ from_bonus FILTER format("%.1f") }} руб.
└ С баланса: {{ from_balance FILTER format("%.1f") }} руб.
{{ ELSIF from_bonus > 0 }}└ С бонусов: {{ from_bonus FILTER format("%.1f") }} руб.
{{ ELSIF from_balance > 0 }}└ С баланса: {{ from_balance FILTER format("%.1f") }} руб.
{{ ELSE }}└ Бесплатный сброс 🎁
{{ END }}
💰 <b>Новый баланс:</b> {{ shm_user.balance }} руб.{{ IF shm_user.get_bonus > 0 }} + {{ shm_user.get_bonus }} бонусов{{ END }}

Теперь вы можете продолжить использование VPN! 🚀
{{ END }}
        {{ tg_buttons = [
            [{ 'text' => '📊 Подробнее', 'url' => 'https://t.me/hq_vpn_bot/web' }],
            [{ 'text' => '🏠 Главное меню', 'callback_data' => '/menu' }]
        ] }}
        {{ tg_url = 'https://api.telegram.org/bot' _ telegram_bot_token _ '/sendMessage' }}
        {{ tg_payload = {
            'chat_id' => tg_chat_id,
            'text' => tg_text,
            'parse_mode' => 'HTML',
            'reply_markup' => { 'inline_keyboard' => tg_buttons }
        } }}
        {{ tg_send_result = http.post(tg_url, 'content_type', 'application/json', 'content', toJson(tg_payload)) }}
    {{ END }}

    {{# ═══════════════════════ УВЕДОМЛЕНИЕ АДМИНИСТРАТОРУ ═══════════════════════ #}}
    {{ IF admin_chat_id && telegram_bot_token }}
        {{ interface_icon = shm_user.settings.interface == 'web' ? '🌐' : '🤖' }}
        {{ admin_text = BLOCK }}🔁 <b>Сброс трафика (charge-reset)</b>

👤 <code>{{ storage_prefix _ usi }}</code>{{ shm_user.settings.telegram.login ? ' (@' _ shm_user.settings.telegram.login _ ')' : '' }} {{ interface_icon }}
🆔 USI: <code>{{ usi }}</code> | UID: <code>{{ shm_user.id }}</code>

📊 <b>Было:</b> {{ used_gb_fmt }} ГБ из {{ limit_gb_fmt }} ГБ ({{ used_percent_fmt }}%)

💳 <b>Списано:</b> {{ reset_cost_fmt }} руб.
{{ IF from_bonus > 0 && from_balance > 0 }}├ Бонусы: {{ from_bonus FILTER format("%.1f") }} руб.
└ Баланс: {{ from_balance FILTER format("%.1f") }} руб.{{ ELSIF from_bonus > 0 }}└ Бонусы: {{ from_bonus FILTER format("%.1f") }} руб.{{ ELSE }}└ Баланс: {{ from_balance FILTER format("%.1f") }} руб.{{ END }}

💰 <b>Новый баланс:</b> {{ shm_user.balance }} руб. (бонусы: {{ shm_user.get_bonus }})
📅 <b>Скидка:</b> {{ discount_percent }}% | Режим: {{ calc_mode }}
{{ END }}
        {{# Кнопка с ссылкой на подписку #}}
        {{ subscription_url = storage_data.response.subscriptionUrl || '' }}
        {{ admin_buttons = [] }}
        {{ IF subscription_url && subscription_url.grep('^https:').first }}
            {{ u_status = api_result.response.status || 'UNKNOWN' }}
            {{- SWITCH u_status }}
            {{- CASE 'ACTIVE' }}{{- status_icon = '🟢' }}
            {{- CASE 'LIMITED' }}{{- status_icon = '🔴' }}
            {{- CASE 'BLOCK' }}{{- status_icon = '🔴' }}
            {{- CASE 'DISABLED' }}{{- status_icon = '🔴' }}
            {{- CASE 'NOT PAID' }}{{- status_icon = '🟠' }}
            {{- CASE }}{{- status_icon = '⏳' }}
            {{- END }}
            {{ USE btn_date = date }}
            {{ expire_at = api_result.response.expireAt || u_service.expire || '' }}
            {{ expire_fmt = '' }}
            {{ IF expire_at }}
                {{- expire_ts = btn_date.format(expire_at, '%s') }}
                {{- now_ts = btn_date.now }}
                {{- remaining = expire_ts - now_ts }}
                {{- d_left = remaining / 86400 }}
                {{- IF remaining < 86400 }}
                    {{- expire_fmt = btn_date.format(expire_at, '%d.%m %H:%M') }}
                {{- ELSIF d_left <= 3 }}
                    {{- expire_fmt = btn_date.format(expire_at, '%d.%m %H:%M') }}
                {{- ELSE }}
                    {{- expire_fmt = btn_date.format(expire_at, '%d.%m.%Y') }}
                {{- END }}
            {{ END }}
            {{- btn_text = status_icon _ ' ' _ (u_service.name || 'HQVPN_' _ usi) _ (expire_fmt ? ' (до ' _ expire_fmt _ ')' : '') }}
            {{ admin_buttons.push([{ 'text' => btn_text, 'url' => subscription_url }]) }}
        {{ END }}
        {{ admin_payload = {
            'chat_id' => admin_chat_id,
            'text' => admin_text,
            'parse_mode' => 'HTML'
        } }}
        {{ IF admin_buttons.size > 0 }}
            {{ admin_payload.reply_markup = { 'inline_keyboard' => admin_buttons } }}
        {{ END }}
        {{ IF admin_thread_id && admin_thread_id != '' }}
            {{ admin_payload.message_thread_id = admin_thread_id }}
        {{ END }}
        {{ admin_tg_url = 'https://api.telegram.org/bot' _ telegram_bot_token _ '/sendMessage' }}
        {{ admin_send_result = http.post(admin_tg_url, 'content_type', 'application/json', 'content', toJson(admin_payload)) }}
    {{ END }}

    {{# Успешный ответ #}}
{{ toJson({
    success => 1,
    event => 'charge_and_reset_traffic',
    usi => usi,
    user_id => req_user_id,
    charged => reset_cost + 0,
    charged_fmt => reset_cost_fmt,
    from_bonus => from_bonus,
    from_balance => from_balance,
    new_balance => shm_user.balance + 0,
    new_bonus => shm_user.get_bonus + 0,
    traffic_reset => 1,
    storage_updated => 1,
    calc_mode => calc_mode,
    base_cost => base_cost + 0,
    discount_percent => discount_percent,
    reset_strategy => reset_strategy,
    was_used_percent => used_percent_fmt,
    was_used_gb => used_gb_fmt,
    limit_gb => limit_gb_fmt,
    notification_sent => (notify_user && tg_chat_id != '' ? 1 : 0)
}) }}

{{ ELSE }}
    {{# ═══════════════════════ ОШИБКА API — ВОЗВРАТ СРЕДСТВ ═══════════════════════ #}}

    {{# Возвращаем бонусы #}}
    {{ IF from_bonus > 0 }}
        {{ refund_bonus = shm_user.add_bonus(from_bonus, 'Возврат бонусов - ошибка сброса трафика #' _ usi) }}
    {{ END }}
    {{# Возвращаем баланс #}}
    {{ IF from_balance > 0 }}
        {{ refund_new_balance = shm_user.balance + from_balance }}
        {{ refund_balance = shm_user.set(balance = refund_new_balance) }}
    {{ END }}

    {{# Уведомление админу об ошибке #}}
    {{ err_text = BLOCK }}❌ <b>ОШИБКА сброса трафика!</b>

👤 <code>{{ storage_prefix _ usi }}</code>{{ shm_user.settings.telegram.login ? ' (@' _ shm_user.settings.telegram.login _ ')' : '' }}
🆔 USI: <code>{{ usi }}</code> | UID: <code>{{ shm_user.id }}</code>
🔑 UUID: <code>{{ user_uuid }}</code>

⚠️ <b>Ошибка API:</b> {{ api_result.message || 'Неизвестная ошибка' }}
📋 <b>Статус:</b> {{ api_result.response.status || api_result.status || 'N/A' }}

💸 <b>Деньги возвращены:</b>
{{ IF from_bonus > 0 && from_balance > 0 }}├ Бонусы: {{ from_bonus FILTER format("%.1f") }} руб.
└ Баланс: {{ from_balance FILTER format("%.1f") }} руб.{{ ELSIF from_bonus > 0 }}└ Бонусы: {{ from_bonus FILTER format("%.1f") }} руб.{{ ELSE }}└ Баланс: {{ from_balance FILTER format("%.1f") }} руб.{{ END }}{{ END }}
    {{ INCLUDE send_error_to_admin }}

    {{# Уведомление пользователю об ошибке #}}
    {{ IF notify_user && tg_chat_id != '' && telegram_bot_token != '' }}
        {{ tg_err_text = BLOCK }}
❌ <b>Ошибка при сбросе трафика</b>

Произошла техническая ошибка. Средства возвращены на ваш баланс.
Пожалуйста, попробуйте позже или обратитесь в поддержку.
{{ END }}
        {{ tg_err_buttons = [
            [{ 'text' => '🔄 Попробовать снова', 'callback_data' => '/reset_traffic ' _ usi }],
            [{ 'text' => '💬 Поддержка', 'url' => 'https://t.me/hq_vpn_support_bot' }]
        ] }}
        {{ tg_err_url = 'https://api.telegram.org/bot' _ telegram_bot_token _ '/sendMessage' }}
        {{ tg_err_payload = {
            'chat_id' => tg_chat_id,
            'text' => tg_err_text,
            'parse_mode' => 'HTML',
            'reply_markup' => { 'inline_keyboard' => tg_err_buttons }
        } }}
        {{ tg_err_send = http.post(tg_err_url, 'content_type', 'application/json', 'content', toJson(tg_err_payload)) }}
    {{ END }}

{{ toJson({
    error => 'Remnawave API reset failed',
    code => 502,
    api_status => api_result.response.status || api_result.status || 'unknown',
    api_message => api_result.message || '',
    refunded => reset_cost + 0,
    refund_bonus => from_bonus,
    refund_balance => from_balance,
    usi => usi
}) }}

{{ END }}
