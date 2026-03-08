{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "Здравствуйте

⛔️ Ваш ключ был заблокирован: {{ us.service.name }} ⛔️

💰 Чтобы разблокировать ключ, пополните баланс. 💰
",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "♻️ Обновить меню",
                    "callback_data": "/menu"
                }
            ]
        ]
    }
}