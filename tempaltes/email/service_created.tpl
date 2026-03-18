{{ lang = user.settings.lang || 'ru' }}{{ IF lang == 'en' }}Hello, {{ user.full_name }}!

Your VPN service "{{ us.name }}" has been created.

Please open HQ VPN app to set up your connection:
https://t.me/hq_vpn_bot/web

If you have any questions, contact support:
@hq_vpn_support_bot

Best regards,
HQ VPN Team{{ ELSE }}Здравствуйте, {{ user.full_name }}!

Ваша VPN-услуга «{{ us.name }}» успешно создана.

Откройте приложение HQ VPN для настройки подключения:
https://t.me/hq_vpn_bot/web

Если у вас есть вопросы — обращайтесь в поддержку:
@hq_vpn_support_bot

С уважением,
Команда HQ VPN{{ END }}
