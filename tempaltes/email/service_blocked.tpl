{{ lang = user.settings.lang || 'ru' }}{{ IF lang == 'en' }}Hello, {{ user.full_name }}.

Your VPN service "{{ us.name }}" has been suspended due to insufficient balance.

Your balance: {{ user.balance }} RUB

Top up your balance to restore access:
https://t.me/hq_vpn_bot/web

Best regards,
HQ VPN Team{{ ELSE }}Здравствуйте, {{ user.full_name }}.

Ваша VPN-услуга «{{ us.name }}» приостановлена из-за недостаточного баланса.

Ваш баланс: {{ user.balance }} ₽

Пополните баланс для восстановления доступа:
https://t.me/hq_vpn_bot/web

С уважением,
Команда HQ VPN{{ END }}
