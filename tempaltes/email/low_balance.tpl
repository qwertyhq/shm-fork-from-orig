{{ lang = user.settings.lang || 'ru' }}{{ IF lang == 'en' }}Hello, {{ user.full_name }}.

Insufficient balance! Your VPN service may be suspended.

Your balance: {{ user.balance }} RUB
Bonus balance: {{ user.get_bonus }} RUB

Please top up your balance to keep your subscription active:
https://t.me/hq_vpn_bot/web

Best regards,
HQ VPN Team{{ ELSE }}Здравствуйте, {{ user.full_name }}.

Недостаточно средств! Ваша VPN-услуга может быть приостановлена.

Ваш баланс: {{ user.balance }} ₽
Бонусный счёт: {{ user.get_bonus }} ₽

Пожалуйста, пополните баланс, чтобы подписка оставалась активной:
https://t.me/hq_vpn_bot/web

С уважением,
Команда HQ VPN{{ END }}
