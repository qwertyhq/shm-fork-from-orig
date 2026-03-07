<% TAGS [% %] %>

{{ MACRO getBotUsername BLOCK }}
    {{ 
        token = tpl.settings.telegram.token || config.telegram.token;
        getUsername = http.post("https://api.telegram.org/bot${token}/getMe").result.username; 
        getUsername; 
    }}
{{ END }}

{{
    # Get data from storage
    storageMessageType = user.id(1).storage.read('name', 'bot_configuration').messageType;
    storageMenuCmd = user.id(1).storage.read('name', 'bot_configuration').menuCmd;
    storageCheckNotPaidServices = user.id(1).storage.read('name', 'bot_configuration').checkNotPaidServices;
}}

{{  #   Global variables
    defaultMessageType = (storageMessageType || config.bot.defaultMessageType || 'sendMessage');
    mainMenuCmd = (storageMenuCmd || config.bot.mainMenuCmd || 'start');
    checkNotPaidServices = (storageCheckNotPaidServices == 0 ? 0 : storageCheckNotPaidServices == 1 ? 1 : config.bot.checkNotPaidServices ? config.bot.checkNotPaidServices : 0);
    supportUrl = (config.bot.supportUrl || 'https://t.me/gboxvpn');
    botUsername = (getBotUsername || config.bot.botUsername || tpl.settings.username || 'Set token or username in template settings or set username in config.bot.botUsername');
}}

{{ MACRO sendAlert BLOCK }}
    {
        "answerCallbackQuery": {
            "callback_query_id": {{ callback_query.id }},
            "parse_mode":"HTML",
            "text": "{{ errtext.replace('\n','\n') }}",
            "show_alert": true
        }
    }
    {{ IF redirect }}
        ,{
            "shmRedirectCallback": {
                "callback_data": "{{ redirect }}"
            }
        }
    {{ END }}
    {{ STOP }}
{{ END }}

{{ MACRO redirect BLOCK }}
    {
        "shmRedirectCallback": { "callback_data": "{{ callback }}" }
    }
    {{ STOP }}
{{ END }}



[%# Check for admin rights from user settings %]
[%# for use admin menu, set role = "admin" or "moderator" %]
{{ BLOCK checkAdminRights }}
    {{ IF user.settings.role != "admin" && user.settings.role != "moderator" }}
        {{ sendAlert(code=403, errtext='⭕️ Раздел закрыт', redirect=mainMenuCmd) }}
    {{ END }}
{{ END }}


[%# Check for moderator rights %]
{{ MACRO checkModeratorRights BLOCK }}
    {{ IF user.settings.role == "moderator" && user.settings.moderate.$right != 1 }}
        {{ sendAlert(code=403, errtext="⭕️ Доступ запрещён!", redirect=mainMenuCmd) }}
    {{ END }}
{{ END }}

[%# sendMessage or editMessageText functional %]
{{ MACRO send BLOCK }}
    {{
        messageType =
            (cmd == '/start') ? 'sendMessage' :
            (cmd == 'menu' && mainMenuCmd == 'menu') ? 'editMessageText' :
            (mainMenuCmd == 'start' || cmd == 'start') ? 'sendMessage' :
            (edit == 0) ? 'sendMessage' :
            (edit == 1) ? 'editMessageText' :
            (defaultMessageType == 'editMessageText' ) ? 'editMessageText' :
            defaultMessageType;

        # Clear state
        ret = user.set_settings({'state' => ''});

        IF user.settings.bot.reqPromo > 0;
            delete(msgID=[user.settings.bot.reqPromo]);
            ret = user.set_settings({'bot' => {'reqPromo' => ''} });
        END;

        IF (cmd != '/start' && !edit && messageType != 'editMessageText' );
            delete(msgID=[message.message_id]);
        END; 
        
        # variable check for admin rights to access admin menu
        IF admin == 1;
            PROCESS checkAdminRights;
        END;
    }}
    {
        "sendChatAction": {
            "chat_id": "{{ user.settings.telegram.chat_id }}",
            "action": "typing"
        }
    },
    {
        "{{messageType}}": {
            {{ IF messageType == 'editMessageText'}}
                "message_id": "{{ message.message_id }}",
            {{ END }}
            "parse_mode": "HTML",
            "text": "{{ TEXT.replace('\n','\n') }}",
            "reply_markup": {
                "inline_keyboard": [
                    {{ BUTTONS }}
                ]
            }
        }
    }
{{ END }}

{{ MACRO notification BLOCK }}
    {
        "sendMessage": {
            "parse_mode": "HTML",
            "text": "{{ TEXT.replace('\n','\n') }}",
            "reply_markup": {
            {{ IF force == 1 }}
                "force_reply": true,
                "input_field_placeholder": "{{ placeholder }}"
            {{ END }}
            {{ IF BUTTONS }}
                "inline_keyboard": [
                    {{ BUTTONS }}
                ]
            {{ END }}
            }
        }
    }
{{ END }}

{{ MACRO delete BLOCK }}
{
    "deleteMessages": { "chat_id": {{ user.settings.telegram.chat_id }}, "message_ids": {{ toJson(msgID) }} }
},
{{ END }}


[%# 
    Main bot logic
%]
[% SWITCH cmd %]

[%# Регистрация несуществующих пользователей %]
[% CASE 'USER_NOT_FOUND' %]
{
    "shmRegister": {
        "partner_id": "{{ start_args.partner_id }}",
        "callback_data": "/start",
        "error": "ОШИБКА: Логин {{ message.chat.username }} или chat_id {{ message.chat.id }} уже существует"
    }
}


[%#   Основное / главное меню бота
    #   Команды:
    #       /start, start, menu

    #   Разделы меню:
    #       admin:menu      - меню администратора
    #       user:cabinet    - личный кабинет
    #       user:keys       - ключи
    #       price           - купить подписку
    #       user:referrals  - реферальная система
    #       help            - помощь
%]
[% CASE ['/start', 'start', 'menu'] %]
{{   # variables
     messageType = (cmd == 'menu') ? 1 : 0;
}}


{{ TEXT = BLOCK }}
<b>Меню gBox Service</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ IF user.settings.role == 'moderator' || user.settings.role == 'admin'; }}
        [{ "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}", "callback_data": "admin:menu" }],
    {{ END }}
    [{ "text": "👤 Личный кабинет", "callback_data": "user:cabinet" }],
    [{ "text": "🛒 Купить ключ", "callback_data": "price" }],
    {{ IF user.us.has_services.size }}
        [{ "text": "🔑 Мои ключи", "callback_data": "user:keys" }],
    {{ END }}
    [{ "text": "🤝 Реферальная система", "callback_data": "user:referrals" }],
    [{ "text": "🛟 Помощь", "callback_data": "help" }]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, edit=messageType)  }}


[%#   
    Личный кабинет 
%]
[% CASE ['user:cabinet'] %]
{{ TEXT = BLOCK }}
👤 <b>Личный кабинет gBox Service</b>

UserID: {{ user.id }}
Баланс: {{ user.balance }}₽
Бонусы: {{ user.get_bonus }}₽

