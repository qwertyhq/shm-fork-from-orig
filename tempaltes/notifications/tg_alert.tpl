{{ lang = user.settings.lang || 'ru' }}
{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>.\n\n⛔️ <b>Your subscription has been blocked</b>\n\nService: <b>{{ us.service.name }}</b>\n\n💳 Balance: <b>{{ user.balance }} RUB</b>\n👥 Bonus balance: {{ user.get_bonus }} RUB\n\n💰 Top up your balance to restore access.{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>.\n\n⛔️ <b>Ваша подписка была заблокирована</b>\n\nУслуга: <b>{{ us.service.name }}</b>\n\n💳 Баланс: <b>{{ user.balance }} ₽</b>\n👥 Бонусный счёт: {{ user.get_bonus }} ₽\n\n💰 Пополните баланс, чтобы восстановить доступ.{{ END }}",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "{{ lang == 'en' ? '💰 Top up balance' : '💰 Пополнить баланс' }}",
                    "url": "https://t.me/hq_vpn_bot/web",
                    "style": "danger"
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
