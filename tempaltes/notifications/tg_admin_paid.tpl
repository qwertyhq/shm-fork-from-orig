⭐️ User login: @{{ user.settings.telegram.login }}
⭐️ User ID: {{ user.id }}
⭐️ User name: {{ user.full_name }}
{{ IF event_name == "PAYMENT" }}
💰 оплатил: {{ user.pays.last.money }} ₽
{{ END }}