{{ IF user.discount }}
Персональная скидка: {{ user.discount }}%
{{ END }}
Кол-во рефералов: {{ user.referrals_count }}

<b>Необходимо оплатить:</b> {{ user.pays.forecast('blocked', 1).total }} ₽
{{ END }}

{{ BUTTONS = BLOCK }}
    [{ "text": "✚ Пополнить баланс", "web_app": { "url": "{{ config.api.url }}/shm/v1/public/payment?format=html&user_id={{ user.id }}" }}],
    [{ "text": "🏷️ Ввести промокод", "callback_data": "promocode" }, { "text": "🏷️ Web", "web_app": { "url": "{{ config.api.url }}/shm/v1/public/promo_webapp?format=html&user_id={{ user.id }}" }}],
    [{ "text": "☰ История платежей", "callback_data": "user:pays" }],
    [{ "text": "🏠 Главное меню", "callback_data": "{{ mainMenuCmd }}" }]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
   Мои ключи
%]
[% CASE ['user:keys'] %]
{{ TEXT = BLOCK }}
🔑  <b>Список VPN ключей</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item IN user.us.items }}
        {{ SWITCH item.status }}
        {{ CASE 'ACTIVE' }}
            {{ icon = '✅' }}
            {{ status = 'Работает' }}
        {{ CASE 'BLOCK' }}
            {{ icon = '❌' }}
            {{ status = 'Заблокирована' }}
        {{ CASE 'NOT PAID' }}
            {{ icon = '💵' }}
            {{ status = 'Ожидает оплаты' }}
        {{ CASE }}
            {{ icon = '⏳' }}
            {{ status = 'Обработка' }}
        {{ END }}

        [
            {
                "text": "#{{ item.user_service_id }} - {{ item.name }} - {{ icon }} {{ status }}",
                "callback_data": "user:keys:id {{ item.user_service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "✚ Купить новый ключ",
            "callback_data": "price"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Меню информации о ключе
    @args.0 - id услуги
%]
[% CASE ['user:keys:id'] %]
{{ # Variables
    us = user.services.list_for_api('usi', args.0);

    # Plugins
    USE date;
}}

{{
    SWITCH us.status;
        CASE 'ACTIVE';
            icon = '✅';
            status = 'Активен';
        CASE 'BLOCK';
            icon = '❌';
            status = 'Заблокирован';
        CASE 'NOT PAID';
            icon = '💵';
            status = 'Ожидает оплату';
        CASE;
            icon = '⏳';
            status = 'Обработка';
    END;
}}

{{ TEXT = BLOCK }}
🔑 <b>Ключ #{{ us.user_service_id }} - {{ us.name }}</b>

{{ IF us.expire }}
🗓️ <b>Оплачен до</b>: {{ date.format(us.expire, '%d.%m.%Y') }}
{{ END }}
<b>Статус</b>: {{ icon }} {{ status }}
{{ IF us.next != us.service_id && us.next > 0 }}
<b>Следующий тариф ключа</b>: {{ service.id(us.next).name }}
{{ END }}
{{ END }}

{{ subscription_url = storage.read('name', 'vpn_mrzb_' _ us.user_service_id).response.subscriptionUrl || "" }}
{{ BUTTONS = BLOCK }}
  {{ IF us.status == 'ACTIVE' && us.category.grep('^mz-vsem').first && subscription_url.grep('^https:').first }}
      [
          {
              "text": "🔗 Подключиться",
              "web_app": {
                  "url": "{{ subscription_url }}"
              }
          }
      ],
  {{ ELSE }}
      [
          {
              "text": "😢 Ошибка: подключение не найдено (Категория: {{ us.category }}, URL: {{ subscription_url }})",
              "callback_data": "{{ mainMenuCmd }}"
          }
      ],
  {{ END }}
  {{ IF us.status == ('NOT PAID' || 'BLOCK') }}
      [
          {
              "text": "💰 Оплатить",
              "callback_data": "user:cabinet"
          }
      ],
      [
          {
              "text": "🗑️ Удалить ключ",
              "callback_data": "user:keys:delete {{ us.user_service_id }}"
          }
      ],
  {{ END }}
      [
          {
              "text": "♻️ Сменить след. тариф",
              "callback_data": "user:keys:next {{ us.user_service_id }}"
          }
      ],
      [
          {
              "text": "🏠 Главное меню",
              "callback_data": "{{ mainMenuCmd }}"
          }
      ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%  #   Меню смены след. тарифа %]
[%#
    Меню смены следующего тарифа
    @args.0 - id услуги
    @args.1 - id следующей услуги
%]
[% CASE ['user:keys:next', 'user:keys:next:confirm'] %]
{{ 
    # Variables
    usi = user.services.list_for_api('usi', args.0);

    # Plugins
    USE date;

    IF cmd == 'user:keys:next:confirm';
        us = us.id(args.0)
        ret = us.set("next", args.1);
        new = service.id(args.1).name;
        
        # Show alert window
        sendAlert(errtext="✅ Следующий тариф успешно изменен на $new", redirect="user:keys:id $usi.user_service_id");
        STOP;
    END;
}}

{{ TEXT = BLOCK }}
ℹ️ Смена тарифа произойдет при следующем продлении ключа

<b>Дата след. продления</b>: {{ date.format(usi.expire, '%d.%m.%Y') }}
<b>Текущий тариф</b>: {{ usi.name }}
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item IN ref(service.api_price_list).nsort('cost') }}
        [
            {
                "text": "{{ item.name }} - {{ item.cost }} руб/мес.",
                "callback_data": "user:keys:next:confirm {{ usi.user_service_id _ ' ' _ item.service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "⭕️ Отменить",
            "callback_data": "user:keys:id {{ usi.user_service_id }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}



[%# 
    Удаление подписки
    @args.0 - id of user service
%]
[% CASE ['user:keys:delete', 'user:keys:delete:confirm'] %]
{{
  us = user.service.list_for_api('usi', args.0);
}}
{{ IF cmd == 'user:keys:delete:confirm' }}
{
    "shmServiceDelete": {
        "usi": "{{ args.0 }}",
        "callback_data": "{{ mainMenuCmd }}",
        "error": "ОШИБКА"
    }
},
{
    "answerCallbackQuery": {
         "callback_query_id": {{ callback_query.id }},
         "parse_mode":"HTML",
         "text": "✅ Ключ успешно удален!",
         "show_alert": true
     }
}
{{ ELSIF us.status != 'ACTIVE' && cmd != 'user:keys:delete:confirm' }}

{{ TEXT = BLOCK }}
🤔 <b>Подтвердите удаление ключа #{{ args.0 }}. Ключ нельзя будет восстановить!</b>
{{ END }}

{{ BUTTONS = BLOCK }}
  [
    {
      "text": "🧨 ДА, УДАЛИТЬ! 🔥",
      "callback_data": "user:keys:delete:confirm {{ args.0 }}"
    }
  ],
  [
      {
          "text": "⇦ Назад",
          "callback_data": "user:keys"
      }
  ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}

{{ END }}


[%#
    Прайс-лист
%]
[% CASE ['price'] %]
{{ TEXT = BLOCK }}
☷ <b>Выберите тарифный план ключа для заказа</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item IN ref(service.api_price_list).nsort('cost') }}
        [
            {
                "text": "{{ item.name }} - {{ item.cost }} руб/мес.",
                "callback_data": "order {{ item.service_id }}"
            }
        ],
    {{ END }}
        [
            {
                "text": "🏠 Главное меню",
                "callback_data": "{{ mainMenuCmd }}"
            }
        ]
{{ END }}

