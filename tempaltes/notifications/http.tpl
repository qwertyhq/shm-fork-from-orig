{
    "chat_id": {{ user.settings.telegram.chat_id }},
    "parse_mode": "HTML",
    "text": "🎉 <b>VPN успешно создан!</b>\n\n👤 Услуга: <b>{{ us.name }}</b>\n\n⚠️ <b>Осталось настроить VPN</b>\n\nНажмите кнопку ниже, чтобы:\n• Скачать приложение\n• Подключить VPN\n• Начать пользоваться",
    "reply_markup": {
        "inline_keyboard": [
            [
                {
                    "text": "📲 Настроить VPN",
                    "url": "https://t.me/hq_vpn_bot/web"
                }
            ],
            [
                {
                    "text": "🔄 Обновить меню",
                    "callback_data": "/start"
                }
            ]
        ]
    }
}
