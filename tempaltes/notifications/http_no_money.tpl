{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "Здравствуете.

⛔️ У вас недостаточный баланс! ⛔️ 

💰 Чтобы активировать подписку, просто пополните баланс. 💰",
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