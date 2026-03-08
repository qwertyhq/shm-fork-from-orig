{{ lang = user.settings.lang || 'ru' }}
{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"{{ IF lang == 'en' }}Hello, <b>{{ user.full_name }}</b>! 👋\n\n🎁 You received a bonus: <b>{{ bonus.amount }} RUB</b>\n\n👥 Bonus balance: <b>{{ user.get_bonus }} RUB</b>\n💳 Main balance: {{ user.balance }} RUB\n\n💡 Bonuses are applied automatically when renewing your subscription.{{ ELSE }}Здравствуйте, <b>{{ user.full_name }}</b>! 👋\n\n🎁 Вам начислен бонус: <b>{{ bonus.amount }} ₽</b>\n\n👥 Бонусный счёт: <b>{{ user.get_bonus }} ₽</b>\n💳 Основной баланс: {{ user.balance }} ₽\n\n💡 Бонусы списываются автоматически при продлении подписки.{{ END }}",
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