{{
    IF checkNotPaidServices == 1;
        notPaid = user.services.list_for_api('filter', {'status' => 'NOT PAID'}, 'limit', 1);
        IF ref(notPaid).size == 1;
            sendAlert(errtext="⭕️ У вас имеется неоплаченный ключ\n🔑 #$notPaid.user_service_id - $notPaid.name\nОплатите, либо удалите его для покупки нового.", redirect="user:keys:id $notPaid.user_service_id");
            STOP;
        END;
    END;
    send(TEXT=TEXT, BUTTONS=BUTTONS);
}}


[%#
    Кейс регистрации услуги
    @args.0 - id услуги
%]
[% CASE ['order'] %]
{
    "shmServiceOrder": {
        "service_id": {{ args.0 }},
        "callback_data": "/start",
        "cb_not_enough_money": "user:cabinet",
        "error": "<b>ERROR for service order</b>"
    }
},
{
    "answerCallbackQuery": {
         "callback_query_id": {{ callback_query.id }},
         "parse_mode":"HTML",
         "text": "✅ Ключ зарегистрирован.",
         "show_alert": true
     }
}


[%#
    История платежей
%]
[% CASE ['user:pays'] %]
{{
    # Variables
    limit = 5;
    offset = args.0 || 0;
    pays = ref(user.pays.list_for_api('limit', limit, 'offset', offset ));
}}
{{ TEXT = BLOCK }}
☰ <b>История платежей</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in pays }}
        [
            {
                "text": "Дата: {{ item.date }}, Сумма: {{ item.money }} руб.",
                "callback_data": "user:cabinet"
            }
        ],
    {{ END }}
    {{ IF pays.size == limit || offset > 0 }}
        [
        {{ IF offset > 0 }}
            {
                "text": "⬅️ Назад",
                "callback_data": "user:pays {{ offset - limit }}"
            },
        {{ END }}
        {{ IF pays.size == limit }}
            {
                "text": "Ещё ➡️",
                "callback_data": "user:pays {{ limit + offset }}"
            }
        {{ END }}
        ],
    {{ END }}
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Реферальная система 
%]
[% CASE ['user:referrals'] %]
{{ TEXT = BLOCK }}
🤝 <b>Партнёрская программа</b>

Приглашай друзей и зарабатывай {{ config.billing.partner.income_percent }}% с их пополнений. Заработанные деньги можно потратить на покупку или продление ключа.
⬇️️ Твоя реферальная ссылка:
└ <code>https://t.me/{{ botUsername }}?start={{ toBase64Url(toQueryString( partner_id = user.id )) }}</code>
🏅 Статистика:
├ Приведено друзей: {{ user.referrals_count }}
└ Доступно к использованию: {{ user.get_bonus }} ₽
{{ END }}
{{ BUTTONS = BLOCK }}
    [
        {
            "text": "👤 Пригласить друга",
            "url": "https://t.me/share/url?url=https://t.me/{{ botUsername }}?start={{ toBase64Url(toQueryString( partner_id = user.id )) }}"
        }
    ],
    [
        {
            "text": "📃 Список приглашенных",
            "callback_data": "user:referrals:list"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Список приглашенных 
%]
[% CASE ['user:referrals:list'] %]
{{
    limit = 7;
    offset = (args.0 || 0);
    referralsArray = ref(user.list_for_api('admin', 1, 'limit', limit, 'offset', offset, 'filter',{"partner_id" = user.id}));
}}
{{ TEXT = BLOCK }}
📃 <b>Список приглашенных пользователей</b>

Всего приглашено: {{ user.referrals_count }}
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in referralsArray }}
        [
            {
                "text": "{{ item.full_name }}",
                "callback_data": "user:referrals:list"
            }
        ],
    {{ END }}
    {{ IF referralsArray.size == limit || offset > 0}}
    [
        {{ IF offset > 0 }}
            {
                "text": "⬅️ Назад",
                "callback_data": "user:referrals:list {{ offset - limit }}"
            },
        {{ END }}
        {{ IF referralsArray.size == limit }}
            {
                "text": "Ещё ➡️",
                "callback_data": "user:referrals:list {{ limit + offset }}"
            }
        {{ END }}
    ],
    {{ END }}
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Меню помощи
%]
[% CASE ['help'] %]
{{ TEXT = BLOCK }}
<b>По всем вопросам вы можете обратиться в чат поддержки</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "💬 Чат поддержки",
            "url": "{{ supportUrl }}"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}

[%# ########################################################################################### %]
[%# ############################### ADMIN PANEL ############################################### %]
[%# ########################################################################################### %]

[% CASE ['admin:menu'] %]
{{ TEXT = BLOCK }}
〠 <b>Меню {{ role = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); role; }}</b>

⭕️ Будьте осторожны с выбором действий!
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "👨‍💻 Пользователи",
            "callback_data": "admin:users:list"
        }
    ],
    {{ IF user.settings.role == 'admin' || (user.settings.role == 'moderator' && user.settings.moderate.settings == 1 )}}
        [
            {
                "text": "⚙️ Настройки бота",
                "callback_data": "admin:settings"
            }
        ],
    {{ END }}
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}

[% CASE ['admin:settings'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="settings");
}}

{{ TEXT = BLOCK }}
<b>Конфигурация бота</b>

Запретить оформления новых ключей, если есть неоплаченные: {{ notPaidStatus = (checkNotPaidServices == 0 ? '⭕️ Выключено' : '🟢 Включено'); notPaidStatus; }}

