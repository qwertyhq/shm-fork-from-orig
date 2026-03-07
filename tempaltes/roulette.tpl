{{#
    Шаблон Бонусной Рулетки (API для Web App)
    
    Endpoint: https://admin.ev-agency.io/shm/v1/template/roulette
    
    Логика:
    - Пользователь делает ставку с основного баланса
    - Выигрыш начисляется на бонусный баланс
    
    Actions:
    - action=spin&bet=100  - Крутить рулетку
    - action=config        - Получить конфигурацию
    - action=stats         - Статистика пользователя
    - action=admin_stats   - Статистика всех игроков (только для админа)
#}}

{{# ============== КОНФИГУРАЦИЯ РУЛЕТКИ ============== #}}

{{# Telegram уведомления админу (тот же чат что и hwid_notify) #}}
{{ ADMIN_CHAT_ID = -1001965226181 }}
{{ ADMIN_THREAD_ID = 28953 }}
{{ TG_TOKEN = config.telegram.telegram_bot.token || config.telegram.token || "" }}

{{ MIN_BET = 10 }}
{{ MAX_BET = 500 }}
{{ PRESET_BETS = [10, 25, 50, 100, 250, 500] }}

{{# Сегменты: [id, множитель, вероятность (из 1000), название] #}}
{{# EV = 0.75 (дом в плюсе ~25%) #}}
{{ SEGMENTS = [
    { id => 0, mult => 0,   prob => 450, name => '0x' },
    { id => 1, mult => 0.5, prob => 250, name => '0.5x' },
    { id => 2, mult => 1,   prob => 180, name => '1x' },
    { id => 3, mult => 1.5, prob => 75,  name => '1.5x' },
    { id => 4, mult => 2,   prob => 30,  name => '2x' },
    { id => 5, mult => 3,   prob => 10,  name => '3x' },
    { id => 6, mult => 5,   prob => 4,   name => '5x' },
    { id => 7, mult => 10,  prob => 1,   name => '10x' }
] }}

{{# ============== ФУНКЦИЯ ВЫБОРА СЕГМЕНТА ============== #}}

{{ BLOCK select_segment }}
    {{ USE Math }}
    {{ random_val = Math.int(Math.rand(1000)) + 1 }}
    {{ cumulative = 0 }}
    {{ result_segment = SEGMENTS.0 }}
    {{ segment_found = 0 }}
    {{ FOREACH seg IN SEGMENTS }}
        {{ cumulative = cumulative + seg.prob }}
        {{ IF random_val <= cumulative && !segment_found }}
            {{ result_segment = seg }}
            {{ segment_found = 1 }}
        {{ END }}
    {{ END }}
{{ END }}

{{# ============== API ============== #}}
{{# Авторизация через session_id обрабатывается SHM автоматически #}}
{{# Вызов: ?action=spin&bet=100&session_id=YOUR_SESSION_ID #}}

{{ req = request() }}
{{ action = req.params.action }}
{{ bet = req.params.bet + 0 }}

{{# Минимальная сумма платежей для доступа #}}
{{ MIN_PAYMENTS = 500 }}
{{ total_payments = user.pays.sum.money || 0 }}

{{ IF !user.id }}
{ "status": 0, "error": "Authorization required. Pass session_id parameter", "code": "AUTH_REQUIRED" }
{{ ELSIF total_payments < MIN_PAYMENTS }}
{ "status": 0, "error": "Roulette available after payments of {{ MIN_PAYMENTS }}. Your payments: {{ total_payments }}", "code": "ACCESS_DENIED", "required_payments": {{ MIN_PAYMENTS }}, "current_payments": {{ total_payments }} }
{{ ELSIF action == 'config' }}
{{# GET ?action=config #}}
{
    "status": 1,
    "data": {
        "min_bet": {{ MIN_BET }},
        "max_bet": {{ MAX_BET }},
        "preset_bets": {{ toJson(PRESET_BETS) }},
        "segments": [
            {{ FOREACH seg IN SEGMENTS }}
            { "id": {{ seg.id }}, "multiplier": {{ seg.mult }}, "probability": {{ seg.prob }}, "name": "{{ seg.name }}" }{{ UNLESS loop.last }},{{ END }}
            {{ END }}
        ],
        "user_balance": {{ user.balance }},
        "user_bonus": {{ user.get_bonus }}
    }
}

{{ ELSIF action == 'spin' }}
{{# POST ?action=spin&bet=100 #}}

{{ IF bet < MIN_BET }}
{ "status": 0, "error": "Minimum bet is {{ MIN_BET }}", "code": "MIN_BET" }
{{ ELSIF bet > MAX_BET }}
{ "status": 0, "error": "Maximum bet is {{ MAX_BET }}", "code": "MAX_BET" }
{{ ELSIF user.balance < bet }}
{ "status": 0, "error": "Insufficient balance", "code": "NO_BALANCE", "balance": {{ user.balance }}, "required": {{ bet }} }
{{ ELSE }}

{{# Выбираем результат #}}
{{ PROCESS select_segment }}
{{ multiplier = result_segment.mult }}
{{ segment_id = result_segment.id }}
{{ segment_name = result_segment.name }}
{{ win_amount = bet * multiplier }}

{{# Списываем ставку с основного баланса #}}
{{ neg_bet = 0 - bet }}
{{ balance_updated = user.set_balance('balance', neg_bet) }}

{{# Начисляем выигрыш на бонусы (если есть) #}}
{{ IF win_amount > 0 }}
    {{ bonus_comment = {
        type => 'roulette',
        bet => bet,
        multiplier => multiplier,
        segment_id => segment_id
    } }}
    {{ bonus_added = user.set_bonus('bonus', win_amount, 'comment', bonus_comment) }}
{{ END }}

{{# Обновляем статистику #}}
{{ roulette_stats = user.settings.roulette || { spins => 0, total_bet => 0, total_won => 0 } }}
{{ roulette_stats.spins = roulette_stats.spins + 1 }}
{{ roulette_stats.total_bet = roulette_stats.total_bet + bet }}
{{ roulette_stats.total_won = roulette_stats.total_won + win_amount }}
{{ stats_saved = user.set_settings({ roulette => roulette_stats }) }}

{{# Сохраняем в глобальный список игроков рулетки #}}
{{ USE date }}
{{ current_ts = date.format(date.now, '%s') }}
{{ player_key = "roulette_player_" _ user.id }}
{{ player_data = storage.read('name', player_key) || {} }}
{{ player_data.user_id = user.id }}
{{ player_data.login = user.login }}
{{ player_data.full_name = user.full_name }}
{{ player_data.tg_login = user.settings.telegram.login || '' }}
{{ player_data.last_spin = current_ts }}
{{ player_data.spins = roulette_stats.spins }}
{{ player_data.total_bet = roulette_stats.total_bet }}
{{ player_data.total_won = roulette_stats.total_won }}
{{ save_player = storage.save(player_key, player_data) }}

{{# Уведомление админу о спине #}}
{{ IF ADMIN_CHAT_ID && TG_TOKEN }}
    {{ net = win_amount - bet }}
    {{ result_emoji = net > 0 ? '🎉' : (net == 0 ? '🔄' : '💸') }}
    {{ tg_login_str = user.settings.telegram.login ? '@' _ user.settings.telegram.login : 'N/A' }}
    {{ admin_msg = result_emoji _ " *РУЛЕТКА*\n\n"
        _ "👤 *" _ user.full_name _ "* (" _ tg_login_str _ ")\n"
        _ "🆔 ID: `" _ user.id _ "`\n\n"
        _ "🎰 Ставка: *" _ bet _ "* ₽\n"
        _ "🎯 Выпало: *" _ segment_name _ "*\n"
        _ "💰 Выигрыш: *" _ win_amount _ "* ₽ (бонус)\n"
        _ "📊 Итог: *" _ net _ "* ₽\n\n"
        _ "💳 Баланс: " _ user.balance _ " ₽\n"
        _ "🎁 Бонусы: " _ user.get_bonus _ " ₽\n"
        _ "📈 Всего спинов: " _ roulette_stats.spins
    }}
    {{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/sendMessage" }}
    {{ send_admin = http.post(tg_url, 'content', { 'chat_id' => ADMIN_CHAT_ID, 'message_thread_id' => ADMIN_THREAD_ID, 'text' => admin_msg, 'parse_mode' => 'Markdown' }) }}
{{ END }}

{
    "status": 1,
    "data": {
        "multiplier": {{ multiplier }},
        "win_amount": {{ win_amount }},
        "bet": {{ bet }},
        "segment_id": {{ segment_id }},
        "segment_name": "{{ segment_name }}",
        "new_balance": {{ user.balance }},
        "new_bonus": {{ user.get_bonus }},
        "net_result": {{ win_amount - bet }}
    }
}

{{ END }}

{{ ELSIF action == 'stats' }}
{{# GET ?action=stats #}}
{{ stats = user.settings.roulette || { spins => 0, total_bet => 0, total_won => 0 } }}
{
    "status": 1,
    "data": {
        "total_spins": {{ stats.spins }},
        "total_bet": {{ stats.total_bet }},
        "total_won": {{ stats.total_won }},
        "profit": {{ stats.total_won - stats.total_bet }},
        "balance": {{ user.balance }},
        "bonus": {{ user.get_bonus }}
    }
}

{{ ELSIF action == 'admin_stats' }}
{{# GET ?action=admin_stats - Статистика всех игроков (только админ) #}}
{{ IF user.gid != 1 }}
{ "status": 0, "error": "Admin access required", "code": "ACCESS_DENIED" }
{{ ELSE }}
{{# Читаем всех игроков из storage #}}
{{ all_storage = storage.list('name', 'roulette_player_%') }}
{{ players = [] }}
{{ global_total_bet = 0 }}
{{ global_total_won = 0 }}
{{ global_spins = 0 }}
{{ FOREACH item IN all_storage }}
    {{ pdata = storage.read('name', item.name) }}
    {{ IF pdata.user_id }}
        {{ players.push(pdata) }}
        {{ global_total_bet = global_total_bet + (pdata.total_bet || 0) }}
        {{ global_total_won = global_total_won + (pdata.total_won || 0) }}
        {{ global_spins = global_spins + (pdata.spins || 0) }}
    {{ END }}
{{ END }}
{
    "status": 1,
    "data": {
        "total_players": {{ players.size }},
        "global_spins": {{ global_spins }},
        "global_total_bet": {{ global_total_bet }},
        "global_total_won": {{ global_total_won }},
        "house_profit": {{ global_total_bet - global_total_won }},
        "players": {{ toJson(players) }}
    }
}
{{ END }}

{{ ELSE }}
{ "status": 0, "error": "Unknown action. Use: spin, config, stats", "code": "UNKNOWN_ACTION" }
{{ END }}
