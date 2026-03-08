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
{{ lang = user.settings.lang || 'ru' }}
{{ names_en = {
    '12' => 'VPN 1 Month',
    '15' => 'VPN 2 Months',
    '16' => 'VPN 3 Months',
    '17' => 'VPN 6 Months',
    '18' => 'VPN 12 Months',
    '21' => '🎁 Free Trial - 7 Days 🎁',
    '28' => 'Family 1 Month',
    '29' => 'Family 12 Months',
    '30' => 'Traffic Reset',
} }}
<% SWITCH cmd %>
<% CASE 'USER_NOT_FOUND' %>
{{ TEXT = BLOCK }}
Welcome to HQ VPN! 🌐
Добро пожаловать в HQ VPN!

Press <b>Start</b> / Нажмите <b>Начать</b>
{{ END }}
{
    "sendMessage": {
        "text": "{{TEXT.replace('\n','\n')}}",
        "parse_mode": "HTML",
        "reply_markup" : {
            "inline_keyboard": [
                [
                    {
                        "text": "🇬🇧 Start / 🇷🇺 Начать",
                        "callback_data": "/register {{ args.0 }}",
                        "style": "success"
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
        "callback_data": "/set_interface_and_go",
        "error": "ОШИБКА: Логин {{ message.chat.username }} или chat_id {{ message.chat.id }} уже существует"
    }
}

<% CASE '/set_interface_and_go' %>
{{ interface_set = user.set_settings({ 'interface' => 'web' }) }}
{{ tg_lang = callback_query.from.language_code || message.from.language_code || 'en' }}
{{ detected = tg_lang.match('^ru') ? 'ru' : 'en' }}
{{ lang_set = user.set_settings({ 'lang' => detected }) }}
{{ lang = detected }}
{
    "shmRedirectCallback": {
        "callback_data": "/go"
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
{{ IF lang == 'en' }}
To start using the service, you need to accept our terms of use:

📜 Service Rules:
<blockquote expandable>
1️⃣ Using VPN for activities that violate the laws of the Russian Federation is prohibited.

2️⃣ Using VPN to visit sites related to the distribution or sale of prohibited goods, services, or materials (drugs, child pornography, etc.) is prohibited.

3️⃣ Using VPN for distributing or selling prohibited goods, services, or materials or licensed products without the copyright holder's consent is prohibited.

4️⃣ Using VPN for downloading torrents is prohibited. Your account will be terminated for such activity.

5️⃣ <b>User Agreement and Privacy Policy:</b>
https://telegra.ph/Polzovatelskoe-soglashenie-12-05-31

https://telegra.ph/Politika-konfidencialnosti-12-05-25
</blockquote>
⚠️ In case of violation, access to the service will be restricted without refund. In case of law violation, information about the violator will be recorded and handed over to law enforcement.
{{ ELSE }}
Для начала работы с сервисом вам необходимо принять наши правила использования:

📜 Правила сервиса:
<blockquote expandable>
1️⃣ Запрещено использовать VPN для действий, нарушающих законы Российской Федерации.

2️⃣ Запрещено использовать VPN для посещения сайтов, связанных с распространением, продажей запрещённых товаров, услуг или материалов (наркотические средства, детская порнография и т. д.).

3️⃣ Запрещено использовать VPN для распространения или продажи запрещённых товаров, услуг или материалов (наркотические средства, детская порнография и т. д.) либо лицензионной продукции без согласования с правообладателем.

4️⃣ Запрещено использовать VPN для загрузки торрентов. Аккаунт будет аннулирован за подобную деятельность.

5️⃣ <b>Пользовательское соглашение и Политика конфиденциальности:</b>
https://telegra.ph/Polzovatelskoe-soglashenie-12-05-31

https://telegra.ph/Politika-konfidencialnosti-12-05-25
</blockquote>
⚠️ В случае нарушения правил доступ к сервису будет ограничен без возможности возмещения оплаты. В случае нарушения закона информация о нарушителе будет зафиксирована и передана в правоохранительные органы.
{{ END }}
{{ END }}
{
    "sendMessage": {
        "text": "{{TEXT.replace('\n','\n')}}",
        "parse_mode": "HTML",
        "reply_markup" : {
            "inline_keyboard": [
                [
                    {
                        "text": "{{ lang == 'en' ? '✅ Accept' : '✅ Принимаю' }}",
                        "callback_data": "/accept_rules"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '❌ Decline' : '❌ Отказываюсь' }}",
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
{{ canceled = user.set_settings({ 'cancel' => '1' }) }}
{{ rules_reset = user.set_settings({ 'rules_accepted' => '0' }) }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text": "{{ lang == 'en' ? 'We are not on the same page.\\n\\nGoodbye. Press /start to try again.' : 'Нам с вами не по пути.\\n\\nДо свидания. Нажмите /start чтобы попробовать снова.' }}"
    }
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
    "answerCallbackQuery": {
        "callback_query_id": {{ callback_query.id }},
        "text": "{{ lang == 'en' ? '✅ Trial activated!' : '✅ Триал активирован!' }}"
    }
},
{
    "sendMessage": {
        "text": "{{ lang == 'en' ? '⏳ <b>Creating trial subscription...</b>\\n\\nPlease wait, you will receive instructions shortly.' : '⏳ <b>Создаём триальную подписку...</b>\\n\\nПодождите, сейчас придёт уведомление с инструкцией.' }}",
        "parse_mode": "HTML"
    }
}
{{ ELSE }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{
    "sendMessage": {
        "text": "{{ lang == 'en' ? '🌐 Open the Web App to manage subscriptions, payments and referral program:' : '🌐 Откройте Web-приложение для управления подписками, оплатой и реферальной программой:' }}",
        "parse_mode": "HTML",
        "reply_markup": {
            "inline_keyboard": [
                [
                    {
                        "text": "{{ lang == 'en' ? '🚀 Open Web App' : '🚀 Открыть Web-приложение' }}",
                        "web_app": {
                            "url": "https://z-hq.com/?user_id={{ user.id }}"
                        }
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '⚙️ Settings' : '⚙️ Сменить интерфейс' }}",
                        "callback_data": "/show_interface_menu"
                    }
                ]
            ]
        }
    }
}
{{ END }}

<% CASE '/cancel' %>
{{ canceled = user.set_settings({ 'cancel' => '1' }) }}
{{ rules_reset = user.set_settings({ 'rules_accepted' => '0' }) }}
{
    "sendMessage": {
        "text": "{{ lang == 'en' ? 'We are not on the same page.\\n\\nGoodbye. Press /start to try again.' : 'Нам с вами не по пути.\\n\\nДо свидания. Нажмите /start чтобы попробовать снова.' }}"
    }
}
<% CASE ['/menu', '/start', '/deleted_us'] %>
{{ arr = ref( user.services.list_for_api( 'category', 'vpn-m-%' ) ) }}
{{ IF user.settings.cancel == '1' || user.settings.rules_accepted != '1' }}
{{ canceled = user.set_settings({ 'cancel' => '0' }) }}
{
    "shmRedirectCallback": {
        "callback_data": "/go"
    }
}
{{ ELSIF user.settings.interface == 'web' }}
{{ WEB_TEXT = BLOCK }}
{{ IF lang == 'en' }}
🌐 Open the <b>Web App</b> to manage subscriptions, payments and referral program:
{{ ELSE }}
🌐 Откройте <b>Web-приложение</b> для управления подписками, оплатой и реферальной программой:
{{ END }}
{{ END }}
{{ web_buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🚀 Open Web App' : '🚀 Открыть Web-приложение' }}",
                        "web_app": {
                            "url": "https://z-hq.com/?user_id={{ user.id }}"
                        },
                        "style": "primary"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '👥 Referrals' : '👥 Рефералы' }}",
                        "callback_data": "/referals"
                    },
                    {
                        "text": "{{ lang == 'en' ? '💬 Support' : '💬 Поддержка' }}",
                        "callback_data": "/help"
                    }
                ],
                [
                    {
                        "text": "🌍 Language / Язык",
                        "callback_data": "/show_lang_menu"
                    },
                    {
                        "text": "{{ lang == 'en' ? '⚙️ Settings' : '⚙️ Сменить интерфейс' }}",
                        "callback_data": "/show_interface_menu"
                    }
                ]
{{ END }}
{{ IF cmd == '/menu' }}
{{ PROCESS edit text=WEB_TEXT buttons=web_buttons }}
{{ ELSE }}
{{ IF cmd == '/start' }}
{
    "deleteMessage": { "message_id": {{ message.message_id }} }
},
{{ END }}
{
    "sendMessage": {
        "text": "{{ WEB_TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
        "reply_markup": {
            "inline_keyboard": [
                {{ web_buttons }}
            ]
        }
    }
}
{{ END }}
{{ ELSE }}

{{ first = BLOCK }}
{{ IF lang == 'en' }}
Welcome to our service!

This message introduces the main sections of the bot (it will be active for 24 hours only):

1️⃣ <b>To purchase, extend or change your subscription plan</b>, your balance must have enough funds for the selected period.

👥 Check out our <b>referral program</b> — you can use VPN almost for free by inviting friends. You'll earn 20% bonus from every payment your friend makes.

📩 If you need support, write to us in the bot.

💳 <b>Balance: </b>{{ user.balance }} RUB
👥 <b>Bonus balance:</b> {{ user.get_bonus }} RUB
{{ ELSE }}
Рады приветствовать вас в нашем сервисе!

Это сообщение призвано ознакомить вас с основными разделами бота (оно будет активно только 24 часа):

1️⃣ <b>Для приобретения, продления или смены тарифа подписки</b> на вашем балансе должна быть сумма, равная стоимости подписки на выбранный период.

👥 Обязательно ознакомьтесь с нашей <b>реферальной программой</b> — благодаря ей вы сможете пользоваться VPN практически бесплатно (если привлечёте достаточно друзей). За каждую оплату, сделанную вашим другом, вы будете получать 20% на свой бонусный счёт.

📩 Если вам потребуется поддержка, вы сможете написать нам в бота.

💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
{{ END }}
{{ END }}
{{ USER_TEXT = BLOCK }}
{{ IF lang == 'en' }}
💳 <b>Balance: </b>{{ user.balance }} RUB
👥 <b>Bonus balance:</b> {{ user.get_bonus }} RUB
👥 <b>Your referral link: <u>\nhttps://t.me/hq_vpn_bot?start={{ user.id }}</u></b>
{{ ELSE }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
👥 <b>Ваша реферальная ссылка: <u>\nhttps://t.me/hq_vpn_bot?start={{ user.id }}</u></b>
{{ END }}
{{ END }}
{{ TEXT = BLOCK }}
    {{ IF cmd == '/deleted_us' }}
    {{ IF lang == 'en' }}
    ❌ <b>Your subscription <u>{{ names_en.item(us.service.service_id) || us.service.name }}</u> was deleted due to non-payment (or at your request).</b>❌

    💡 <b>If you want to continue using our service, please create a new subscription.</b>

    If you have any questions, we're always happy to help.
    {{ ELSE }}
    ❌ <b>Ваша подписка <u>{{ us.service.name }}</u> была удалена из-за неуплаты (либо по вашему желанию).</b>❌

    💡 <b>Если вы хотите продолжить использование нашего сервиса, пожалуйста оформите новую подписку.</b>

    Если у вас возникли вопросы, мы всегда готовы помочь.
    {{ END }}
    {{ ELSE }}
        {{ USE date }}
        {{ date_now = date.now }}
        {{ sec_created = date.format(user.created, '%s') }}
        {{ days_left = (date_now - sec_created) div 86400 }}

        {{ IF days_left <= 1 }}
            {{ first }}
        {{ ELSE }}
            {{ IF arr.size == 1 }}
{{ lang == 'en' ? 'Hello again' : 'Снова здравствуйте' }}, {{ user.full_name }}!
{{ USER_TEXT }}

{{ lang == 'en' ? '🔒 Your active subscription:' : '🔒Ваша активная подписка:' }}

            {{ FOR item IN arr }}
                {{ SWITCH item.status }}
                    {{ CASE 'ACTIVE' }}
                    {{ icon = '🟢' }}
                    {{ status = lang == 'en' ? 'Active' : 'Активна' }}
                    {{ CASE 'BLOCK' }}
                    {{ icon = '🔴' }}
                    {{ status = lang == 'en' ? 'Blocked' : 'Заблокирована' }}
                    {{ CASE 'NOT PAID' }}
                    {{ icon = '💵' }}
                    {{ status = lang == 'en' ? 'Not paid' : 'Не оплачено' }}
                    {{ CASE }}
                    {{ icon = '⏳' }}
                    {{ status = lang == 'en' ? 'Processing, refresh the page' : 'Обработка, обновите страницу' }}
                {{ END }}
{{ lang == 'en' ? 'Plan' : 'Тариф' }}: {{ lang == 'en' ? (names_en.item(item.service_id) || item.name) : item.name }}
{{ lang == 'en' ? 'Status' : 'Статус' }}: {{ icon }} {{ status }}
{{ lang == 'en' ? 'Expires' : 'Срок окончания' }}: {{ item.expire }}
            {{ END }}
            {{ ELSIF arr.size >= 2 }}

{{ lang == 'en' ? 'Hello again' : 'Снова здравствуйте' }}, {{ user.full_name }}!

{{ USER_TEXT }}

{{ lang == 'en' ? '🔒 Your active subscriptions:' : '🔒Ваши активные подписки:' }}
            {{ ELSE }}
{{ USER_TEXT }}

{{ IF lang == 'en' }}
⚠️ <b>You don't have any active subscriptions yet.</b>

💳 You need a positive balance to purchase a subscription.
{{ ELSE }}
⚠️ <b>У Вас еще нет активных подписок.</b>

💳 Для покупки подписки у вас должен быть положительный баланс на счету.
{{ END }}
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
                            "text": "{{ lang == 'en' ? 'My subscriptions' : 'Список моих подписок' }}",
                            "callback_data": "/list"
                        }
                    ],
                {{ ELSIF arr.size == 2 }}
                    {{ FOR item IN ref( user.services.list_for_api( 'category', 'vpn-m-%' ) ) }}
                        {{ SWITCH item.status }}
                            {{ CASE 'ACTIVE' }}
                            {{ icon = '🟢' }}
                            {{ status = lang == 'en' ? 'Active' : 'Активна' }}
                            {{ CASE 'BLOCK' }}
                            {{ icon = '🔴' }}
                            {{ status = lang == 'en' ? 'Blocked' : 'Заблокирована' }}
                            {{ CASE 'NOT PAID' }}
                            {{ icon = '💵' }}
                            {{ status = lang == 'en' ? 'Not paid' : 'Не оплачено' }}
                            {{ CASE }}
                            {{ icon = '⏳' }}
                            {{ status = lang == 'en' ? 'Processing' : 'Обработка' }}
                        {{ END }}
                        {{ _n = lang == 'en' ? (names_en.item(item.service_id) || item.name) : item.name }}
                    [
                        {
                            "text": "{{ _n }} - {{ icon }} {{ status }}",
                            "callback_data": "/service {{ item.user_service_id }}"
                        }
                    ],
                    {{ END }}
                {{ ELSE }}
                [
                    {
                        "text": "{{ lang == 'en' ? 'Extend subscription' : 'Продлить подписку' }}",
                        "callback_data": "/prolongate {{ arr.0.user_service_id }}"
                    }
                ],
                {{ IF us.id(arr.0.user_service_id).status == 'BLOCK' }}
                [
                    {
                        "text": "{{ lang == 'en' ? '💳 Top up balance' : '💳 Пополнить баланс' }}",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/tg_payments?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ ELSIF us.id(arr.0.user_service_id).status == 'ACTIVE' }}
    {{ subscription_url = storage.read('name','vpn_mrzb_' _ arr.0.user_service_id ).response.subscriptionUrl }}
    {{ IF subscription_url.grep('^https:').first }}
                    [
                        {
                            "text": "{{ lang == 'en' ? '🔍 Setup VPN' : '🔍 Настроить VPN' }}",
                             "web_app": {
                                "url": "{{ subscription_url }}"
                            }
                        }
                    ],
                {{ END }}
                {{ END }}
                {{ END }}
                {{ IF arr.size > 2 }}
                [
                    {
                        "text": "{{ lang == 'en' ? '💳 Top up balance' : '💳 Пополнить баланс' }}",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/tg_payments?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ END }}
            {{ ELSE }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🔒 Buy subscription' : '🔒 Купить подписку' }}",
                        "callback_data": "/vless"
                    }
                ],
            {{ END }}
                [
                    {
                        "text": "{{ lang == 'en' ? '♻️ Refresh' : '♻️ Обновить страницу' }}",
                        "callback_data": "/menu"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '👥 Referral program' : '👥 Реферальная программа' }}",
                        "callback_data": "/referals"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '📊 More' : '📊 Дополнительное меню' }}",
                        "callback_data": "/menu_2"
                    }
                ],
                [
                    {
                        "text": "🌍 Language / Язык",
                        "callback_data": "/show_lang_menu"
                    },
                    {
                        "text": "{{ lang == 'en' ? '⚙️ Settings' : '⚙️ Сменить интерфейс' }}",
                        "callback_data": "/show_interface_menu"
                    }
                ]
           ]
        }
    }
}
{{ END }}

