{{ lang = user.settings.lang || 'ru' }}
{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>! 👋\n\n✅ Payment received: <b>{{ user.pays.last.money }} ₽</b>\n\n💳 Balance: <b>{{ user.balance }} RUB</b>\n👥 Bonus balance: {{ user.get_bonus }} RUB\n\n💡 Your subscription will be renewed automatically.{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>! 👋\n\n✅ Зачислен платёж: <b>{{ user.pays.last.money }} ₽</b>\n\n💳 Баланс: <b>{{ user.balance }} ₽</b>\n👥 Бонусный счёт: {{ user.get_bonus }} ₽\n\n💡 Подписка будет продлена автоматически.{{ END }}",
"reply_markup":{"inline_keyboard":[
        [
                    {
                        "text": "{{ lang == 'en' ? '🌐 Main menu' : '🌐 Главное меню' }}",
                        "callback_data": "/menu",
                        "style": "success"
                    }
                ]
]}
}