Тип сообщений: {{ messageTypeStatus = (defaultMessageType == 'editMessageText' ? '✏️ Редактирование' : '🆕 Новое сообщение'); messageTypeStatus; }}
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "Изменить запрет оформления",
            "callback_data": "admin:settings:change notpaid"
        }
    ],
    [
        {
            "text": "Изменить тип сообщений",
            "callback_data": "admin:settings:change msg"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%  #   Изменение конфигураций %]
[% CASE ['admin:settings:change'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;

    IF args.0 == 'notpaid'; 
        IF checkNotPaidServices == 0;
            ret = user.id(1).storage.save('bot_configuration', 'checkNotPaidServices' => 1, 'messageType' => defaultMessageType, 'menuCmd' => mainMenuCmd );
        ELSIF checkNotPaidServices == 1;
            ret = user.id(1).storage.save('bot_configuration', 'checkNotPaidServices' => 0, 'messageType' => defaultMessageType, 'menuCmd' => mainMenuCmd );
        END;
        sendAlert(errtext="✅ Запрет оформления новых ключей изменен!", redirect="admin:settings");
    
    ELSIF args.0 == 'msg';
        IF defaultMessageType == 'sendMessage';
            ret = user.id(1).storage.save('bot_configuration', 'checkNotPaidServices' => checkNotPaidServices, 'messageType' => 'editMessageText', 'menuCmd' => 'menu' );
        ELSIF defaultMessageType == 'editMessageText';
            ret = user.id(1).storage.save('bot_configuration', 'checkNotPaidServices' => checkNotPaidServices, 'messageType' => 'sendMessage', 'menuCmd' => 'start' );
        END;
        sendAlert(errtext="✅ Тип сообщений изменен!", redirect="admin:settings");
    END;
}}

[% CASE ['admin:users:list'] %]
{{
    limit = 7;
    offset = (args.0 || 0);
    users = ref(user.list_for_api('admin', 1, 'limit', limit, 'offset', offset, 'filter',{"gid" = 0}));
    getCountUsers = ref(user.list_for_api('admin', 1, 'limit', 0, filter, {"gid" = 0})).size;
}}
{{ TEXT = BLOCK }}
👨‍💻 Пользователи

👤 Всего пользователей: {{ getCountUsers - 1 }}
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in users }}
        {{ status = (item.block == 0 ? "🟢" : "🔴") }}
        [
            {
                "text": "{{ status _' '_ item.full_name.replace('"', '\"')  }} ({{ item.user_id _'-'_ item.login }})",
                "callback_data": "admin:users:id {{ item.user_id _' '_ offset }}"
            }
        ],
    {{ END }}
    {{ IF users.size == limit || offset > 0}}
        [
        {{ IF offset > 0 }}
            {
                "text": "⬅️ Назад",
                "callback_data": "admin:users:list {{ offset - limit }}"
            },
        {{ END }}
        {{ IF users.size == limit }}
            {
                "text": "Ещё ➡️",
                "callback_data": "admin:users:list {{ limit + offset }}"
            }
        {{ END }}
        ],
    {{ END }}
    [{ "text": "🔎 Найти по ID", "callback_data": "admin:users:search" }],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}

[% CASE ['admin:users:id'] %]
{{
    userData = user.id(args.0);
    userPartner = user.id(userData.partner_id);
    userServices = ref(userData.services.list_for_api('category','%'));
    offset = args.1;
}}

{{ TEXT = BLOCK }}
👤 <b>Информация о пользователе</b>

Статус: {{ userStatus = (userData.block == 0 ? "🟢 Активен" : "🔴 Заблокирован"); userStatus; }}

Имя: {{ userData.full_name.replace('"', '\"')  }}
ID: {{ userData.user_id }}
Telegram: {{ userData.settings.telegram.login }}
Логин: {{ userData.login }}

Дата регистрации: {{ userData.created }}
Дата пользования: {{ userData.last_login }}
Кто пригласил: {{ userPartner.full_name _' - '_ userPartner.login }}

Баланс: {{ userData.balance }} руб.
Бонусы: {{ userData.get_bonus }} руб.
Скидка: {{ userData.discount }}

Кол-во подписок: {{ userServices.size }}

