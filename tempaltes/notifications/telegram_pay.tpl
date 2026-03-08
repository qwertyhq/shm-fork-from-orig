{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "Здравствуйте

🚀 Ваш ключ разблокирован, можно смело подключаться! 🚀

🔑 Следующая дата <b>блокировки</b> Вашего ключа: {{ us.expire }} 🔑

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