<% CASE '/change_interface' %>
{{ current_interface = user.settings.interface || 'bot' }}
{{ interface_set = user.set_settings({ 'interface' => args.0 }) }}
{
    "shmRedirectCallback": {
        "callback_data": "/menu"
    }
}

<% CASE '/show_interface_menu' %>
{{ current_interface = user.settings.interface || 'bot' }}
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
⚙️ <b>Switch interface</b>

Current interface: {{ current_interface == 'web' ? '🌐 Web' : '🤖 Bot' }}

Choose a new interface:
{{ ELSE }}
⚙️ <b>Смена интерфейса</b>

Текущий интерфейс: {{ current_interface == 'web' ? '🌐 Web-интерфейс' : '🤖 Бот-интерфейс' }}

Выберите новый интерфейс для работы:
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                {{ IF current_interface != 'bot' }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🤖 Switch to Bot' : '🤖 Переключиться на Бот-интерфейс' }}",
                        "callback_data": "/change_interface bot"
                    }
                ],
                {{ END }}
                {{ IF current_interface != 'web' }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🌐 Switch to Web' : '🌐 Переключиться на Web-интерфейс' }}",
                        "callback_data": "/change_interface web"
                    }
                ],
                {{ END }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ IF cmd == '/show_interface_menu' }}
{{ PROCESS edit text=TEXT buttons=buttons}}
{{ ELSE }}
{
    "editMessageText": {
        "message_id": {{ message.message_id }},
        "text":"{{ TEXT.replace('\n','\n') }}",
        "parse_mode": "HTML",
        "reply_markup": {
            "inline_keyboard": [
                {{ buttons }}
            ]
        }
    }
}
{{ END }}
<% CASE '/set_lang' %>
{{ lang_set = user.set_settings({ 'lang' => args.0 }) }}
{{ lang = args.0 }}
{
    "shmRedirectCallback": {
        "callback_data": "/menu"
    }
}

