# Notification Templates Schema

## Email Notifications (Brevo HTTP API)
See memory `brevo_email_integration` for full details.
- 6 transactional templates in `tempaltes/email/brevo_*.tpl` (events 46-51)
- 1 system template `brevo_system_email.tpl` for verify_email/passwd_reset
- Server: server_id=20, gid=13, transport=http
- GROUP_ID_MAIL overridden to 13 via `prod-files/Const.pm` (Docker volume mount)

## Telegram Notifications

### Location
`tempaltes/notifications/` — 9 files, all Telegram JSON (sendMessage format)

## Templates Overview

### 1. `forecast.tpl` — Subscription Expiry Warning
- **Trigger**: Event `FORECAST` (subscription about to expire)
- **Content**: Lists expiring subscriptions with costs and dates
- **Variables**: `user.full_name`, `user.pays.forecast.items` (loop: usi, name, total, expire), `user.get_bonus`, `user.pays.forecast.total`
- **Buttons**: [💰 Пополнить баланс (web_app)] [🌐 Главное меню]
- **Issues**: ⚠️ `web_app.url` = `t.me/hq_vpn_bot/web` — INVALID! Must be `https://z-hq.com/?user_id=...`

### 2. `http_bonus.tpl` — Bonus Credited
- **Trigger**: Event bonus credited to user
- **Content**: "Вам начислен бонус 💰 {amount} Рублей"
- **Variables**: `bonus.amount`
- **Buttons**: [♻️ Обновить меню]

### 3. `http_del.tpl` — VPN Deleted
- **Trigger**: Service deletion event
- **Content**: "VPN удален ⛔️ {name}"
- **Variables**: `us.name`
- **Buttons**: [♻️ Обновить меню]

### 4. `http_no_money.tpl` — Insufficient Balance
- **Trigger**: Event `NOT_ENOUGH_MONEY`
- **Content**: Warning about insufficient balance to activate subscription
- **Variables**: none specific
- **Buttons**: [💰 Пополнить баланс (web_app)] [🌐 Главное меню]
- **Issues**: ⚠️ `web_app.url` = `t.me/hq_vpn_bot/web` — INVALID! Same bug. Also typo: "Здравствуете" → "Здравствуйте"

### 5. `http_user_pay.tpl` — Payment Received
- **Trigger**: User payment event
- **Content**: "Вам зачислен платеж 💰 {money} ₽"
- **Variables**: `user.pays.last.money`
- **Buttons**: [♻️ Обновить меню]

### 6. `http.tpl` — VPN Created Successfully
- **Trigger**: Service create event (HTTP transport callback)
- **Content**: "VPN успешно создан!" with setup instructions
- **Variables**: `us.name`
- **Buttons**: [📱 Настроить VPN (url: t.me/hq_vpn_bot/web)] [🔄 Обновить меню → /start]
- **Issues**: ⚠️ `url: "https://t.me/hq_vpn_bot/web"` — may cause BUTTON_URL_INVALID. Also broken emoji: `�` instead of 📱

### 7. `telegram_pay.tpl` — Key Unblocked After Payment
- **Trigger**: Payment processed, subscription activated
- **Content**: "Ваш ключ разблокирован" with next block date
- **Variables**: `us.expire`
- **Buttons**: [♻️ Обновить меню]

### 8. `tg_admin_paid.tpl` — Admin Payment Notification
- **Trigger**: User makes payment (admin notification)
- **Content**: User info + payment amount (plain text, no JSON wrapper)
- **Variables**: `user.settings.telegram.login`, `user.id`, `user.full_name`, `event_name`, `user.pays.last.money`
- **Format**: Plain text (NOT JSON sendMessage) — sent to admin chat
- **Note**: No bilingual needed (admin-only)

### 9. `tg_alert.tpl` — Key Blocked Alert
- **Trigger**: Service blocked (non-payment)
- **Content**: "Ваш ключ был заблокирован" with top-up prompt
- **Variables**: `us.service.name`
- **Buttons**: [♻️ Обновить меню]

## Common Pattern
All user-facing notifications use: `{{ user.settings.telegram.chat_id }}` for targeting.
Language setting available via: `{{ user.settings.lang }}` (ru/en).

## Critical Bugs Found
1. `forecast.tpl` and `http_no_money.tpl`: `web_app.url` = `t.me/hq_vpn_bot/web` — missing `https://` and wrong URL
2. `http.tpl`: `url` = `https://t.me/hq_vpn_bot/web` — t.me not allowed in url buttons
3. `http.tpl`: Broken emoji `�` (encoding issue)
4. `http_no_money.tpl`: Typo "Здравствуете" → "Здравствуйте"
5. No English language support in any notification
