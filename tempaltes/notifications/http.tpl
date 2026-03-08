{{ lang = user.settings.lang || 'ru' }}
{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "{{ IF lang == 'en' }}🎉 <b>VPN successfully created!</b>\n\n👤 Service: <b>{{ us.name }}</b>\n\n⚠️ <b>VPN setup required</b>\n\nPress the button below to:\n• Download the app\n• Connect VPN\n• Start using{{ ELSE }}🎉 <b>VPN успешно создан!</b>\n\n👤 Услуга: <b>{{ us.name }}</b>\n\n⚠️ <b>Осталось настроить VPN</b>\n\nНажмите кнопку ниже, чтобы:\n• Скачать приложение\n• Подключить VPN\n• Начать пользоваться{{ END }}",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "{{ lang == 'en' ? '📱 Setup VPN' : '📱 Настроить VPN' }}",
                    "url": "https://t.me/hq_vpn_bot/web",
                    "style": "success"
                }
            ],
            [
                {
                    "text": "{{ lang == 'en' ? '🌐 Main menu' : '🌐 Главное меню' }}",
                    "callback_data": "/start"
                }
            ]
        ]
    }
}
