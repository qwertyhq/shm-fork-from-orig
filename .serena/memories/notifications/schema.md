# Notification Templates Schema

## Location: `tempaltes/notifications/`

## Templates Overview

### 1. `http.tpl` — VPN Created (EVENT_CREATE)
- **Trigger**: After VPN service is created
- **Transport**: Telegram (sendMessage to chat_id)
- **Content**: "VPN успешно создан!" + service name + setup instructions
- **Buttons**: [📲 Настроить VPN (url: t.me/hq_vpn_bot/web)] [🔄 Обновить меню (/start)]
- **Issues**: 
  - URL `t.me/hq_vpn_bot/web` used as regular `url` — should be `web_app` with `z-hq.com`
  - Russian only, no bilingual support
  - Uses "url" for web app link (should use web_app with real URL)

### 2. `http_bonus.tpl` — Bonus Credited
- **Trigger**: When bonus is credited to user (referral payments)
- **Transport**: Telegram
- **Content**: "Вам начислен бонус 💰 {amount} Рублей"
- **Buttons**: [♻️ Обновить меню (/menu)]
- **Issues**: Russian only, minimal info

### 3. `http_del.tpl` — VPN Deleted (EVENT_REMOVE)
- **Trigger**: When VPN service is deleted
- **Transport**: Telegram
- **Content**: "VPN удален ⛔️ {name}"
- **Buttons**: [♻️ Обновить меню (/menu)]
- **Issues**: Russian only, very terse

### 4. `http_no_money.tpl` — Insufficient Balance (EVENT_NOT_ENOUGH_MONEY)
- **Trigger**: When user doesn't have enough money
- **Transport**: Telegram
- **Content**: "Недостаточный баланс!" + prompt to top up
- **Buttons**: [💰 Пополнить баланс (web_app: t.me/hq_vpn_bot/web)] [🌐 Главное меню (/menu)]
- **Issues**: 
  - `web_app.url` = `t.me/hq_vpn_bot/web` — INVALID! Must use `z-hq.com/?user_id=...`
  - Typo: "Здравствуете" (should be "Здравствуйте")
  - Russian only

### 5. `http_user_pay.tpl` — Payment Received
- **Trigger**: When user payment is processed
- **Transport**: Telegram
- **Content**: "Вам зачислен платеж💰 {amount} ₽"
- **Buttons**: [♻️ Обновить меню (/menu)]
- **Issues**: Russian only, minimal info

### 6. `forecast.tpl` — Subscription Expiry Forecast
- **Trigger**: When subscription is about to expire
- **Transport**: Telegram
- **Content**: Warning with service list, costs, expiry dates, bonus balance, total amount
- **Buttons**: [💰 Пополнить баланс (web_app: t.me/hq_vpn_bot/web)] [🌐 Главное меню (/menu)]
- **Issues**: 
  - `web_app.url` = `t.me/hq_vpn_bot/web` — INVALID!
  - Russian only

### 7. `telegram_pay.tpl` — Key Unblocked (EVENT_ACTIVATE/PROLONGATE)
- **Trigger**: After payment activates/unblocks the key
- **Transport**: Telegram
- **Content**: "Ваш ключ разблокирован" + next block date
- **Buttons**: [♻️ Обновить меню (/menu)]
- **Issues**: Russian only

### 8. `tg_admin_paid.tpl` — Admin Payment Notification
- **Trigger**: When user makes a payment (admin-facing)
- **Transport**: Telegram (to admin)
- **Content**: User login, ID, name, payment amount
- **Issues**: Admin-only, no bilingual needed. Plain text (not JSON).

### 9. `tg_alert.tpl` — Key Blocked (EVENT_BLOCK)
- **Trigger**: When key is blocked due to non-payment
- **Transport**: Telegram
- **Content**: "Ваш ключ был заблокирован" + prompt to top up
- **Buttons**: [♻️ Обновить меню (/menu)]
- **Issues**: Russian only, no direct pay button

## Critical Bugs Found
1. **BUTTON_URL_INVALID**: `http_no_money.tpl` and `forecast.tpl` use `web_app.url = "t.me/hq_vpn_bot/web"` — missing `https://` AND should use `z-hq.com/?user_id={{ user.id }}`
2. **Typo**: `http_no_money.tpl` — "Здравствуете" → "Здравствуйте"
3. **Invalid URL**: `http.tpl` — `url: "https://t.me/hq_vpn_bot/web"` in regular url button — Telegram rejects t.me in url buttons

## Event → Template Mapping
| Event | Template | Description |
|-------|----------|-------------|
| CREATE | http.tpl | VPN service created |
| BLOCK | tg_alert.tpl | Key blocked |
| ACTIVATE/PROLONGATE | telegram_pay.tpl | Key unblocked |
| REMOVE | http_del.tpl | Service deleted |
| NOT_ENOUGH_MONEY | http_no_money.tpl | Low balance |
| PAYMENT | http_user_pay.tpl + tg_admin_paid.tpl (admin) | Payment received |
| Bonus credited | http_bonus.tpl | Referral bonus |
| Expiry forecast | forecast.tpl | Subscription expiring soon |
