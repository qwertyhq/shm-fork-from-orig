{{ TEXT = BLOCK }}
📡 <b>MTProto Proxy теперь доступен для всех!</b>

Привет, <b>{{ user.full_name }}</b>! 👋

Мы запустили бесплатный прокси для Telegram — теперь мессенджер работает даже при блокировках, <b>без VPN</b>.

⚡ <b>Преимущества:</b>
• Не нужно устанавливать приложения
• Работает прямо внутри Telegram
• Стабильное и быстрое соединение
• Полностью бесплатно

👇 Нажмите кнопку ниже, чтобы подключить прокси в один клик!

Поддержка: <b>@hq_vpn_support_bot</b>
{{ END }}
{{ ret = user.telegram.profile('telegram_bot').send( 
    sendMessage = {
        text = TEXT
        protect_content = "true"
        parse_mode = "HTML"
        reply_markup = {
        inline_keyboard = [
          [
            {
              text = "⚡ Подключить прокси",
              url = "https://t.me/proxy?server=83.147.255.123&port=8443&secret=40981504b6a78b10aaa3cc5e12daef83"
            }
          ],
          [
            {
              text = "🔥 WEB-кабинет",
              url = "https://t.me/hq_vpn_bot/web"
            }
          ],
          [
            {
              text = "🏠 В меню",
              callback_data = "/start"
            }
          ]
        ]
        }
    }
) 
}}
