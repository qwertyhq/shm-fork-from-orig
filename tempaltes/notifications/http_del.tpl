{{ lang = user.settings.lang || 'ru' }}
{"chat_id":{{ user.settings.telegram.chat_id }},
"parse_mode":"HTML",
"text":"{{ IF lang == 'en' }}⛔️ <b>Subscription deleted</b>\n\nService: <b>{{ us.name }}</b>\n\nIf you want to purchase a new subscription, open the app.{{ ELSE }}⛔️ <b>Подписка удалена</b>\n\nУслуга: <b>{{ us.name }}</b>\n\nЕсли хотите приобрести новую подписку — откройте приложение.{{ END }}",
"reply_markup":{"inline_keyboard":[
        [
                    {
                        "text": "{{ lang == 'en' ? '🚀 Open App' : '🚀 Открыть приложение' }}",
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
]}
}