{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔐 Управление подписками",
            "callback_data": "admin:users:id:subs {{ userData.user_id _' '_ offset }}"
        }
    ],
    [
        {
            "text": "💸 Управление платежами",
            "callback_data": "admin:users:id:pays {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "🎁 Управление бонусами",
            "callback_data": "admin:users:id:bonuses {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "{{ status = (userData.block == 0 ? "🔴 Заблокировать" : "🟢 Активировать"); status; }}",
            "callback_data": "admin:users:block {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:list {{ args.1 }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1, edit=0) }}


[% CASE ['admin:users:block'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="blockUser");

    # Variables
    userData = user.id(args.0);
    name = userData.full_name.replace('"', '\"');
    retcode = (userData.block == 1 ? "0" : "1");
    ret = userData.set(block = retcode);
    status = (userData.block == 1 ? "🔴 заблокирован" : "🟢 активирован");

    sendAlert(errtext="✅ Пользователь $name ($userData.user_id) $status", redirect="admin:users:id $userData.user_id");
}}



[% CASE ['admin:users:id:subs'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listSubs");
}}
{{
    limit = 7;
    last_offset = (args.1 || 0);
    offset = (args.2 || 0);
    userData = user.id(args.0);
    userServices = ref(userData.services.list_for_api('limit', limit, 'offset', offset));
}}
{{ TEXT = BLOCK }}
🔐 Управление подписками

Имя: {{ userData.full_name.replace('"', '\"')  }}
ID: {{ userData.user_id }}
Telegram: {{ userData.settings.telegram.login }}
Логин: {{ userData.login }}

{{ IF userServices.size <= 0}}
<b>У пользователя нет подписок!</b>
{{ END }}
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in userServices }}
    {{ status = (item.status == 'ACTIVE' ? "🟢" : "🔴") }}
        [
            {
                "text": "{{ status; item.user_service_id _' - '_ item.name  }}",
                "callback_data": "admin:subs:id {{ item.user_service_id _ ' ' _ item.user_id }}"
            }
        ],
    {{ END }}
    {{ IF userServices.size == limit }}
        [
            {
                "text": "Ещё ➡️",
                "callback_data": "admin:users:list {{ limit + offset }}"
            }
        ],
    {{ END }}
    {{ IF offset > 0 }}
        [
            {
                "text": "⬅️ Назад",
                "callback_data": "admin:users:list {{ offset - limit }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "➕ Добавить услугу",
            "callback_data": "admin:subs:add {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "➕ Добавить услугу (бесплатно)",
            "callback_data": "admin:subs:add:free {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id _' '_ last_offset }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:subs:add'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addSubs");
}}
{{
    # Variables
    userData = user.id(args.0);
    servicesArray = ref(service.list_for_api).nsort('service_id');
}}
{{ TEXT = BLOCK }}
➕ Выберите услугу для создания пользователю {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in servicesArray }}
        [
            {
                "text": "{{ item.name _' '_ item.descr }} - {{ item.cost }} ₽",
                "callback_data": "admin:subs:add:confirm {{ userData.user_id _' '_ item.service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:subs {{ userData.user_id _' '_ args.1 }}"
        }
    ],
    [
        {
            "text": "⬅️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id _' '_ last_offset }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:subs:add:free'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addFreeSubs");
}}
{{
    # Variables
    userData = user.id(args.0);
    servicesArray = ref(service.list_for_api).nsort('service_id');
}}
{{ TEXT = BLOCK }}
➕ Выберите услугу с 0 стоимостью для создания пользователю {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in servicesArray }}
        [
            {
                "text": "{{ item.name _' '_ item.descr }} - {{ item.cost }} ₽",
                "callback_data": "admin:subs:add:confirm {{ userData.user_id _' '_ item.service_id _' free' }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:subs {{ userData.user_id _' '_ args.1 }}"
        }
    ],
    [
        {
            "text": "⬅️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id _' '_ last_offset }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:subs:add:confirm'] %]
{{ PROCESS checkAdminRights }}
{{
    userData = user.id(args.0);
    createService = service.id(args.1);
    user = user.switch(userData.user_id);
    name = userData.full_name.replace('"', '\"');

    IF args.2 == 'free';
        ret = userData.us.create('service_id' = createService.service_id, 'cost' = 0, 'check_allow_to_order' = 0);
    ELSE;
        ret = userData.us.create('service_id' = createService.service_id, 'check_allow_to_order' = 0);
    END;

    sendAlert(errtext="✅ Подписка $createService.name успешно добавлена пользователю $name ($userData.user_id)", redirect="admin:users:id:subs $userData.user_id");
}}


[% CASE ['admin:subs:id'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listSubs");
}}
{{
    # Arguments:
        # 0 - ID of user service id 
        # 1 - ID of user
    # Variables:
    USE date;
    userData = user.id(args.1);
    userService = userData.us.id(args.0);
    userServiceData = service.id(userService.service_id);
    userServiceNext = service.id(userService.next);
    userSubUrl = (userData.storage.read('name', 'vpn_mrzb_'_ userService.user_service_id).subscription_url || "https://notfound.com");
    subData = http.get(userSubUrl _'/info');
}}
{{ TEXT = BLOCK }}
🔐 Подписка {{ userServiceData.name }} пользователя {{ userData.full_name.replace('"', '\"') }} ({{ userData.user_id }})

ID: {{ userService.user_service_id }}
ID списания: {{ userService.withdraw_id }}
Статус: {{ userService.status }}
Создана: {{ userService.created }}
Заканчивается: {{ userService.expire }}
Следующий тариф: {{ userServiceNext.name }}

Последний онлайн: {{ subData.online_at ? date.format(subData.online_at, '%d.%m.%Y %R') : 'нет информации' }}

{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔗 Подписка {{ userService.user_service_id }} - {{ userServiceData.name }}",
            "web_app": {
                "url": "{{ userSubUrl }}"
            }
        }
    ],
    {{ IF userService.status == 'ACTIVE' || userService.status == 'BLOCK' }}
        [
            {
                "text": "{{ status = (userService.status == 'ACTIVE' ? "🔴 Заблокировать" : "🟢 Активировать"); status; }}",
                "callback_data": "admin:subs:change:status {{ userService.user_service_id }}"
            }
        ],
    {{ ELSIF userService.status == 'PROGRESS' }}
        [
            {
                "text": "⏳ Ожидание (обновите)",
                "callback_data": "admin:subs:id {{ userService.user_service_id _' '_ userData.user_id }}"
            }
        ],
    {{ END }}
    {{ IF userService.status == 'BLOCK' || userService.status == 'NOT PAID' }}
        [
            {
                "text": "❌ Удалить подписку",
                "callback_data": "admin:subs:delete {{ userService.user_service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "🫰 Информация о списании",
            "callback_data": "admin:withdraws:id {{ userService.withdraw_id }}"
        }
    ],
    [
        {
            "text": "⎘ Сменить текущ. тариф",
            "callback_data": "admin:subs:change:current {{ userService.user_service_id }}"
        }
    ],
    [
        {
            "text": "⎘ Сменить след. тариф",
            "callback_data": "admin:subs:change:next {{ userService.user_service_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:subs {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% ####### CHANGE CURRENT PLAN FOR SUBSCRIPTION ###### %]

[% CASE ['admin:subs:change:current'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="changeSubs");
}}
{{
    userService = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(userService.user_id);
    userServiceData = service.id(userService.service_id);
}}
{{ TEXT = BLOCK }}
⎘ Выберите тариф на изменение для подписки {{ userServiceData.name }} #{{ userService.user_service_id }} пользователя {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR list IN ref(service.api_price_list).nsort('service_id') }}
        [
            {
                "text": "{{ list.name _' '_ list.descr }} - {{ list.cost }} ₽",
                "callback_data": "admin:subs:change:current:confirm {{ userService.user_service_id _ ' ' _ list.service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:subs:id {{ userService.user_service_id _ ' '_ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}

[% CASE ['admin:subs:change:current:confirm'] %]
{{ PROCESS checkAdminRights }}
{{
    nextService = args.1;
    data = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(data.user_id);
    username = userData.full_name.replace('"', '\"');
    serviceData = service.id(data.service_id);
    userServiceNext = service.id(nextService);
    
    IF (ret = userData.us.id(data.user_service_id).change('service_id' = nextService));
        sendAlert(
            errtext="✅ Тариф для подписки $serviceData.name #$data.user_service_id пользователя $username (#$userData.user_id) изменен на $userServiceNext.name",
            redirect="admin:subs:id $data.user_service_id $userData.user_id"
        );
    END;
}}



[% ####### Change next plan for subscription ##### %]
[% CASE ['admin:subs:change:next'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="changeSubs");
}}
{{
    userService = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(userService.user_id);
    userServiceData = service.id(userService.service_id);
    userServiceNext = service.id(userService.next);
}}
{{ TEXT = BLOCK }}
⎘ Выберите следующий тариф для подписки {{ userServiceData.name }} пользователя {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

{{ IF userService.next != userService.service_id || userService.next != 0 }}
Следующий тариф: {{ userServiceNext.name }} ({{ userService.next }})
{{ END }}
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR list IN ref(service.api_price_list).nsort('service_id') }}
        [
            {
                "text": "{{ list.name _' '_ list.descr }} - {{ list.cost }} ₽",
                "callback_data": "admin:subs:change:next:confirm {{ userService.user_service_id _ ' ' _ list.service_id }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:subs:id {{ userService.user_service_id _ ' '_ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}

[% CASE ['admin:subs:change:next:confirm'] %]
{{ PROCESS checkAdminRights }}
{{
    nextService = args.1;
    data = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(data.user_id);
    username = userData.full_name.replace('"', '\"');
    serviceData = service.id(data.service_id);
    userServiceNext = service.id(nextService);

    
    IF (ret = userData.us.id(data.user_service_id).set("next", nextService));
        sendAlert(
            errtext="✅ Следующий тариф для подписки $serviceData.name #$data.user_service_id пользователя $username ($userData.user_id) изменён на $userServiceNext.name",
            redirect="admin:subs:id $data.user_service_id $userData.user_id"
        );
    END;
}}


[% CASE ['admin:subs:change:status'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="changeSubs");
}}
{{
    data = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(data.user_id);
    name = userData.full_name.replace('"', '\"');
    serviceData = service.id(data.service_id);

    IF data.status == 'ACTIVE';
        ret = userData.us.id(data.user_service_id).block;
    ELSIF data.status == 'BLOCK';
        ret = userData.us.id(data.user_service_id).activate;
    END;
    
    status = (data.status == 'ACTIVE' ? "🔴 заблокирована" : "🟢 активирована");
    sendAlert(
        errtext="✅ Услуга $serviceData.name ($data.user_service_id) пользователя $name ($userData.user_id) $status",
        redirect="admin:subs:id $data.user_service_id $userData.user_id"
    );
}}


[% CASE ['admin:subs:delete'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="deleteSubs");
}}
{{
    data = ref(us.list_for_api('admin', 1, 'filter', {"user_service_id" = args.0})).first;
    userData = user.id(data.user_id);
    name = userData.full_name.replace('"', '\"');
    serviceData = service.id(data.service_id);

    IF data.status == 'BLOCK' || data.status == 'NOT PAID';
        IF (ret = userData.us.id(data.user_service_id).delete);
            sendAlert(
                errtext="❌ Услуга $serviceData.name ($data.user_service_id) пользователя $name ($userData.user_id) удалена!",
                redirect="admin:users:id:subs $userData.user_id"
            );
        END;
    END;
}}

[% CASE ['admin:users:id:pays'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listPays");
}}
{{
    limit = 5;
    offset = args.1 || 0;
    userData = user.id(args.0);
    userPays = ref(userData.pays.list_for_api('limit', limit, 'offset', offset ));
}}
{{ TEXT = BLOCK }}
👨‍💻 Управление платежами пользователя {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in userPays }}
        [
            {
                "text": "(ID: {{ item.id }}), {{ item.money }} руб, {{ item.date }}",
                "callback_data": "admin:pays:id {{ item.id }}"
            }
        ],
    {{ END }}
    {{ IF offset > 0 }}
        [
            {
                "text": "⬅️ Назад",
                "callback_data": "admin:users:id:pays {{ userData.user_id _' ' }} {{ offset - limit }}"
            }
        ],
    {{ END }}
    {{ IF userPays.size == limit }}
        [
            {
                "text": "Ещё ➡️",
                "callback_data": "admin:users:id:pays {{ userData.user_id _' ' }} {{ limit + offset }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "➕ Добавить платеж",
            "callback_data": "admin:pays:add {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:pays:id'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listPays");
}}
{{
    userPay = ref(pay.list_for_api('admin', 1, 'filter', {"id" = args.0})).first;
    payData = userPay.comment.object;
    payMethod = payData.payment_method;
    payCard = payMethod.card;
    userData = user.id(userPay.user_id);
}}
{{ TEXT = BLOCK }}
💸 Информация о платеже ID {{ userPay.id }} пользователя {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

Дата платежа: {{ userPay.date }}
Платежная система: {{ userPay.pay_system_id }}
Сумма: {{ userPay.money }} руб.

{{ IF userPay.comment.comment }}
<b>Комментарий к платежу</b>
<blockquote>{{ userPay.comment.comment }}</blockquote>
{{ END }}

{{ IF payData }}
<b>Данные о платеже</b>
<blockquote>
ID в системе: {{ payData.id }}
Статус: {{ payData.status }}
{{ IF payCard }}
Тип карты: {{ payCard.card_type }}
Номер карты: {{ payCard.first6 }}******{{ payCard.last4 }}
Банк: {{ payCard.issuer_name }}
Страна банка: {{ payCard.issuer_country }}
Срок действия: {{ payCard.expiry_month }}/{{ payCard.expiry_year }}
{{ END }}
{{ IF payMethod.type == 'sbp' }}
Тип оплаты: СБП
Номер операции в СБП: {{ payMethod.sbp_operation_id }}
Бик Банка: {{ payMethod.payer_bank_details.bic }}
{{ END }}

{{ IF payMethod.title.match('YooMoney') }}
Кошелек YooMoney: {{ payMethod.title }}
ID кошелька: {{ payMethod.account_number }}
{{ END }}
</blockquote>
{{ END }}

{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:pays {{ userPay.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:pays:add'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addPays");
}}
{{
    userData = user.id(args.0);
}}
{{ TEXT = BLOCK }}
💸 Выберите сумму, которую хотите начислить пользователю {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})
Текущий баланс {{ userData.balance }} руб.

{{ END }}
{{ BUTTONS = BLOCK }}
    [
        {
            "text": "10 руб",
            "callback_data": "admin:pays:add:confirm {{ userData.user_id }} 10"
        },
        {
            "text": "20 руб",
            "callback_data": "admin:pays:add:confirm {{ userData.user_id }} 20"
        }
    ],
    [
        {
            "text": "50 руб",
            "callback_data": "admin:pays:add:confirm {{ userData.user_id }} 50"
        },
        {
            "text": "100 руб",
            "callback_data": "admin:pays:add:confirm {{ userData.user_id }} 100"
        }
    ],
    [
        {{ FOR item IN ref(service.api_price_list('category', '%')).nsort('cost') }}
                
            {
                "text": "{{ item.cost }} руб",
                "callback_data": "admin:pays:add:confirm {{ userData.user_id _ ' ' }} {{ item.cost }}"
            },
        {{ END }}
    ],
    [
        {
            "text": "Ввести свою сумму",
            "callback_data": "admin:pays:add:manual {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:pays {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[%#
    Ручное добавление баланса
%]
[% CASE ['admin:pays:add:manual'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addPays");
}}
{{
    userData = user.id(args.0);

    ret = user.set_settings({'state' => 'awaiting_amount'});
    ret = user.set_settings({'bot' => {'switchUser' => userData.user_id} });
}}

{{ TEXT = BLOCK }}
💬 Введите сумму для пополнения баланса пользователя {{ userData.full_name.replace('"', '\"') }}
{{ END }}
{{ notification(TEXT=TEXT, force=1) }}


[% CASE ['admin:pays:add:confirm'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addPays");
}}
{{
    userData = user.id(args.0);
    name = userData.full_name.replace('"', '\"');
    amount = args.1;

    IF (pay = userData.payment('money', amount, 'pay_system_id', 'manual'));
        sendAlert(
            errtext="✅ Баланс пользователя $name ($userData.user_id) пополнен на $amount руб.\nТекущий баланс $userData.balance руб.",
            redirect="admin:pays:add $userData.user_id"
        );
    END;
}}


[% CASE ['admin:users:id:bonuses'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listBonus");
}}
{{
    limit = 5;
    offset = (args.1 || 0);
    userData = user.id(args.0);
    userBonuses = ref(bonus.list_for_api('admin', 1, 'limit', limit, 'offset', offset, 'filter', {"user_id" = userData.user_id}));
}}
{{ TEXT = BLOCK }}
👨‍💻 Управление бонусами пользователя {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

Баланс бонусов: {{ userData.get_bonus }} руб.
{{ END }}

{{ BUTTONS = BLOCK }}
    {{ FOR item in userBonuses }}
        [
            {
                "text": "(ID: {{ item.id }}), {{ item.bonus }} руб., {{ item.date }}",
                "callback_data": "admin:bonuses:id {{ item.id _ ' ' _ offset }}"
            }
        ],
    {{ END }}
    {{ IF offset > 0 }}
        [
            {
                "text": "⬅️ Назад",
                "callback_data": "admin:users:id:bonuses {{ userData.user_id _' ' }} {{ offset - limit }}"
            }
        ],
    {{ END }}
    {{ IF userBonuses.size == limit }}
        [
            {
                "text": "Ещё ➡️",
                "callback_data": "admin:users:id:bonuses {{ userData.user_id _' ' }} {{ limit + offset }}"
            }
        ],
    {{ END }}
    [
        {
            "text": "➕ Добавить бонусы",
            "callback_data": "admin:bonuses:add {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "⬅️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:bonuses:id'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="listBonus");
}}
{{
    offset = args.1;
    data = ref(bonus.list_for_api('admin', 1, 'limit', limit, 'offset', offset, 'filter', {"id" = args.0})).first;
    userData = user.id(data.user_id);
    partnerData = user.id(data.comment.from_user_id)
}}
{{ TEXT = BLOCK }}
💸 Информация о начислении бонусов ID {{ data.id }} пользователю {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

ID начисления: {{ data.id }}
Дата начисления: {{ data.date }}
Сумма начисления: {{ data.bonus }} руб.

{{ IF data.comment.from_user_id }}
<blockquote>{{ data.comment.percent }}% от {{ userData.full_name.replace('"', '\"')  }} ({{ partnerData.user_id }})</blockquote>
{{ END }}

{{ IF data.comment.msg }}
<blockquote>{{ data.comment.msg }}</blockquote>
{{ END }}
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:bonuses {{ userData.user_id _ ' ' _ offset }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:bonuses:add'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addBonus");
}}
{{
    userData = user.id(args.0);
}}
{{ TEXT = BLOCK }}
💸 Выберите кол-во бонусов, которые хотите начислить пользователю {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})
Текущий баланс бонусов {{ userData.get_bonus }} руб.

{{ END }}
{{ BUTTONS = BLOCK }}
    [
        {
            "text": "10 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 10"
        },
        {
            "text": "20 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 20"
        },
        {
            "text": "30 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 30"
        },
        {
            "text": "40 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 40"
        }
    ],
    [
        {
            "text": "50 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 50"
        },
        {
            "text": "100 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 100"
        },
        {
            "text": "150 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 150"
        },
        {
            "text": "200 руб",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} 200"
        }
    ],
    [
        {
            "text": "Убрать {{ userData.get_bonus }}",
            "callback_data": "admin:bonuses:add:confirm {{ userData.user_id }} -{{ userData.get_bonus }}"
        }
    ],
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:users:id:bonuses {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:bonuses:add:confirm'] %]
{{
    # Check for admin or moderator rights
    PROCESS checkAdminRights;
    # Check right for change settings
    checkModeratorRights(right="addBonus");
}}
{{
    userData = user.id(args.0);
    name = userData.full_name.replace('"', '\"');
    amount = args.1;

    IF amount < 0;
        ret = userData.set_bonus('bonus', amount, 'comment', {'msg' => 'Ручная корректировка от администратора'});
    ELSE;
        IF (ret = userData.set_bonus('bonus', amount, 'comment', {'msg' => 'Ручное начисление от администратора'}));
            notification(
                chat_id="$userData.settings.telegram.chat_id",
                TEXT="🎁 Вам начислено $amount бонусов на счет от администратора"
            ); ",";
        END;
    END;

    sendAlert(
        errtext="✅ Баланс бонусов пользователя $name ($userData.user_id) изменен на $amount руб.\nТекущий баланс $userData.get_bonus руб.",
        redirect="admin:bonuses:add $userData.user_id"
    );
}}


[% CASE ['admin:withdraws:id'] %]
{{
    data = ref(wd.list_for_api('admin', 1, 'filter', {"withdraw_id" = args.0})).first;
    userData = user.id(data.user_id);
}}
{{ TEXT = BLOCK }}
💸 Информация о списании №{{ data.withdraw_id }}

Пользователь: {{ userData.full_name.replace('"', '\"')  }} ({{ userData.user_id }})

Услуга: {{ data.name }} ({{ data.user_service_id }})
Стоимость: {{ data.cost }}
Дата создания: {{ data.create_date }}
Дата списания: {{ data.withdraw_date }}
Дата окончания по списанию: {{ data.end_date }}
Кол-во месяцев: {{ data.months }}

<b>Списание:</b>
<blockquote>
Скидка: {{ data.discount }}%
Бонусов: {{ data.bonus }} руб
<b>Всего: {{ data.total }}</b>

</blockquote>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "⬅️ Назад",
            "callback_data": "admin:subs:id {{ data.user_service_id _ ' ' _  userData.user_id }}"
        }
    ],
    [
        {
            "text": "👨‍💻 Меню {{ menuRole = (user.settings.role == 'admin' ? 'администратора' : 'модератора'); menuRole; }}",
            "callback_data": "admin:menu"
        },
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ send(TEXT=TEXT, BUTTONS=BUTTONS, admin=1) }}