<% CASE '/show_lang_menu' %>
{{ current_lang = user.settings.lang || 'ru' }}
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🌍 <b>Language Settings</b>

Current language: {{ current_lang == 'en' ? '🇬🇧 English' : '🇷🇺 Русский' }}

Choose your language:
{{ ELSE }}
🌍 <b>Настройки языка</b>

Текущий язык: {{ current_lang == 'en' ? '🇬🇧 English' : '🇷🇺 Русский' }}

Выберите язык:
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "🇷🇺 Русский {{ current_lang == 'ru' ? '✓' : '' }}",
                        "callback_data": "/set_lang ru"
                    },
                    {
                        "text": "🇬🇧 English {{ current_lang == 'en' ? '✓' : '' }}",
                        "callback_data": "/set_lang en"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons }}

<% CASE '/menu_2' %>
{{ TEXT = BLOCK}}
{{ lang == 'en' ? 'Please select a menu item.' : 'Пожалуйста выберите интересующий вас пункт меню.' }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🔒 Buy subscription' : '🔒 Купить подписку' }}",
                        "callback_data": "/vless"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '💬 Support' : '💬 Поддержка' }}",
                        "callback_data": "/help"
                    },
                    {
                        "text": "❓ Q&A",
                        "callback_data": "/faq"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '📜 Rules' : '📜 Правила' }}",
                        "callback_data": "/rules"
                    },
                    {
                        "text": "{{ lang == 'en' ? 'About' : 'О сервисе' }}",
                        "callback_data": "/about"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '⚙️ Settings' : '⚙️ Сменить интерфейс' }}",
                        "callback_data": "/show_interface_menu"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '📶 Server status' : '📶 Статус серверов' }}",
                        "web_app": {
                            "url": "https://status.z-hq.com/status/hq"
                        }
                    }],
                    [
                    {
                        "text": "{{ lang == 'en' ? '📢 TG Channel HQ VPN' : '📢 ТГ-канал HQ VPN' }}",
                         "url": "https://t.me/hq_vpn"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/prolongate' %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
💳 <b>Balance: </b>{{ user.balance }} RUB
👥 <b>Bonus balance:</b> {{ user.get_bonus }} RUB

<b>Your current subscription:</b>
{{ u_service = user.services.list_for_api( 'usi', args.0 ) }}
Plan: {{ names_en.item(u_service.service_id) || u_service.name }}
Cost: {{ u_service.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }}
Status: {{ u_service.status == 'ACTIVE' ? '🟢 Paid': '🔴 Blocked'}}
Expires: {{ u_service.expire }}

📊 <b>Select a new plan</b> to extend
{{ ELSE }}
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
{{ END }}
{{ buttons = BLOCK }}
                {{ FOR item IN ref(service.api_price_list( 'category', 'vpn-m-%' )).nsort('cost') }}
                    [
                        {
                            "text": "{{ lang == 'en' ? (names_en.item(item.service_id) || item.name) : item.name }} - {{ item.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }} ₽ {{ IF user.discount > 0 }} (-{{ user.discount }}%){{ END }}",
                            "callback_data": "/prolongate_confirm {{ args.0 _ ' ' _ item.service_id }}"
                        }
                    ],
                {{ END }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
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
{{ IF lang == 'en' }}
💳 <b>Balance: </b>{{ user.balance }} RUB
👥 <b>Bonus balance:</b> {{ user.get_bonus }} RUB

    {{ IF money < discounted_cost }}
Press <b>Pay 💵</b> to top up your balance by {{ discounted_cost - money }} RUB
    {{ ELSE }}
The plan will be extended using your account balance
    {{ END }}

Current plan: {{ names_en.item(us.id( args.0 ).service_id) || us.id( args.0 ).name }}
Next plan: {{ names_en.item(new_service.service_id) || new_service.name }}
Cost: {{ discounted_cost }} {{ IF user.discount > 0 }} (-{{ user.discount }}%){{ END }}
{{ ELSE }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей

    {{ IF money < discounted_cost }}
Нажмите <b>оплатить 💵</b> чтобы пополнить баланс на {{ discounted_cost - money }} рублей
    {{ ELSE }}
Тариф будет продлен за счет средств баланса вашего аккаунта
    {{ END }}

Текущий тариф: {{ us.id( args.0 ).name }}
Следующий тариф: {{ new_service.name }}
Стоимость: {{ discounted_cost }} {{ IF user.discount > 0 }} (-{{ user.discount }}%){{ END }}
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
            {{ IF money < discounted_cost }}
                [
                    {
                        "text": "{{ lang == 'en' ? 'Pay 💵' : 'Оплатить 💵' }}",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/tg_payments?format=html&user_id={{ user.id }}&amount={{ discounted_cost - money }}"
                        }
                    }
                ],
            {{ END }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/list' %>
{{ TEXT = BLOCK}}
{{ IF lang == 'en' }}
💳 <b>Balance: </b>{{ user.balance }} RUB
👥 <b>Bonus balance:</b> {{ user.get_bonus }} RUB
👥 <b>Your referral link: <u>\nhttps://t.me/hq_vpn_bot?start={{ user.id }}</u></b>

🔒 Your active subscriptions:
{{ ELSE }}
💳 <b>Текущий баланс: </b>{{ user.balance }} руб.
👥 <b>Бонусный баланс:</b> {{ user.get_bonus }} рублей
👥 <b>Ваша реферальная ссылка: <u>\nhttps://t.me/hq_vpn_bot?start={{ user.id }}</u></b>

🔒Ваши активные подписки:
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                    {{ FOR item IN ref( user.services.list_for_api( 'category', 'vpn-m-%' ) ) }}
                        {{ SWITCH item.status }}
                            {{ CASE 'ACTIVE' }}
                            {{ icon = '🟢' }}
                            {{ status = lang == 'en' ? 'Active' : 'Активна' }}
                            {{ CASE 'BLOCK' }}
                            {{ icon = '🔴' }}
                            {{ status = lang == 'en' ? 'Blocked' : 'Заблокирована' }}
                            {{ CASE 'NOT PAID' }}
                            {{ icon = '💵' }}
                            {{ status = lang == 'en' ? 'Not paid' : 'Не оплачено' }}
                            {{ CASE }}
                            {{ icon = '⏳' }}
                            {{ status = lang == 'en' ? 'Processing' : 'Обработка' }}
                        {{ END }}
                        {{ _n = lang == 'en' ? (names_en.item(item.service_id) || item.name) : item.name }}
                    [
                        {
                            "text": "{{ _n }} - {{ icon }} {{ status }}",
                            "callback_data": "/service {{ item.user_service_id }}"
                        }
                    ],
                    {{ END }}
                    [
                        {
                            "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
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
    {{ status = lang == 'en' ? 'Active' : 'Активна' }}
    {{ CASE 'BLOCK' }}
    {{ icon = '🔴' }}
    {{ status = lang == 'en' ? 'Blocked' : 'Заблокирована' }}
    {{ CASE 'NOT PAID' }}
    {{ icon = '💵' }}
    {{ status = lang == 'en' ? 'Not paid' : 'Не оплачено' }}
    {{ CASE }}
    {{ icon = '⏳' }}
    {{ status = lang == 'en' ? 'Processing' : 'Обработка' }}
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
            {{ IF lang == 'en' }}{{ years _ "y " _ months _ "mo left" }}{{ ELSE }}{{ "Осталось " _ years _ " г " _ months _ " мес." }}{{ END }}
        {{ ELSIF months > 0 }}
            {{ IF lang == 'en' }}{{ months _ "mo " _ days _ "d " _ hours _ "h " _ minutes _ "m left" }}{{ ELSE }}{{ "Осталось " _ months _ " мес " _ days _ " дн " _ hours _ " ч " _ minutes _ " мин " _ seconds _ " с" }}{{ END }}
        {{ ELSE }}
            {{ IF lang == 'en' }}{{ days _ "d " _ hours _ "h " _ minutes _ "m left" }}{{ ELSE }}{{ "Осталось " _ days _ " дн " _ hours _ " ч " _ minutes _ " мин " _ seconds _ " с" }}{{ END }}
        {{ END }}
    {{ ELSE }}
        {{ lang == 'en' ? 'Service expired.' : 'Услуга истекла.' }}
    {{ END }}
{{ END }}

{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
<b>Subscription</b>:
├ Current plan - {{ names_en.item(service.service_id) || service.name }}
    {{ IF service.status != 'ACTIVE' }}
└ <b>{{ status }}</b>
    {{ELSE}}
├ <b>{{ EXPIRE }}</b>
    {{END }}
    {{ IF service.next != null }}
        {{ next = services.list_for_api( 'service_id', service.next ) }}

├ Next plan - {{ names_en.item(next.service_id) || next.name }}
└ Next plan cost - {{ next.cost }}
    {{ END }}
    {{ IF service.status == 'ACTIVE' }}
        {{ IF service.category.grep('^vpn-m-%').first}}
\nPress <b>Setup VPN</b> to connect VPN on your device
        {{ END }}
    {{ END }}
{{ ELSE }}
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
        {{ IF service.category.grep('^vpn-m-%').first}}
\nНажмите на кнопку <b>Настроить VPN</b>, для подключения VPN на вашем устройстве
        {{ END }}
    {{ END }}
{{ END }}
{{ END }}

{{ buttons = BLOCK }}
        {{ IF service.status == 'ACTIVE' }}
            {{ IF service.category.grep('^vpn-m-%').first }}
                {{ subscription_url = storage.read('name','vpn_mrzb_' _ args.0 ).response.subscriptionUrl }}
                {{ IF subscription_url.grep('^https:').first }}
                    [
                        {
                            "text": "{{ lang == 'en' ? '🔍 Setup VPN' : '🔍 Настроить VPN' }}",
                             "web_app": {
                                "url": "{{ subscription_url }}"
                            }
                        }
                    ],
                    [
                        {
                            "text": "{{ lang == 'en' ? 'Extend subscription' : 'Продлить подписку' }}",
                            "callback_data": "/prolongate {{ args.0 }}"
                        }
                    ],
                {{ ELSE }}
                    [
                        {
                            "text": "{{ lang == 'en' ? 'ERROR: Contact admin' : 'ОШИБКА: Напишите администратору' }}",
                            "callback_data": "/menu"
                        }
                    ],
                    [
                        {
                            "text": "{{ lang == 'en' ? '♻️ Refresh info' : '♻️ Обновить информацию об услуге' }}",
                            "callback_data": "/service {{ args.0 }}"
                        }
                    ],
                {{ END }}
            {{ ELSE }}
                    [
                        {
                            "text": "{{ lang == 'en' ? 'Extend subscription' : 'Продлить подписку' }}",
                            "callback_data": "/prolongate {{ args.0 }}"
                        }
                    ],
            {{ END }}
        {{ END }}
        {{ IF service.status == 'NOT PAID' || service.status == 'BLOCK' }}
                [
                    {
                        "text": "{{ lang == 'en' ? 'Pay 💵' : 'Оплатить 💵' }}",
                        "web_app": {
                        "url": "{{ config.api.url }}/shm/v1/public/tg_payments?format=html&user_id={{ user.id }}"
                        }
                    }
                ],
                {{ IF service.status != 'PROGRESS' || user.services.list_for_api( 'category', 'vpn-m-%' ).size > 1 }}
                [
                    {
                        "text": "{{ lang == 'en' ? 'Delete ❌' : 'Удалить ❌' }}",
                        "callback_data": "/delete {{ args.0 }}"
                    }
                ],
                {{ END }}
        {{ END }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
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
{{ lang == 'en' ? 'No refund' : 'Деньги не вернутся в счет' }}
{{ ELSE }}
{{ lang == 'en' ? 'Funds will be refunded' : 'деньги вернуться в счет' }}
{{ END}}
{{ END }}
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
Deleting the service will remove your subscription. If you purchase a new one, you'll need to set it up on your devices again.
<b>Do you confirm the deletion?</b>
{{ ELSE }}
Удаление услуги из бота приведет к удалению вашей подписки. В случае приобретения новой - вам придется её настраивать на устройствах заново.
<b>Вы подтверждаете удаление подписки?</b>
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🗑 YES, DELETE! 🗑' : '🗑 ДА, УДАЛИТЬ! 🗑' }}",
                        "callback_data": "/delete_confirmed {{ args.0 }}"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? 'Cancel' : 'Отмена' }}",
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
        "text": "{{ lang == 'en' ? 'Deleting...' : 'Удаление...' }}",
        "show_alert": true
    }
}
<% CASE '/order' %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
A subscription gives you access to our VPN service.

We use the reliable and secure VLESS protocol.
It's undetectable, so it works everywhere (even abroad).
{{ ELSE }}
Подписка позволит вам воспользоваться нашим VPN сервисом.

Для подключения мы используем надежный и безопасный протокол VLESS.
Его невозможно детектировать, поэтому он будет работать у вас везде (и даже за рубежом)
{{ END }}
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
            "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
            "callback_data": "/menu"
        }
    ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE '/vless' %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🔒 We use the reliable and secure <b>VLESS</b> protocol.
It's undetectable, so it works everywhere.

<b>Choose your plan:</b>
{{ ELSE }}
🔒 Для подключения мы используем надежный и безопасный протокол <b>VLESS</b>.  
Его невозможно детектировать, поэтому он будет работать у вас везде.

<b>Выберите интересующий вас тариф:</b>
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
            {{ FOR item IN ref(service.api_price_list( 'category', 'vpn-m-%' )).nsort('cost') }}
                [
                    {
                        "text": "{{ lang == 'en' ? (names_en.item(item.service_id) || item.name) : item.name }} - {{ item.cost * (user.discount > 0 ? (1 - 0.01 * user.discount) : 1) }} ₽ {{ IF user.discount > 0 }}( -{{ user.discount }}%){{ END }}",
                        "callback_data": "/serviceorder {{ item.service_id }}"
                    }
                ],
            {{ END }}
                [
                    
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
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
{{ IF lang == 'en' }}
💬 To contact support, you can write your question to our bot and we'll respond as soon as possible.

{{ ELSE }}
💬 Для связи со службой поддержки вы можете написать ваш вопрос нашему боту, и мы ответим вам при первой возможности.

{{ END }}
{{ END }}
{{ buttons = BLOCK }}

               [
                    {
                        "text": "{{ lang == 'en' ? '💬 Support Bot' : '💬 Бот поддержки' }}",
                        "url": "https://t.me/hq_vpn_support_bot"
                    }],[
                    {
                        "text": "{{ lang == 'en' ? '📢 TG Channel HQ VPN' : '📢 ТГ-канал HQ VPN' }}",
                        "url": "https://t.me/hq_vpn"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/faq'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
❓ Q&A

Browse information sections and find answers to your questions

{{ ELSE }}
❓ Q&A

Здесь вы можете выбрать интересующие вас разделы информации и получить на них ответы

{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '🔒 VPN Connection' : '🔒 Подключение к VPN' }}",
                        "callback_data": "/vpn_connect"
                    }],

[{"text": "{{ lang == 'en' ? '🔄 Renewal' : '🔄 Продление подписки' }}",
                        "callback_data": "/subs_renewal"
                    }],
                [{"text": "{{ lang == 'en' ? '⚙️📲 Routing & apps' : '⚙️📲 Настройка роутинга и приложений' }}",
                        "callback_data": "/vpn_routing"
                    }],
                [{"text": "{{ lang == 'en' ? '🔒 Limitations' : '🔒 Ограничения на сервисе' }}",
                        "callback_data": "/vpn_limits"
                }],
                [{ "text": "{{ lang == 'en' ? '◀️ Back' : '◀️ Предыдущее меню' }}",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_connect'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🔐 <b>VPN Connection:</b>

--------------------------------

1️⃣ After purchasing a key, it will be available in the bot's main menu 🗝️

2️⃣ To connect VPN on your device, select <b>Setup VPN</b> to open the web version of your subscription page. 📄

3️⃣ <b>Follow the instructions:</b> Carefully read all instructions on the page. 🔍

💬 If you need help, you can always write to us in chat.

{{ ELSE }}
🔐 <b>Подключение к VPN:</b>

--------------------------------

1️⃣ После приобретения ключа он будет доступен в боте в основном меню 🗝️

2️⃣ Для подключения VPN на устройстве выберите раздел менею <b>Настроить VPN</b>, чтобы открыть веб-версию вашей страницы подписки. 📄

3️⃣ <b>Следуйте инструкциям:</b> Внимательно прочтите все указания на открывшейся странице. 🔍

💬 Если у вас что-то не получается, вы всегда можете написать нам в чате.

{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "{{ lang == 'en' ? '📞 Support Chat' : '📞 Чат-Поддержка' }}",
                         "url": "https://t.me/hq_vpn_support_bot"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back to ❓Q&A' : '◀️ Вернуться в ❓Q&A' }}",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_routing'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🔐 <b>What is routing and how to set it up:</b>

--------------------------------

1️⃣ Routing is a special configuration that allows you to split apps, websites, and services to use VPN only when needed.

2️⃣ Simply put, if you're in Russia, .RU websites are better opened without VPN. Same applies to banks, messengers, etc.

3️⃣ <b>Follow the instructions on your subscription page.</b> \n We've simplified everything — just press 1 button and settings will apply (except for Android v2rayNG and Hiddify) 🔍

💬 If you need help, you can always write to us in chat.

{{ ELSE }}
🔐 <b>Что такое роутинг и как его настроить:</b>

--------------------------------

1️⃣ Роутинг - это особенные настройки для работы вашего приложения, благодаря которым можно разделить программы, сайты и сервисы вашего устройства на использование VPN только при необходимости.

2️⃣ Проще говоря, если вы находитесь в РФ, то сайты с окончанием .RU лучше открывать без VPN. Аналогично и с другими работающими сервисами, в т.ч. банками, месседжерами (если они не блокируются в стране)

3️⃣ <b>Для настройки следуйте информации на вашей странице подписки.</b> \n Мы максимально упростили для вас все настройки, и вам достаточно нажать 1 кнопку на странице и настройке применятся на вашем устройстве (за исключением Android приложений v2rayNG и кросс-платформенного Hiddify) 🔍

💬 Если у вас что-то не получается настроить, вы всегда можете написать нам в чате.

{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "{{ lang == 'en' ? '📞 Support Chat' : '📞 Чат-Поддержка' }}",
                         "url": "https://t.me/hq_vpn_support_bot"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back to ❓Q&A' : '◀️ Вернуться в ❓Q&A' }}",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/vpn_limits'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🔒 <b>HQ VPN service limitations:</b>  
--------------------------------

0️⃣ <b>Traffic limit:</b>  
Each user gets 450 GB of traffic per month.  
❓ <i>Why?</i>  
This prevents abuse. 450 GB/month is sufficient for active use by two users.

1️⃣ <b>No torrents:</b>  
🚫 Downloading torrents is prohibited. Violations may result in account termination without refund.  
🔍 <i>Why?</i>  
Torrents create heavy load on network channels.

2️⃣ <b>Two devices:</b>  
📱 Each account can be used on two devices simultaneously. You can share with family, but violations may lead to blocking.

3️⃣ <b>Other limitations:</b>  
📜 Full list of rules in the Rules section.


{{ ELSE }}
🔒 <b>Ограничения использования на сервисе HQ VPN:</b>  
--------------------------------

0️⃣ <b>Ограничение трафика:</b>  
Каждому пользователю предоставляется 450 ГБ трафика в месяц.  
❓ <i>Почему это важно?</i>  
Это необходимо для предотвращения злоупотреблений использованием VPN. Наша многолетняя аналитика показала, что 450 ГБ в месяц — достаточный объем для активного использования сервиса двумя пользователями. 

1️⃣ <b>Запрет на загрузку торрент-файлов:</b>  
🚫 На нашем сервисе запрещено загружать торренты. Нарушение этого правила может привести к блокировке аккаунта без возврата средств.  
🔍 <i>Почему?</i>  
Загрузка торрентов создает значительную нагрузку на каналы связи и увеличивает расход трафика.

2️⃣ <b>Подключение с двух устройств:</b>  
📱 Каждый аккаунт может быть использован на двух устройствах одновременно. Вы можете делиться подпиской с близкими, однако нарушение этого правила может привести к блокировке аккаунта.

3️⃣ <b>Другие ограничения:</b>  
📜 Полный список запретов и правил вы найдете в разделе меню  Правила .


{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                                       {
                        "text": "{{ lang == 'en' ? '📞 Support Chat' : '📞 Чат-Поддержка' }}",
                         "url": "https://t.me/hq_vpn_support_bot"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '📜 Read rules' : '📜 Прочитать правила' }}",
                        "callback_data": "/rules"
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back to ❓Q&A' : '◀️ Вернуться в ❓Q&A' }}",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/subs_renewal'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🔄 <b>Subscription renewal:</b>

🔔 To renew, just maintain a positive balance. It auto-renews.
--------------------------------
📊 <b>Changing your plan:</b>  

1️⃣ On the main page, select <b>Extend subscription</b>.  
2️⃣ Choose a new plan.   
3️⃣ The new plan applies after the current one expires. You'll be prompted to top up.

{{ ELSE }}
🔄 <b>Продление подписки:</b>

🔔 Для продления подписки вам достаточно иметь положительный баланс. Подписка продлится автоматически.
--------------------------------
📊 <b>Изменение тарифа:</b>  

1️⃣ На основной странице выберите раздел <b>Продлить подписку</b>.  
2️⃣ Выберите новый тариф.   
3️⃣ Новый тариф будет применен сразу после окончания действующего. Вам будет предложено пополнить ваш счет.

{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back to ❓Q&A' : '◀️ Вернуться в ❓ Q&A' }}",
                        "callback_data": "/faq"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/referals'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
🤝 <b>Referral Program</b>  
Share your referral link and earn from your friends' payments!  

<b>Your level:</b> {{ IF user.settings.partner.income_percent > config.billing.partner.income_percent }}Ambassador ({{ user.settings.partner.income_percent }}%){{ ELSE }}Partner ({{ config.billing.partner.income_percent }}%){{ END }}  

<b>Benefits:</b>  
🔹 <b>Free VPN:</b> Pay for subscription with accumulated bonuses.  
🔹 <b>Passive income:</b> Earn effortlessly – just share the link.  

📎 <b>Your link:</b>  
https://t.me/hq_vpn_bot?start={{ user.id }}  

👥 <b>Friends invited:</b> {{ user.referrals_count }}  
💰 <b>Earned:</b> {{ user.get_bonus }} RUB  

{{ IF user.get_bonus >= 100000 }}  
💳 <b>Withdraw funds:</b> Button available in the menu.  
{{ END }}  

❓ Questions? We're always here to help! 💙  

{{ ELSE }}
🤝 <b>Партнёрская программа</b>  
Делитесь своей реферальной ссылкой и получайте доход от пополнений ваших друзей!  

<b>Ваш уровень:</b> {{ IF user.settings.partner.income_percent > config.billing.partner.income_percent }}Амбассадор ({{ user.settings.partner.income_percent }}%){{ ELSE }}Партнёр ({{ config.billing.partner.income_percent }}%){{ END }}  

<b>Преимущества программы:</b>  
🔹 <b>Бесплатный VPN:</b> Оплачивайте подписку накопленными бонусами.  
🔹 <b>Пассивный доход:</b> Доход без усилий – просто делитесь ссылкой.  

📎 <b>Ваша ссылка:</b>  
https://t.me/hq_vpn_bot?start={{ user.id }}  

👥 <b>Приведено друзей:</b> {{ user.referrals_count }}  
💰 <b>Заработано:</b> {{ user.get_bonus }} руб.  

{{ IF user.get_bonus >= 100000 }}  
💳 <b>Вывести средства:</b> Кнопка для вывода бонусов доступна в меню.  
{{ END }}  

❓ Если есть вопросы, мы всегда на связи. Напишите в поддержку – мы поможем! 💙  

{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '📋 Copy link' : '📋 Скопировать ссылку' }}",
                        "copy_text": {
                            "text": "https://t.me/hq_vpn_bot?start={{ user.id }}"
                        }
                    }
                ],
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ],
                [
                {
                    "text": "{{ lang == 'en' ? 'Enter promo code' : 'Ввести промокод' }}",
                    "web_app": {
                        "url": "https://z-hq.com/?user_id={{ user.id }}"
                    }
                }
                ],
{{ IF user.get_bonus >= 100000 }}
                ,[
                    {
                        "text": "{{ lang == 'en' ? '💸 Withdraw bonuses 💸' : '💸 Вывод бонусов 💸' }}",
                        "callback_data": "/money_out"
                    }
                ]
{{ END }}
{{ END }}


{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/money_out'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
💳 <b>Withdraw funds</b>

Currently, withdrawals are processed manually.

To request a withdrawal, please copy and send the following message to this chat (tap to copy):
{{ ELSE }}
💳 <b>Вывод средств</b>

В настоящее время вывод средств осуществляется в ручном режиме.

Чтобы отправить запрос на вывод средств, пожалуйста, скопируйте и отправьте в этот чат следующее сообщение (нажмите на него, чтобы скопировать):
{{ END }}

<pre>
Прошу выполнить вывод средств с реферального счёта:
⭐️ Пользователь: {{ user.settings.telegram.login }}
⭐️ Имя: {{ user.full_name }}
⭐️ ID: {{ user.id }} || Login: {{ user.login }}

💸 Сумма к выводу: {{ user.get_bonus }} 💸

<b>Реквизиты для вывода: </b>
</pre>

{{ IF lang == 'en' }}
<b>Then, in the next message, send your payment details for withdrawal.</b>

⏳ <b>Maximum processing time:</b> up to 3 business days.

If you have questions, we'll contact you. Thank you for your patience.
{{ ELSE }}
<b>После этого, в следующем сообщении, отправьте реквизиты для вывода средств.</b>

⏳ <b>Максимальный срок обработки запроса:</b> до 3 рабочих дней.

Если возникнут вопросы, мы свяжемся с вами. Спасибо за понимание.
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/rules'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
To use the service, you must accept our terms:

📜 Service Rules:
<blockquote expandable>
1️⃣ Using VPN for activities violating Russian Federation laws is prohibited.

2️⃣ Using VPN to visit sites distributing/selling prohibited goods/services/materials is prohibited.

3️⃣ Using VPN for distributing prohibited goods/services or licensed products without copyright holder's consent is prohibited.

4️⃣ Using VPN for downloading torrents is prohibited. Account will be terminated.

5️⃣ <b>User Agreement and Privacy Policy:</b>

https://telegra.ph/Polzovatelskoe-soglashenie-12-05-31

https://telegra.ph/Politika-konfidencialnosti-12-05-25
</blockquote>
⚠️ Violators will lose access without refund. Law violations will be reported to authorities.
{{ ELSE }}
Для начала работы с сервисом, вам обязательно нужно принять наши правила использования:

📜 Правила сервиса: 

 1️⃣ Запрещено использовать VPN для действий, нарушающих законы Российской Федерации. 

 2️⃣ Запрещено использовать VPN для посещения сайтов, связанных с распространением/продажей запрещенных товаров/услуг/материалов (наркотические средства, детское порно и пр.). 

 3️⃣ Запрещено использовать VPN для распространения или продажи запрещенных товаров/услуг/материалов (наркотические средства, детское порно и пр.) или лицензионных товаров без согласования с правообладателем. 

4️⃣ Запрещается использовать VPN для загрузки торрент. Аккаунт будет аннулирован за такую деятельность.

5️⃣ <b>Пользовательское соглашение и Политика конфиденциальности:</b>

https://telegra.ph/Polzovatelskoe-soglashenie-12-05-31

https://telegra.ph/Politika-konfidencialnosti-12-05-25 


 ⚠️ В случае нарушения, доступ нарушителя будет ограничен без возмещения оплаты. В случае нарушения закона, данные нарушителя будут зафиксированы и переданы органам правопорядка.
{{ END }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back' : '◀️ Предыдущее меню' }}",
                        "callback_data": "/menu_2"
                    }
                ]
{{ END }}
{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/status'] %>
{{ TEXT = BLOCK }}
{{ lang == 'en' ? 'All servers are active' : 'Все сервера активны' }}
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
                        "callback_data": "/menu"
                    }
                ]
{{ END }}

{{ PROCESS edit text=TEXT buttons=buttons}}
<% CASE ['/about'] %>
{{ TEXT = BLOCK }}
{{ IF lang == 'en' }}
Our service has been on the VPN market since 2022, trusted by over 2,000 clients worldwide.

🌍 We offer 5+ connection locations and keep expanding! We monitor our servers closely and are always ready to help.

📋 <b>Available countries:</b>  
🇵🇱 Poland — 20 Gbps 
🇫🇮 Finland — 1 Gbps
🇩🇪 Germany — 1 Gbps   
🇺🇸 USA — 1 Gbps 
🇰🇿 Kazakhstan — 1 Gbps 
🇸🇪 Sweden — 1 Gbps  

🔧 We constantly update our servers for smooth operation and high availability.  
Our goal — maximum reliability for you!
{{ ELSE }}
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
{{ END }}
{{ buttons = BLOCK }}
                [
                    {
                        "text": "{{ lang == 'en' ? '◀️ Back' : '◀️ Предыдущее меню' }}",
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
                        "text": "{{ lang == 'en' ? '◀️ Main menu' : '◀️ Главное меню' }}",
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
        "photo": "{{ message.photo.0.file_id }}",
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