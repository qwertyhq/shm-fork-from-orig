{{ TEXT = BLOCK }}
{{ IF event_name == "REGISTERED" }}
🆕 <b>Новый пользователь</b>

👤 @{{ user.settings.telegram.login }}
📛 {{ user.full_name }}
🆔 US_ID: #uid_{{ user.id }} | TG_ID: #id_{{ user.settings.telegram.chat_id }}
{{ IF user.partner_id > 0 }}

🤝 <b>Реферал от:</b>
➡️ @{{ user.id(user.partner_id).settings.telegram.login }}
➡️ {{ user.id(user.partner_id).full_name }}
➡️ US_ID: #uid_{{ user.partner_id }} | TG_ID: #id_{{ user.id(user.partner_id).settings.telegram.chat_id }}
{{ END }}
{{ END }}
{{ IF event_name == "CREATE" }}
🆕 <b>Создана услуга</b>

📦 {{ us.name }} (USI: #HQVPN_{{ us.id }})
📅 Создана: {{ us.created }}
📅 Действует до: {{ us.expire }}
💰 Баланс: {{ user.balance }} ₽
{{ IF user.partner_id > 0 }}

🤝 <b>Реферал от:</b> #uid_{{ user.partner_id }}
➡️ @{{ user.id(user.partner_id).settings.telegram.login }}
➡️ {{ user.id(user.partner_id).full_name }}
{{ END }}
{{ END }}
{{ IF event_name == "ACTIVATE" }}
✅ <b>Активирована услуга</b>

📦 {{ us.name }} (USI: #HQVPN_{{ us.id }})
📅 Действует до: {{ us.expire }}
💰 Баланс: {{ user.balance }} ₽
{{ END }}
{{ IF event_name == "PAYMENT" && pay.money > 0 }}
💰 <b>Оплата получена</b>

💵 Сумма: {{ user.pays.last.money }} ₽
📦 Тариф: {{ us.name }}
💰 Баланс после: {{ user.balance }} ₽
{{ END }}
{{ IF event_name == "BLOCK" }}
⛔️ <b>Ключ заблокирован</b>

📦 {{ us.name }} (USI: #HQVPN_{{ us.id }})
💰 Баланс: {{ user.balance }} ₽
{{ END }}
{{ IF event_name == "REMOVE" }}
❌ <b>Ключ удалён</b>

📦 {{ us.name }} (USI: #HQVPN_{{ us.id }})
💰 Баланс: {{ user.balance }} ₽
{{ END }}
{{ IF event_name == "PROLONGATE" }}
🔄 <b>Ключ продлён</b>

📦 {{ us.name }} (USI: #HQVPN_{{ us.id }})
📅 Новый срок до: {{ us.expire }}
💰 Баланс: {{ user.balance }} ₽
{{ END }}
{{ IF event_name == "BONUS" }}
🎁 <b>Начислен бонус</b>

💵 Сумма: {{ bonus.amount }} ₽
💰 Баланс: {{ user.balance }} ₽
{{ END }}
{{ IF event_name != "REGISTERED" }}

👤 @{{ user.settings.telegram.login }} | {{ user.full_name }}
🆔 US_ID: #uid_{{ user.id }} | TG_ID: #id_{{ user.settings.telegram.chat_id }}
{{ END }}
{{ END }}
{{
  toJson({
    text = TEXT
    parse_mode = 'HTML'
    disable_web_page_preview = 'True'
    chat_id = -1001965226181
    message_thread_id = 28953
  })
}}