[% CASE ['admin:users:search'] %]
{{
    # Set state for user
    ret = user.set_settings({'state' => 'awaiting_search'});
}}
{{ TEXT = BLOCK }}
💬 <b>Введите ID пользователя</b>
{{ END }}
{{ notification(TEXT=TEXT, force=1) }}

[%# ########################################################################################### %]
[%# ############################### ADMIN PANEL END ########################################### %]
[%# ########################################################################################### %]


[%#
    Уведомление после создания ключа
%]
[% CASE ['notification:create'] %]
{{
    USE date;
    usi = args.0;
    service = user.services.list_for_api('usi', usi);
}}
{{ TEXT = BLOCK }}
✅ <b>Ключ #{{ service.user_service_id }} - {{ service.name }} активирован</b>

🗓️ <b>Дата окончания</b>: {{ date.format(service.expire, '%d.%m.%Y') }}

<blockquote><b>Для подключения нажмите 🔐 Подключиться</b></blockquote>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔐 Подключиться",
            "callback_data": "user:keys:id {{ service.user_service_id }}"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}

[%#
    Уведомление после блокировки ключа
%]
[% CASE ['notification:block'] %]
{{
    USE date;
    usi = args.0;
    service = user.services.list_for_api('usi', usi);
}}
{{ TEXT = BLOCK }}
⭕️ <b>Ключ #{{ service.user_service_id }} - {{ service.name }} заблокирован</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔑 Мои ключи",
            "callback_data": "user:keys"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}



[%#
    Уведомление после активации ключа
%]
[% CASE ['notification:activate'] %]
{{
    USE date;
    usi = args.0;
    service = user.services.list_for_api('usi', usi);
}}
{{ TEXT = BLOCK }}
✅ <b>Ключ #{{ service.user_service_id }} - {{ service.name }} активирован</b>

🗓️ <b>Дата окончания</b>: {{ date.format(service.expire, '%d.%m.%Y') }}

<blockquote>Для подключения нажмите 🔐 Подключиться</blockquote>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔐 Подключиться",
            "callback_data": "user:keys:id {{ service.user_service_id }}"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}

