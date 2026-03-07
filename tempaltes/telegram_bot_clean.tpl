{{ BLOCK send }}
{
    "sendMessage": {
        "parse_mode": "HTML",
        "text": "{{ text.replace('\n','\n') }}",
        "reply_markup": {
            "inline_keyboard": [
                {{ buttons }}
            ]
        }
    }
}
{{ END }}
{{ BLOCK edit }}
{
    "editMessageText": {
        "message_id": {{ message.message_id }},
        "parse_mode": "HTML",
        "text": "{{ text.replace('\n','\n') }}",
        "reply_markup": {
            "inline_keyboard": [
                {{ buttons }}
            ]
        }
    }
}
{{ END }}
<% SWITCH cmd %>
<% CASE 'USER_NOT_FOUND' %>
{{ TEXT = BLOCK }}
Добро пожаловать в бот сети VPN сервис gBox! 


Если вы согласны продолжить, пожалуйста нажмите кнопку <b>Начать</b>
{{ END }}
{
    "sendMessage": {
        "text": "{{TEXT.replace('\n','\n')}}",
        "parse_mode": "HTML",
        "reply_markup" : {
            "inline_keyboard": [
                [
                    {
                        "text": "Начать",
                        "callback_data": "/register {{ args.0 }}"
                    }
                ]
            ]
        }
    }
}
<% CASE '/register' %>
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "shmRegister": {
        "partner_id": "{{ args.0 }}",
        "callback_data": "/go",
        "error": "ОШИБКА: Логин {{ message.chat.username }} или chat_id {{ message.chat.id }} уже существует"
    }
}

<% CASE '/go' %>
{{ canceled = user.set_settings({ 'cancel' => '0' }) }}
{{ IF user.settings.rules_accepted == '1' }}
{
    "shmRedirectCallback": {
        "callback_data": "/trial_order"
    }
}
{{ ELSE }}
{{ TEXT = BLOCK }}
Для начала работы с сервисом вам необходимо принять наши правила использования:

📜 Правила сервиса:

1️⃣ Запрещено использовать VPN для действий, нарушающих законы Российской Федерации.

2️⃣ Запрещено использовать VPN для посещения сайтов, связанных с распространением, продажей запрещённых товаров, услуг или материалов (наркотические средства, детская порнография и т. д.).

3️⃣ Запрещено использовать VPN для распространения или продажи запрещённых товаров, услуг или материалов (наркотические средства, детская порнография и т. д.) либо лицензионной продукции без согласования с правообладателем.

4️⃣ Запрещено использовать VPN для загрузки торрентов. Аккаунт будет аннулирован за подобную деятельность.

5️⃣ <b>Пользовательское соглашение и Политика конфиденциальности:</b>


⚠️ В случае нарушения правил доступ к сервису будет ограничен без возможности возмещения оплаты. В случае нарушения закона информация о нарушителе будет зафиксирована и передана в правоохранительные органы.
{{ END }}
{
    "sendMessage": {
        "text": "{{TEXT.replace('\n','\n')}}",
        "parse_mode": "HTML",
        "reply_markup" : {
            "inline_keyboard": [
                [
                    {
                        "text": "Принимаю",
                        "callback_data": "/accept_rules"
                    }
                ],
                [
                    {
                        "text": "Отказываюсь",
                        "callback_data": "/decline_rules"
                    }
                ]
            ]
        }
    }
}
{{ END }}

<% CASE '/accept_rules' %>
{{ rules_accepted = user.set_settings({ 'rules_accepted' => '1' }) }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "shmRedirectCallback": {
        "callback_data": "/trial_order"
    }
}

<% CASE '/decline_rules' %>
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text": "Нам с вами не по пути.\n\nДо свидания."
    }
},
{
    "shmUserDelete": {}
}

<% CASE '/trial_order' %>
{{ IF user.settings.trial != 1 }}
{{ settrial = user.set_settings({ 'trial' => '1' }) }}
{{ create = 
  service.create_for_api(
    service_id = tpl.settings.trial_service_id
    check_allow_to_order = 0
  )
}}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "shmRedirectCallback": {
        "callback_data": "/menu"
    }
}
{{ ELSE }}
{
    "shmRedirectCallback": {
        "callback_data": "/menu"
    }
}
{{ END }}

