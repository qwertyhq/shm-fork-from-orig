{{ lang = user.settings.lang || 'ru' }}{{ IF lang == 'en' }}Hello, {{ user.full_name }}!

Your VPN service "{{ us.name }}" has been renewed until {{ us.expire }}.

Your balance: {{ user.balance }} RUB

Best regards,
HQ VPN Team{{ ELSE }}Здравствуйте, {{ user.full_name }}!

Ваша VPN-услуга «{{ us.name }}» продлена до {{ us.expire }}.

Ваш баланс: {{ user.balance }} ₽

С уважением,
Команда HQ VPN{{ END }}