[%#
    Уведомление после продления ключа
%]
[% CASE ['notification:prolongate'] %]
{{
    USE date;
    usi = args.0;
    service = user.services.list_for_api('usi', usi);
}}
{{ TEXT = BLOCK }}
✅ <b>Ключ #{{ service.user_service_id }} - {{ service.name }} продлён!</b>

🗓️ Дата окончания: {{ date.format(service.expire, '%d.%m.%Y') }}

<blockquote>Для подключения нажмите 🔐 Подключиться</blockquote>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "🔐 Подключиться",
            "callback_data": "user:keys:id {{ service.user_service_id }}"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}

[%#
    Уведомление FORECAST
%]
[% CASE ['notification:forecast'] %]
{{
    USE date;
    usi = args.0;
    service = user.services.list_for_api('usi', usi);
    cost = user.pays.forecast('blocked', 1).total;
}}
{{ TEXT = BLOCK }}
💰 <b>Необходимо оплатить следующие ключи</b>

    {{ FOR item in ref(user.pays.forecast.items('blocked', 1)) }}
<code>
🔑 #<b>{{ item.user_service_id }} - {{ item.name }}</b>
        {{ IF item.expire }}
🗓️ <b>Дата окончания</b>: {{ date.format(item.expire, '%d.%m.%Y') }}
        {{ END }}
