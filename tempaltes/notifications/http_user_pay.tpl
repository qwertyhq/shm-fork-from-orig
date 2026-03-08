{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"Вам зачислен платеж💰 {{ user.pays.last.money }} ₽",
"reply_markup":{"inline_keyboard":[
        [
                    {
                        "text": "♻️ Обновить меню",
                        "callback_data": "/menu"
                    }
                ]
]}
}