{{ lang = user.settings.lang || 'ru' }}{{ IF lang == 'en' }}Hello, {{ user.full_name }}!

Payment received: {{ user.pays.last.money }} RUB

Your balance: {{ user.balance }} RUB
Bonus balance: {{ user.get_bonus }} RUB

Your subscription will be renewed automatically.

Best regards,
HQ VPN Team{{ ELSE }}Здравствуйте, {{ user.full_name }}!

Зачислен платёж: {{ user.pays.last.money }} ₽

Ваш баланс: {{ user.balance }} ₽
Бонусный счёт: {{ user.get_bonus }} ₽

Подписка будет продлена автоматически.

С уважением,
Команда HQ VPN{{ END }}
