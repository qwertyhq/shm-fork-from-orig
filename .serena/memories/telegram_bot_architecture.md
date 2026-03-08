# Telegram Bot Architecture (HQ VPN)

## Overview
- Bot: @hq_vpn_bot — VPN subscription management bot
- Template: `tempaltes/tg_bot_main.tpl` (~1500 lines, single SWITCH block)
- Engine: Template::Toolkit (TT2) via Core::Template::parse()
- Transport: Core::Transport::Telegram → process_message() → exec_template()

## Request Flow
```
Telegram webhook → v1.cgi → Core::Transport::Telegram::process_message()
  → Verify IP + secret → auth user via chat_id → parse cmd + args
  → exec_template(cmd => $cmd) → Core::Template::parse()
  → TT2 SWITCH cmd → match CASE → generate JSON Telegram API actions
  → Send to Telegram API sequentially → Return 200 OK
```

## Two Interfaces
- **Web** (`user.settings.interface == 'web'`): Minimal bot menu, redirects to https://z-hq.com/?user_id={id}
- **Bot** (default): Full feature menu with inline keyboards
- Switchable via `/show_interface_menu` → `/change_interface bot|web`

## Command Tree

### Registration Flow
USER_NOT_FOUND → /register → /set_interface_and_go → /go → rules check
  → /accept_rules → /trial_order (creates trial sub)
  → /decline_rules → delete user

### Main Navigation
/start, /menu, /deleted_us → Shows balance, bonus, active subs with status icons
  → Buttons: [Продлить], [Настроить VPN], [Пополнить баланс], [Реферальная программа], [Доп. меню]

### Subscription Management
/list → all subs | /service {usi} → details
/prolongate {usi} → tariff picker | /prolongate_confirm {usi} {sid} → apply
/delete {usi} → confirm | /delete_confirmed {usi} → execute
/active_service → read-only details

### Purchase Flow
/vless → VLESS tariffs | /serviceorder {sid} → shmServiceOrder
  → If balance < cost → payment UI (tg_payments.tpl as WebApp)
  → Else → charge from balance → CREATE event → remnawave.tpl → VPN provisioning

### Billing & Referrals
/referals → link + stats + promo code | /money_out → withdrawal request

### Support & Info
/menu_2 → secondary menu | /help → support links
/faq → topic list | /vpn_connect, /vpn_routing, /vpn_limits, /subs_renewal
/rules → terms | /about → company info | /status → all OK
/cancel → user cancellation

### Admin Forwarding
Default (unmatched) → forward to admin chat with #chat_id# marker
Admin reply → find #chat_id# → forward back to user

## VPN Provisioning (remnawave.tpl)
1. CREATE event fires → spool.pl → remnawave.tpl
2. Call Remnawave API `/api/users` → get UUID
3. Retrieve subscription URL from `/api/sub/{shortUuid}`
4. Save to storage: key=`vpn_mrzb_{usi}`, value={subscriptionUrl, configs, uuid}
5. Status → ACTIVE

## Storage Pattern
`storage.read('name', 'vpn_mrzb_' _ usi).response.subscriptionUrl`
→ Returns Remnawave subscription URL for VPN configuration page

## Balance Components
- `user.balance` — primary account (RUB)
- `user.get_bonus` — referral earnings
- `user.discount` — personal discount %
- Effective cost = cost * (1 - discount/100)
- Total available = balance + bonus

## Key Templates
- tg_bot_main.tpl — main bot logic
- tg_payments.tpl — payment WebApp
- remnawave.tpl — VPN provisioning
- traffic_reset.tpl — monthly traffic reset
- telegram_bot_web_app.tpl — webapp auth

## Known Issues
1. Race condition on balance check (no pessimistic locking)
2. Callback data no URL encoding (spaces break parsing)
3. Monolithic template (1500 lines in one SWITCH)
4. Admin forwarding fragile (#chat_id# manual parsing)
5. No usage/traffic stats in bot interface
6. No payment history command
