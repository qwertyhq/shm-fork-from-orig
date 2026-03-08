{{ lang = user.settings.lang || 'ru' }}
{{ names_en = { '12' => 'VPN 1 Month', '15' => 'VPN 2 Months', '16' => 'VPN 3 Months', '17' => 'VPN 6 Months', '18' => 'VPN 12 Months', '21' => 'Free Trial - 7 Days', '28' => 'Family 1 Month', '29' => 'Family 12 Months', '30' => 'Traffic Reset' } }}
{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>! 👋\n\n🚀 <b>Your subscription has been activated!</b> 🚀\n\n🔑 Service: <b>{{ names_en.item(us.service_id) || us.name }}</b>\n📅 Active until: <b>{{ us.expire }}</b>\n💳 Balance: {{ user.balance }} RUB\n\n✅ You can connect now!{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>! 👋\n\n🚀 <b>Ваша подписка активирована!</b> 🚀\n\n🔑 Услуга: <b>{{ us.name }}</b>\n📅 Действует до: <b>{{ us.expire }}</b>\n💳 Баланс: {{ user.balance }} ₽\n\n✅ Можно смело подключаться!{{ END }}",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "{{ lang == 'en' ? '🌐 Main menu' : '🌐 Главное меню' }}",
                    "callback_data": "/menu",
                    "style": "success"
                }
            ]
        ]
    }
}
