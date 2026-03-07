{{#
    Шаблон для обновления данных Telegram пользователя
    
    Использование: Вызывается при каждом взаимодействии с ботом
    для синхронизации актуальных данных пользователя из Telegram
    
    Обновляет:
    - username (login)
    - first_name
    - last_name
    
    Пример использования в боте:
    {{ INCLUDE 'telegram_update_user_info' }}
    или
    {{ PROCESS telegram_update_user_info }}
#}}

{{ tg_username = message.from.username || message.chat.username || '' }}
{{ tg_first_name = message.from.first_name || message.chat.first_name || '' }}
{{ tg_last_name = message.from.last_name || message.chat.last_name || '' }}

{{# Обновляем только если username изменился или отличается от сохранённого #}}
{{ IF tg_username != '' && tg_username != user.settings.telegram.login }}
{{ update_tg = user.set_settings({ 
    'telegram' => { 
        'login' => tg_username, 
        'first_name' => tg_first_name, 
        'last_name' => tg_last_name, 
        'chat_id' => user.settings.telegram.chat_id 
    } 
}) }}
{{ END }}

{{# Опционально: обновляем full_name пользователя если изменилось имя в Telegram #}}
{{ IF tg_first_name != '' }}
{{ new_full_name = tg_first_name _ (tg_last_name ? ' ' _ tg_last_name : '') }}
{{ IF new_full_name != user.full_name }}
{{ update_name = user.set('full_name', new_full_name) }}
{{ END }}
{{ END }}
