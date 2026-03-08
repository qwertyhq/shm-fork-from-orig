{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"Здравствуйте, {{ user.full_name }}!
⚠️ Период действия вашего ключа подходит к концу.
⚠️ Не забудьте оплатить ключ!

{{ FOR item IN user.pays.forecast.items }}
- Ключ №{{ item.usi }} - {{ item.name }}
- Стоимость: {{ item.total }}₽
- Истекает: {{ item.expire }}

{{ END }}
🎁 Бонусный счет: {{ user.get_bonus }}₽
💳 Итог к оплате: {{ user.pays.forecast.total }}₽",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "💰 Пополнить баланс",
                    "web_app": {
                        "url": "t.me/hq_vpn_bot/web"
                    }
                }
            ],
            [
                {
                    "text": "🌐 Главное меню",
                    "callback_data": "/menu"
                }
            ]
        ]
    }
}