<% CASE '/cancel' %>
{{ canceled = user.set_settings({ 'cancel' => '1' }) }}
{
    "sendMessage": {
        "text": "Нам с вами не по пути.\n\nДо свидания."
    }
},
{
    "shmUserDelete": {}
}
<% CASE ['/menu', '/start', '/deleted_us'] %>
{{ arr = ref( user.services.list_for_api( 'category', 'mz-%' ) ) }}
{{ IF user.settings.cancel == '1' }}
{{ TEXT = BLOCK }}
Вы отказались принимать правила, может быть вы все таки хотите их принять?
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "Посмотреть правила",
                        "callback_data": "/go"
                    }
                ]
{{ END }}
{{ PROCESS send text=TEXT buttons=buttons}}
{{ ELSE }}

{{ first = BLOCK }}
Рады приветствовать вас в нашем сервисе!

Это сообщение призвано ознакомить вас с основными разделами бота (оно будет активно только 24 часа):

1️⃣ <b>Для приобретения, продления или смены тарифа подписки</b> на вашем балансе должна быть сумма, равная стоимости подписки на выбранный период.

👥 Обязательно ознакомьтесь с нашей <b>реферальной программой</b> — благодаря ей вы сможете пользоваться VPN практически бесплатно (если привлечёте достаточно друзей). За каждую оплату, сделанную вашим другом, вы будете получать 20% на свой бонусный счёт.

📩 Если вам потребуется поддержка, вы сможете написать нам в бота.

💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
{{ END }}
{{ USER_TEXT = BLOCK }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
👥 <b>Ваша реферальная ссылка: <u>\nhttps://t.me/gboxvpn_bot?start={{ user.id }}</u></b>
{{ END }}
{{ TEXT = BLOCK }}
    {{ IF cmd == '/deleted_us' }}
    ❌ <b>Ваша подписка <u>{{ us.service.name }}</u> была удалена из-за неуплаты (либо по вашему желанию).</b>❌

    💡 <b>Если вы хотите продолжить использование нашего сервиса, пожалуйста оформите новую подписку.</b>

    Если у вас возникли вопросы, мы всегда готовы помочь.
    {{ ELSE }}
        {{ USE date }}
        {{ date_now = date.now }}
        {{ sec_created = date.format(user.created, '%s') }}
        {{ days_left = (date_now - sec_created) div 86400 }}

        {{ IF days_left <= 1 }}
            {{ first }}
        {{ ELSE }}
            {{ IF arr.size == 1 }}
Снова здравствуйте, {{ user.full_name }}!
{{ USER_TEXT }}

🔒Ваша активная подписка:

            {{ FOR item IN arr }}
                {{ SWITCH item.status }}
                    {{ CASE 'ACTIVE' }}
                    {{ icon = '🟢' }}
                    {{ status = 'Активна' }}
                    {{ CASE 'BLOCK' }}
                    {{ icon = '🔴' }}
                    {{ status = 'Заблокирована' }}
                    {{ CASE 'NOT PAID' }}
                    {{ icon = '💵' }}
                    {{ status = 'Не оплачено' }}
                    {{ CASE }}
                    {{ icon = '⏳' }}
                    {{ status = 'Обработка, обновите страницу' }}
                {{ END }}
Тариф: {{ item.name }}
Статус: {{ icon }} {{ status }}
Срок окончания: {{ item.expire }}
            {{ END }}
            {{ ELSIF arr.size > 1 || arr.size < 3 }}

Снова здравствуйте, {{ user.full_name }}!

{{ USER_TEXT }}

🔒Ваши активные подписки:
            {{ ELSE }}
{{ USER_TEXT }}

⚠️ <b>У Вас еще нет активных подписок.</b>

💳 Для покупки подписки у вас должен быть положительный баланс на счету.
            {{ END }}
        {{ END }}
    {{ END }}
{{ END }}
{{ IF cmd == '/start' }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text":"{{ TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
{{ END }}
{{ IF cmd == '/deleted_us' }}
{
    "sendMessage": {
        "text":"{{ TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
{{ END }}
{{ IF cmd == '/menu' }}
{
    "editMessageText": {
        "message_id": {{ message.message_id }},
        "text":"{{ TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
{{ END }}
        "reply_markup" : {
            "inline_keyboard": [
            {{ IF arr.size != 0 }}
                {{ IF arr.size >= 3 }}
                    [
                        {
                            "text": "Список моих подписок",
                            "callback_data": "/list"
                        }
                    ],
                {{ ELSIF arr.size == 2 }}
                    {{ FOR item IN ref( user.services.list_for_api( 'category', 'mz-%' ) ) }}
                        {{ SWITCH item.status }}
                            {{ CASE 'ACTIVE' }}
                            {{ icon = '🟢' }}
                            {{ status = 'Активна' }}
                            {{ CASE 'BLOCK' }}
                            {{ icon = '🔴' }}
                            {{ status = 'Заблокирована' }}
                            {{ CASE 'NOT PAID' }}
                            {{ icon = '💵' }}
                            {{ status = 'Не оплачено' }}
                            {{ CASE }}
                            {{ icon = '⏳' }}
                            {{ status = 'Обработка' }}
                        {{ END }}
                    [
                        {
                            "text": "{{ item.name }} - {{ icon }} {{ status }}",
                            "callback_data": "/service {{ item.user_service_id }}"
                        }
                    ],
                    {{ END }}
                {{ ELSE }}
                [
                    {
                        "text": "Продлить подписку",
                        "callback_data": "/prolongate {{ arr.0.user_service_id }}"
                    }
                ],
                {{ IF arr.0.status == 'BLOCK' }}
                [
                    {
                        "text": "💳 Пополнить баланс",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/payment?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ ELSIF arr.0.status == 'ACTIVE' }}
    {{ storage_data = storage.read('name','vpn_mrzb_' _ arr.0.user_service_id ) }}
    {{ subscription_url = storage_data.response.subscriptionUrl || storage_data.subscription_url || storage_data.response.subscription_url || '' }}
    {{ IF subscription_url.grep('^https:').first }}
                    [
                        {
                            "text": "🔍Настроить VPN ",
                             "web_app": {
                                "url": "{{ subscription_url }}"
                            }
                        }
                    ],
    {{ ELSE }}
                    [
                        {
                            "text": "😢 Ошибка: подключение не найдено",
                            "callback_data": "/menu"
                        }
                    ],
    {{ END }}
                {{ END }}
                {{ END }}
                {{ IF arr.size > 2 }}
                [
                    {
                        "text": "💳 Пополнить баланс",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/payment?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ END }}
            {{ ELSE }}
                [
                    {
                        "text": "🔒 Купить подписку",
                        "callback_data": "/vless"
                    }
                ],
            {{ END }}
                [
                    {
                        "text": "♻️ Обновить страницу ",
                        "callback_data": "/menu"
                    }
                ],
                [
                    {
                        "text": "👥 Реферальная программа",
                        "callback_data": "/referals"
                    }
                ],
                [
                    {
                        "text": "📊 Дополнительное меню",
                        "callback_data": "/menu_2"
                    }
                ]
           ]
        }
    }
}
{{ END }}

<% CASE '/menu_2' %>
{{ TEXT = BLOCK}}
Пожалуйста выберите интересующий вас пункт меню.
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "🔒 Купить подписку",
                        "callback_data": "/vless"
                    }
                ],
                [
                    {
                        "text": "💬 Поддержка",
                        "callback_data": "/help"
                    },
                    {
                        "text": "❓ Q&A",
                        "callback_data": "/faq"
                    }
                ],
                [
                    {
                        "text": "📜 Правила",
                        "callback_data": "/rules"
                    },
                    {
                        "text": "О сервисе",
                        "callback_data": "/about"
                    }
                ],
                [
                    {
                        "text": "📢 ТГ-канал VPN сервис gBox",
                         "url": "https://t.me/gboxinfo"
                    }
                ],
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/prolongate' %>
{{ TEXT = BLOCK }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей

<b>Ваша текущая подписка:</b>
{{ u_service = user.services.list_for_api( 'usi', args.0 ) }}
Тариф: {{ u_service.name }}
Стоимость: {{ u_service.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }}
Статус: {{ u_service.status == 'ACTIVE' ? '🟢 Оплачено': '🔴 Заблокирован'}}
Срок окончания: {{ u_service.expire }}

📊 <b>Выберите новый тариф</b>, для продления
{{ END }}
{{ buttons = BLOCK }}
                {{ FOR item IN ref(service.api_price_list( 'category', 'mz-%' )).nsort('cost') }}
                    [
                        {
                            "text": "{{ item.name }} - {{ item.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }} ₽ {{ IF user.discount > 0 }} (-{{ user.discount }}%){{ END }}",
                            "callback_data": "/prolongate_confirm {{ args.0 _ ' ' _ item.service_id }}"
                        }
                    ],
                {{ END }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/prolongate_confirm' %>
{{ prolongate = us.id( args.0 ).set('next', args.1 ) }}
{{ new_service = service.list_for_api('service_id', args.1 ) }}
{{ money = user.get_bonus != 0 ? user.balance + user.get_bonus : user.balance }}
{{ discounted_cost = new_service.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }}
{{ TEXT = BLOCK }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей

    {{ IF money < discounted_cost }}
Нажммите <b>оплатить 💵</b> чтобы пополнить баланс на {{ discounted_cost - money }} рублей
    {{ ELSE }}
Тариф будет продлен за счет средств баланса вашего аккаунта
    {{ END }}

Текущий тариф: {{ us.id( args.0 ).name }}
Следующий тариф: {{ new_service.name }}
Стоимость: {{ discounted_cost }} {{ IF user.discount > 0 }} (-{{ user.discount }}%){{ END }}
{{ END }}
{{ buttons = BLOCK }}
            {{ IF money < discounted_cost }}
                [
                    {
                        "text": "Оплатить 💵",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/payment?format=html&user_id={{ user.id }}&amount={{ discounted_cost - money }}"
                        }
                    }
                ],
            {{ END }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/list' %>
{{ TEXT = BLOCK}}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
👥 <b>Ваша реферальная ссылка: <u>\nhttps://t.me/gboxvpn_bot?start={{ user.id }}</u></b>

🔒Ваши активные подписки:
{{ END }}
{{ buttons = BLOCK }}
                    {{ FOR item IN ref( user.services.list_for_api( 'category', 'mz-%' ) ) }}
                        {{ SWITCH item.status }}
                            {{ CASE 'ACTIVE' }}
                            {{ icon = '🟢' }}
                            {{ status = 'Активна' }}
                            {{ CASE 'BLOCK' }}
                            {{ icon = '🔴' }}
                            {{ status = 'Заблокирована' }}
                            {{ CASE 'NOT PAID' }}
                            {{ icon = '💵' }}
                            {{ status = 'Не оплачено' }}
                            {{ CASE }}
                            {{ icon = '⏳' }}
                            {{ status = 'Обработка' }}
                        {{ END }}
                    [
                        {
                            "text": "{{ item.name }} - {{ icon }} {{ status }}",
                            "callback_data": "/service {{ item.user_service_id }}"
                        }
                    ],
                    {{ END }}
                    [
                        {
                            "text": "◀️ Главное меню",
                            "callback_data": "/menu"
                        }
                    ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/service', '/active_service'] %>
{{ service = user.services.list_for_api( 'usi', args.0 ) }}
{{ SWITCH service.status }}
    {{ CASE 'ACTIVE' }}
    {{ icon = '🟢' }}
    {{ status = 'Активна' }}
    {{ CASE 'BLOCK' }}
    {{ icon = '🔴' }}
    {{ status = 'Заблокирована' }}
    {{ CASE 'NOT PAID' }}
    {{ icon = '💵' }}
    {{ status = 'Не оплачено' }}
    {{ CASE }}
    {{ icon = '⏳' }}
    {{ status = 'Обработка' }}
{{ END }}

{{ EXPIRE = BLOCK }}
    {{ USE date }}
    {{ now = date.now }}
    {{ created = date.format(service .created, '%s') }}
    {{ expire = date.format(service .expire, '%s') }}
    {{ remaining = expire - now }}
    {{ IF remaining > 0 }}
        {{ years = remaining DIV (365 * 24 * 60 * 60) }}
        {{ remaining = remaining MOD (365 * 24 * 60 * 60) }}
        {{ months = remaining DIV (30 * 24 * 60 * 60) }}
        {{ remaining = remaining MOD (30 * 24 * 60 * 60) }}
        {{ days = remaining DIV (24 * 60 * 60) }}
        {{ remaining = remaining MOD (24 * 60 * 60) }}
        {{ hours = remaining DIV (60 * 60) }}
        {{ remaining = remaining MOD (60 * 60) }}
        {{ minutes = remaining DIV 60 }}
        {{ seconds = remaining MOD 60 }}
        {{ IF years > 0 }}
            {{ "Осталось " _ years _ " г " _ months _ " мес." }}
        {{ ELSIF months > 0 }}
            {{ "Осталось " _ months _ " мес " _ days _ " дн " _ hours _ " ч " _ minutes _ " мин " _ seconds _ " с" }}
        {{ ELSE }}
            {{ "Осталось " _ days _ " дн " _ hours _ " ч " _ minutes _ " мин " _ seconds _ " с" }}
        {{ END }}
    {{ ELSE }}
        Услуга истекла.
    {{ END }}
{{ END }}

{{ TEXT = BLOCK }}
<b>Подписка</b>:
├ Текущая услуга - {{ service.name }}
    {{ IF service.status != 'ACTIVE' }}
└ <b>{{ status }}</b>
    {{ELSE}}
├ <b>{{ EXPIRE }}</b>
    {{END }}
    {{ IF service.next != null }}
        {{ next = services.list_for_api( 'service_id', service.next ) }}

├ Следующая услуга - {{ next.name }}
└ Стоимость следующей услуги - {{ next.cost }}
    {{ END }}
    {{ IF service.status == 'ACTIVE' }}
        {{ IF service.category.grep('^mz-%').first}}
\nНажмите на кнопку <b>Настроить VPN</b>, для подключения VPN на вашем устройстве
        {{ END }}
    {{ END }}
{{ END }}

{{ buttons = BLOCK }}
        {{ IF service.status == 'ACTIVE' }}
            {{ IF service.category.grep('^mz-%').first }}
                {{ storage_data = storage.read('name','vpn_mrzb_' _ args.0 ) }}
                {{ subscription_url = storage_data.response.subscriptionUrl || storage_data.subscription_url || storage_data.response.subscription_url || '' }}
                {{ IF subscription_url.grep('^https:').first }}
                    [
                        {
                            "text": "🔍Настроить VPN",
                             "web_app": {
                                "url": "{{ subscription_url }}"
                            }
                        }
                    ],
                    [
                        {
                            "text": "Продлить подписку",
                            "callback_data": "/prolongate {{ args.0 }}"
                        }
                    ],
                {{ ELSE }}
                    [
                        {
                            "text": "😢 Ошибка: подключение не найдено (Категория: {{ service.category }}, USI: {{ args.0 }})",
                            "callback_data": "/menu"
                        }
                    ],
                    [
                        {
                            "text": "♻️Обновить информацию об услуге ",
                            "callback_data": "/service {{ args.0 }}"
                        }
                    ],
                {{ END }}
            {{ ELSE }}
                    [
                        {
                            "text": "Продлить подписку",
                            "callback_data": "/prolongate {{ args.0 }}"
                        }
                    ],
            {{ END }}
        {{ END }}
        {{ IF service.status == 'NOT PAID' || service.status == 'BLOCK' }}
                [
                    {
                        "text": "Оплатить 💵",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/payment?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ IF service.status != 'PROGRESS' || user.services.list_for_api( 'category', 'mz-%' ).size > 1 }}
                [
                    {
                        "text": "Удалить ❌",
                        "callback_data": "/delete {{ args.0 }}"
                    }
                ],
                {{ END }}
        {{ END }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "{{ cmd == '/active_service' ? '/start' : '/menu' }}"
                    }
                ]
{{ END }}

{{ IF cmd == '/service' }}
{{ PROCESS edit text=TEXT buttons=buttons}}
{{ ELSIF cmd == '/active_service' }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text":"{{ TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
        "reply_markup" : {
            "inline_keyboard": [
                {{ buttons }}
            ]
        }
    }
}
{{ END }}
<% CASE ['/delete'] %>
{{ us = user.services.list_for_api( 'usi', args.0 ) }}
{{ s_id = us.service_id }}
{{ money_back = service.id( s_id ).config.no_money_back }}
{{ money = BLOCK }}
{{ IF money_back == 0 }}
Деньги не вернутся в счет
{{ ELSE }}
деньги вернуться в счет
{{ END}}
{{ END }}
{{ TEXT = BLOCK }}
Удаление услуги из бота приведет к удалению вашей подписки. В случае приобретения новой - вам придется её настраивать на устройствах заново.
<b>Вы подтверждаете удаление подписки?</b>
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "🗑 ДА, УДАЛИТЬ! 🗑",
                        "callback_data": "/delete_confirmed {{ args.0 }}"
                    }
                ],
                [
                    {
                        "text": "Отмена",
                        "callback_data": "/service {{ args.0 }}"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/delete_confirmed' %>
{
    "shmServiceDelete": {
        "usi": "{{ args.0 }}",
        "callback_data": "/menu",
        "error": "ОШИБКА"
    }
},
{
    "answerCallbackQuery": {
        "callback_query_id": {{ callback_query.id }},
        "text": "Удаление...",
        "show_alert": true
    }
}
<% CASE '/order' %>
{{ TEXT = BLOCK }}
Подписка позволит вам воспользоваться нашим VPN сервисом.

Для подключения мы используем надежный и безопасный протокол VLESS.
Его невозможно детектировать, поэтому он будет работать у вас везде (и даже за рубежом)
{{ END }}
{{ buttons = BLOCK }}
    
    [
        {
            "text": "VLESS TCP",
            "callback_data": "/vless"
        }
    ],
    [
        {
            "text": "◀️ Главное меню",
            "callback_data": "/menu"
        }
    ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/vless' %>
{{ TEXT = BLOCK }}
🔒 Для подключения мы используем надежный и безопасный протокол <b>VLESS</b>.  
Его невозможно детектировать, поэтому он будет работать у вас везде.

<b>Выберите интересующий вас тариф:</b>
{{ END }}
{{ buttons = BLOCK }}
            {{ FOR item IN ref(service.api_price_list( 'category', 'mz-%' )).nsort('cost') }}
                [
                    {
                        "text": "{{ item.name }} - {{ item.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }} ₽ {{ IF user.discount > 0 }}( -{{ user.discount }}%){{ END }}",
                        "callback_data": "/serviceorder {{ item.service_id }}"
                    }
                ],
            {{ END }}
                [
                    
                    {
                        "text": "◀️Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/serviceorder' %>
{
    "shmServiceOrder": {
        "service_id": "{{ args.0 }}",
        "callback_data": "/menu",
        "cb_not_enough_money": "/menu",
        "error": "ОШИБКА"
    }
}

<% CASE ['/help'] %>
{{ TEXT = BLOCK }}
💬 Для связи со службой поддержки вы можете написать ваш вопрос нашему боту, и мы ответим вам при первой возможности.

{{ END }}
{{ buttons = BLOCK }}

               [
                    {
                        "text": "💬Бот поддержки",
                        "url": "https://t.me/gboxvpn"
                    }],[
                    {
                        "text": "📢 ТГ-канал VPN сервис gBox",
                        "url": "https://t.me/gboxinfo"
                    }
                ],
                [
                    {
                        "text": "◀️Предыдущее меню",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/faq'] %>
{{ TEXT = BLOCK }}
❓ Q&A

Здесь вы можете выбрать интересующие вас разделы информации и получить на них ответы

{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "🔒Подключение к VPN",
                        "callback_data": "/vpn_connect"
                    }],

[{"text": "🔄Продление подписки",
                        "callback_data": "/subs_renewal"
                    }],
                [{"text": "⚙️📲Настройка роутинга и приложений ",
                        "callback_data": "/vpn_routing"
                    }],
                [{"text": "🔒Ограничения на сервисе",
                        "callback_data": "/vpn_limits"
                }],
                [{ "text": "◀️ Предыдущее меню",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_connect'] %>
{{ TEXT = BLOCK }}
🔐 <b>Подключение к VPN:</b>

--------------------------------

1️⃣ После приобретения ключа он будет доступен в боте в основном меню 🗝️

2️⃣ Для подключения VPN на устройстве выберите раздел менею <b>Настроить VPN</b>, чтобы открыть веб-версию вашей страницы подписки. 📄

3️⃣ <b>Следуйте инструкциям:</b> Внимательно прочтите все указания на открывшейся странице. 🔍

💬 Если у вас что-то не получается, вы всегда можете написать нам в чате.

{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "📞Чат-Поддержка",
                         "url": "https://t.me/gboxvpn"
                    }
                ],
                [
                    {
                        "text": "◀️ Вернуться в ❓Q&A",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_routing'] %>
{{ TEXT = BLOCK }}
🔐 <b>Что такое роутинг и как его настроить:</b>

--------------------------------

1️⃣ Роутинг - это особенные настройки для работы вашего приложения, благодаря которым можно разделить программы, сайты и сервисы вашего устройства на использование VPN только при необходимости.

2️⃣ Проще говоря, если вы находитесь в РФ, то сайты с окончанием .RU лучше открывать без VPN. Аналогично и с другими работающими сервисами, в т.ч. банками, месседжерами (если они не блокируются в стране)

3️⃣ <b>Для настройки следуйте информации на вашей странице подписки.</b> \n Мы максимально упростили для вас все настройки, и вам достаточно нажать 1 кнопку на странице и настройке применятся на вашем устройстве (за исключением Android приложений v2rayNG и кросс-платформенного Hiddify) 🔍

💬 Если у вас что-то не получается настроить, вы всегда можете написать нам в чате.

{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "📞Чат-Поддержка",
                         "url": "https://t.me/gboxvpn"
                    }
                ],
                [
                    {
                        "text": "◀️ Вернуться в ❓Q&A",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_limits'] %>
{{ TEXT = BLOCK }}
🔒 <b>Ограничения использования на сервисе VPN сервис gBox:</b>  
--------------------------------

0️⃣ <b>Ограничение трафика:</b>  
Каждому пользователю предоставляется 1000 ГБ трафика в месяц.  
❓ <i>Почему это важно?</i>  
Это необходимо для предотвращения злоупотреблений использованием VPN. Наша многолетняя аналитика показала, что 1000 ГБ в месяц — достаточный объем для активного использования сервиса двумя пользователями. 

1️⃣ <b>Запрет на загрузку торрент-файлов:</b>  
🚫 На нашем сервисе запрещено загружать торренты. Нарушение этого правила может привести к блокировке аккаунта без возврата средств.  
🔍 <i>Почему?</i>  
Загрузка торрентов создает значительную нагрузку на каналы связи и увеличивает расход трафика.

2️⃣ <b>Подключение с двух устройств:</b>  
📱 Каждый аккаунт может быть использован на двух устройствах одновременно. Вы можете делиться подпиской с близкими, однако нарушение этого правила может привести к блокировке аккаунта.

3️⃣ <b>Другие ограничения:</b>  
📜 Полный список запретов и правил вы найдете в разделе меню  Правила .


{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "📞Чат-Поддержка",
                         "url": "https://t.me/gboxvpn"
                    }
                ],
                [
                    {
                        "text": "📜 Прочитать правила",
                        "callback_data": "/rules"
                    }
                ],
                [
                    {
                        "text": "◀️ Вернуться в ❓Q&A",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/subs_renewal'] %>
{{ TEXT = BLOCK }}
🔄 <b>Продление подписки:</b>

🔔 Для продления подписки вам достаточно иметь положительный баланс. Подписка продлится автоматически.
--------------------------------
📊 <b>Изменение тарифа:</b>  

1️⃣ На основной странице выберите раздел <b>Продлить подписку</b>.  
2️⃣ Выберите новый тариф.   
3️⃣ Новый тариф будет применен сразу после окончания действующего. Вам будет предложено пополнить ваш счет.

{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Вернуться в ❓ Q&A",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/referals'] %>
{{ TEXT = BLOCK }}
🤝 <b>Партнёрская программа</b>  
Делитесь своей реферальной ссылкой с друзьями!  

<b>Ваш уровень:</b> {{ IF user.settings.partner.income_percent > config.billing.partner.income_percent }}Амбассадор ({{ user.settings.partner.income_percent }}%){{ ELSE }}Партнёр ({{ config.billing.partner.income_percent }}%){{ END }}  

<b>Преимущества программы:</b>  
🔹 <b>Бесплатный VPN:</b> Оплачивайте подписку накопленными бонусами.  
🔹 <b>Пассивный доход:</b> Доход без усилий – просто делитесь ссылкой.  

📎 <b>Ваша ссылка:</b>  
https://t.me/gboxvpn_bot?start={{ user.id }}  

👥 <b>Приведено друзей:</b> {{ user.referrals_count }}  
💰 <b>Заработано:</b> {{ user.get_bonus }} руб.  

{{ IF user.get_bonus >= 100000 }}  
💳 <b>Вывести средства:</b> Кнопка для вывода бонусов доступна в меню.  
{{ END }}  

❓ Если есть вопросы, мы всегда на связи. Напишите в поддержку – мы поможем! 💙  

{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ],
                [
                {
                    "text": "Ввести промокод",
                        "web_app": {
                            "url": "{{ config.api.url }}/shm/v1/template/promo?format=html&uid={{ user.id }}&session_id={{ user.gen_session.id }}"
                        }
                }
                ],
{{ IF user.get_bonus >= 100000 }}
                ,[
                    {
                        "text": "💸 Вывод бонусов 💸",
                        "callback_data": "/money_out"
                    }
                ]
{{ END }}
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/money_out'] %>
{{ TEXT = BLOCK }}
💳 <b>Вывод средств</b>

В настоящее время вывод средств осуществляется в ручном режиме.

Чтобы отправить запрос на вывод средств, пожалуйста, скопируйте и отправьте в этот чат следующее сообщение (нажмите на него, чтобы скопировать):

<pre>
Прошу выполнить вывод средств с реферального счёта:
⭐️ Пользователь: {{ user.settings.telegram.login }}
⭐️ Имя: {{ user.full_name }}
⭐️ ID: {{ user.id }} || Login: {{ user.login }}

💸 Сумма к выводу: {{ user.get_bonus }} 💸

<b>Реквизиты для вывода: </b>
</pre>

<b>После этого, в следующем сообщении, отправьте реквизиты для вывода средств.</b>

⏳ <b>Максимальный срок обработки запроса:</b> до 3 рабочих дней.

Если возникнут вопросы, мы свяжемся с вами. Спасибо за понимание.
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/rules'] %>
{{ TEXT = BLOCK }}
Для начала работы с сервисом, вам обязательно нужно принять наши правила использования:

📜 Правила сервиса: 

 1️⃣ Запрещено использовать VPN для действий, нарушающих законы Российской Федерации. 

 2️⃣ Запрещено использовать VPN для посещения сайтов, связанных с распространением/продажей запрещенных товаров/услуг/материалов (наркотические средства, детское порно и пр.). 

 3️⃣ Запрещено использовать VPN для распространения или продажи запрещенных товаров/услуг/материалов (наркотические средства, детское порно и пр.) или лицензионных товаров без согласования с правообладателем. 

4️⃣ Запрещается использовать VPN для загрузки торрент. Аккаунт будет аннулирован за такую деятельность.

5️⃣ <b>Пользовательское соглашение и Политика конфиденциальности:</b>

 


 ⚠️ В случае нарушения, доступ нарушителя будет ограничен без возмещения оплаты. В случае нарушения закона, данные нарушителя будут зафиксированы и переданы органам правопорядка.
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Предыдущее меню",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/status'] %>
{{ TEXT = BLOCK }}
Все сервера активны
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/about'] %>
{{ TEXT = BLOCK }}
Наш сервис работает на рынке VPN с 2022 года, и нам уже доверяют более 2000 клиентов из разных стран.

🌍 Мы предоставляем более 5 локаций для подключения, и постоянно расширяем их список! Мы внимательно следим за состоянием серверов и всегда готовы помочь нашим клиентам в решении любых вопросов.

📋 <b>Список доступных стран:</b>  
🇵🇱 Польша — 20 Гб/с 
🇫🇮 Финляндия — 1 Гб/с
🇩🇪 Германия — 1 Гб/с   
🇺🇸 США — 1 Гб/с 
🇰🇿 Казахстан — 1 Гб/с 
🇸🇪 Швеция — 1 Гб/с  

🔧 Мы постоянно контролируем и обновляем наши серверы, чтобы обеспечить их бесперебойную работу и высокую доступность.  
Наша цель — гарантировать максимальную надёжность и доступность сервиса для вас!
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "◀️ Предыдущее меню",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}

<% CASE '/new' %>
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text": "Откройте новый интерфейс:",
        "parse_mode": "HTML",
        "reply_markup": {
            "inline_keyboard": [
                [
                    {
                        "text": "Teest",
                        "web_app": {
                            "url": "https://vpn.ev-agency.io/?user_id={{ user.id }}"
                        }
                    }
                ],
                [
                    {
                        "text": "◀️ Главное меню",
                        "callback_data": "/menu"
                    }
                ]
            ]
        }
    }
}


<% CASE %>
{{ IF message.reply_to_message.chat.id == tpl.settings.admin.chat_id }}
{{ text = message.reply_to_message.caption || message.reply_to_message.text }}
{{ chatid = text.split('#').1 }}
{{ IF chatid }}
{{ IF message.photo }}
{
    "sendPhoto": {
        "chat_id": "{{ chatid }}",
"parse_mode": "HTML",
        "photo": "{{ message.photo.0.file_id }}",
        "caption": "📢Сообщение от администрации:\n\n{{message.caption.replace('\n','\n')}}"
    }
}
{{ ELSIF message.text }}
{
    "sendMessage": {
        "chat_id": "{{ chatid }}",
"parse_mode": "HTML",
        "text": "📢<b>Сообщение от администрации:</b>\n\n{{message.text.replace('\n','\n')}}"
    }
}
{{ ELSE }}
{
    "sendMessage": {
        "chat_id": "{{ chatid }}",
        "text": "📢Доступны только тестовые сообщении и отправка фото"
    }
}
{{ END }}
{{ ELSE }}
{
    "sendMessage": {
        "chat_id": "{{ tpl.settings.admin.chat_id }}",
        "text": "🛑Не удалось найти пользователя или вы не ответили на сообщение"
        }
}
{{ END }}
{{ ELSE }}
{{ IF message.photo }}
{
    "sendPhoto": {
        "chat_id": "{{ tpl.settings.admin.chat_id }}",
        "photo": "{{ message.photo.0.file_id }}",ё
"parse_mode": "HTML",
        "caption": "<b>Пишет {{ user.full_name }}-#{{ user.settings.telegram.chat_id }}#:</b>\n\n{{message.caption.replace('\n','\n')}}."
    }
}
{{ ELSIF message.text }}
{
    "sendMessage": {
        "chat_id": "{{ tpl.settings.admin.chat_id }}",
"parse_mode": "HTML",
        "text": "<b>Пишет {{ user.full_name }}-#{{ user.settings.telegram.chat_id }}#:\n\n</b>{{message.text.replace('\n','\n')}}"
    }
}
{{ ELSE }}
{
    "sendMessage": {
        "text": "Доступно только тестовые сообщении и отправка фото"
    }
}
{{ END }}
{{ END }}
<% END %>