</code>
    {{ END }}

<b>Баланс</b>: {{ user.balance }} руб.
<b>Баланс необходимо пополнить на </b>{{ cost }} руб.
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "➕ Пополнить {{ cost }} руб.",
            "web_app": {
                "url": "{{ config.api.url }}/shm/v1/public/tg_payment?format=html"
            }
        }
    ],
    [
        {
            "text": "🔑 Мои ключи",
            "callback_data": "user:keys"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Уведомление при нехватке средств на балансе
%]
[% CASE ['notification:not_enough_money'] %]
{{
    cost = user.pays.forecast('blocked',1).total;
}}
{{ TEXT = BLOCK }}
ℹ️ <b>Для активации следующих ключей</b>

    {{ FOR item in ref(user.pays.forecast.items) }}
    {{ # NEXT IF item.status != 'NOT PAID'# }}
<code>🔑 #<b>{{ item.user_service_id }} - {{ item.name }}</b></code>
    {{ END }}

<b>Необходимо оплатить </b>{{ cost }} руб.
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "➕ Пополнить {{ cost }} руб.",
            "web_app": {
                "url": "{{ config.api.url }}/shm/v1/public/tg_payment?format=html"
            }
        }
    ],
    [
        {
            "text": "🔑 Мои ключи",
            "callback_data": "user:keys"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Уведомление после пополнения
%]
[% CASE ['notification:payment'] %]
{{ amount = user.pays.last.money }}
{{ total = user.balance }}
{{
    amount = user.pays.last.money;
}}
{{ TEXT = BLOCK }}
✅ <b>Платёж на сумму {{ amount }} руб. зачислен на ваш баланс.</b>

💰 <b>Баланс</b>: {{ user.balance }}
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "👤 Личный кабинет",
            "callback_data": "user:cabinet"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Уведомление после применения промокода
%]
[% CASE ['notification:promo'] %]

{{ TEXT = BLOCK }}
✅ <b>Промокод {{ args.0 }} успешно применён!</b>
{{ END }}

{{ BUTTONS = BLOCK }}
    [
        {
            "text": "👤 Личный кабинет",
            "callback_data": "user:cabinet"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}


[%#
    Применение промокода
%]
[% CASE ['promocode'] %]
{{
    # Устанавливаем переменную
    ret = user.set_settings({'state' => 'awaiting_promocode'});
    IF user.settings.bot.reqPromo;
        temp = user.settings.bot.reqPromo + 1;
        delete(msgID=[temp, user.settings.bot.reqPromo, message.message_id]);
        ret = user.set_settings({'bot' => {'reqPromo' => message.message_id} });
    ELSE;
        ret = user.set_settings({'bot' => {'reqPromo' => message.message_id} });
    END;
}}
{{ TEXT = BLOCK }}
💬 <b>Введите ваш промокод:</b>
{{ END }}

{{ notification(TEXT=TEXT, force=1) }}


[% CASE DEFAULT %]

{{ IF user.settings.state == 'awaiting_search'}}
    {{
        temp = message.message_id - 1;
        delete(msgID=[message.message_id, temp]);
        IF message.text.match('^[1-9]\d*$');
            searchString = message.text;
            ret = user.set_settings({'state' => ''});
            ret = ref(user.list_for_api('admin', 1, 'filter', {"user_id" = searchString} ));

            IF (ret.size > 0);
                resultID = ret.first.user_id;
                redirect(callback="admin:users:id $resultID");
            ELSE;
                TEXT = "⭕️ Пользователь с ID $searchString не найден!";
            END;

        ELSE;
            ret = user.set_settings({'state' => ''});
            TEXT = "❌ <b>Ошибка:</b> ID может содержать только положительное число!";
        END;

        notification(TEXT=TEXT);
    }}

{{ ELSIF user.settings.state == 'awaiting_promocode' }}
    {{
        IF user.settings.bot.reqPromo;
            temp = user.settings.bot.reqPromo + 1;
            temp2 = user.settings.bot.reqPromo - 1;
            delete(msgID=[temp, temp2, user.settings.bot.reqPromo, message.message_id]);
            ret = user.set_settings({'bot' => {'reqPromo' => message.message_id} });
        END;

        # Проверяем, что введено
        IF message.text.match('^[a-zA-Z0-9_-]+$');
            promocode = message.text;
            ret = user.set_settings({'state' => ''});
            
            IF promo.apply(promocode);
                TEXT = "✅ <b>Промокод $promocode применён!</b>";
            ELSE;
                TEXT = "⭕️ <b>Промокод $promocode не найден!</b>";
            END;

        ELSE;
            TEXT = "❌ <b>Ошибка:</b> Промокод может содержать только буквы, цифры, тире (-) и нижнее подчёркивание (_).";
        END;
    }}

    {{ BUTTONS = BLOCK }}
        [
            {
                "text": "🏷️ Ввести ещё",
                "callback_data": "promocode"
            }
        ],
        [
            {
                "text": "🏠 Главное меню",
                "callback_data": "{{ mainMenuCmd }}"
            }
        ]
    {{ END }}
    {{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}


{{ ELSIF user.settings.state == 'awaiting_amount' AND user.settings.bot.switchUser }}
    {{
        userData = user.id(user.settings.bot.switchUser);
        IF message.text.match('^-?\d+(\.\d+)?$');
            amount = message.text;

            IF (ret = userData.payment('money', amount, 'pay_system_id', 'manual'));
                TEXT = "✅ <b>Баланс пользователя $userData.user_id пополнен на $amount руб.</b>\nТекущий баланс: $userData.balance руб.";
            ELSE;
                TEXT = "⭕️ Ошибка пополнения. Повторите попытку.";
            END;

            ret = user.set_settings({'state' => ''});
            ret = user.set_settings({'bot' => {'switchUser' => ''} });
        ELSE;
            TEXT = "⭕️ Ошибка пополнения. Повторите попытку.";
        END;
    }}

    {{ BUTTONS = BLOCK }}
    [
        {
            "text": "ℹ️ Информация о пользователе",
            "callback_data": "admin:users:id {{ userData.user_id }}"
        }
    ],
    [
        {
            "text": "🏠 Главное меню",
            "callback_data": "{{ mainMenuCmd }}"
        }
    ]
{{ END }}
{{ notification(TEXT=TEXT, BUTTONS=BUTTONS) }}
{{ ELSE }}
    {{ 
        ret = user.set_settings({'bot' => {'switchUser' => ''} });
        ret = user.set_settings({'state' => ''});
        delete(msgID=[message.message_id]);
    }}
{{ END }}
[% END %]