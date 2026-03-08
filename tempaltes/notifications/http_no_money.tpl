{{ lang = user.settings.lang || 'ru' }}
{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>.\n\n⛔️ <b>Insufficient balance!</b> ⛔️\n\n💳 Your balance: <b>{{ user.balance }} RUB</b>\n👥 Bonus balance: {{ user.get_bonus }} RUB\n\n💰 Top up your balance to activate your subscription.{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>.\n\n⛔️ <b>Недостаточный баланс!</b> ⛔️\n\n💳 Ваш баланс: <b>{{ user.balance }} ₽</b>\n👥 Бонусный счёт: {{ user.get_bonus }} ₽\n\n💰 Пополните баланс, чтобы активировать подписку.{{ END }}",
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
