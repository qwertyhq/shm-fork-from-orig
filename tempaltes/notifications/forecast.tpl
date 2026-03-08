{{ lang = user.settings.lang || 'ru' }}
{{ names_en = { '12' => 'VPN 1 Month', '15' => 'VPN 2 Months', '16' => 'VPN 3 Months', '17' => 'VPN 6 Months', '18' => 'VPN 12 Months', '21' => 'Free Trial - 7 Days', '28' => 'Family 1 Month', '29' => 'Family 12 Months', '30' => 'Traffic Reset' } }}
{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>! 👋\n\n⚠️ Your subscription is about to expire.\nPlease don't forget to renew!\n\n{{ FOR item IN user.pays.forecast.items }}🔑 Key #{{ item.usi }} — <b>{{ names_en.item(item.service_id) || item.name }}</b>\n├ Cost: {{ item.total }}₽\n└ Expires: {{ item.expire }}\n\n{{ END }}🎁 Bonus balance: {{ user.get_bonus }}₽\n💳 <b>Total due: {{ user.pays.forecast.total }}₽</b>\n\n💡 Top up your balance to avoid service interruption.{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>! 👋\n\n⚠️ Период действия вашей подписки подходит к концу.\nНе забудьте продлить!\n\n{{ FOR item IN user.pays.forecast.items }}🔑 Ключ №{{ item.usi }} — <b>{{ item.name }}</b>\n├ Стоимость: {{ item.total }}₽\n└ Истекает: {{ item.expire }}\n\n{{ END }}🎁 Бонусный счёт: {{ user.get_bonus }}₽\n💳 <b>Итог к оплате: {{ user.pays.forecast.total }}₽</b>\n\n💡 Пополните баланс, чтобы избежать перебоев в работе.{{ END }}",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "{{ lang == 'en' ? '💰 Top up balance' : '💰 Пополнить баланс' }}",
                    "url": "https://t.me/hq_vpn_bot/web",
                    "style": "primary"
                }
            ],
            [
                {
                    "text": "{{ lang == 'en' ? '🌐 Main menu' : '🌐 Главное меню' }}",
                    "callback_data": "/menu"
                }
            ]
        ]
    }
}
