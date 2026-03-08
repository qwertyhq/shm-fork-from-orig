{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"Вам начислен бонус 💰 {{ bonus.amount }} Рублей",
"reply_markup":{"inline_keyboard":[
        [
                    {
                        "text": "♻️ Обновить меню",
                        "callback_data": "/menu"
                    }
                ]
]}
}