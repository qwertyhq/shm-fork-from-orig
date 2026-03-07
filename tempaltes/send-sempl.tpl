{{ TEXT = BLOCK }}
Привет, <b>{{ user.full_name }}</b>! 👋

В связи с сегодня

⚙️ <b>Стабильнее всего сейчас работают:</b>
👉 iOS — ShadowRocket
👉 Android/ПК — ClashMeta / Koala Clash

Чтобы вернуть доступ остальным — добавлены подключения с тегом <b>XHTTP</b>.
⚠️ Возможны редкие вылеты на iOS из-за особенностей маскировки и ограничений памяти на устройствах Apple при высокой нагрузке. Сейчас доступно <b>3 локации</b> с этим тегом.

<b>❗ БЛОК ПО «БЕЛЫМ СПИСКАМ» РАБОТАЕТ ТОЛЬКО НА МОБИЛЬНОЙ СВЯЗИ</b>


Поддержка: <b>@hq_vpn_support_bot</b>
{{ END }}
{{ ret = user.telegram.profile('telegram_bot').send( 
    sendPhoto = {
        photo = "https://ibb.co/1frmZLfg"
        protect_content = "true"
        caption = TEXT
        parse_mode = "HTML"
        reply_markup = {
        inline_keyboard = [
          [
            {
              text = "🏠 В меню",
              callback_data = "/start"
            }
          ],
          [
            {
              text = "🔥 WEB-кабинет!",
              url = "https://t.me/hq_vpn_bot/web"
            }
          ],
          [
            {
              text = "📖 Читать новость на канале",
              url = "https://t.me/hq_vpn"
            }
          ]
        ]
        }
    }
) 
}}
{{ IF ret.result.message_id }}
{{ TG_TOKEN = config.telegram.telegram_bot.token }}
{{ tg_url = "https://api.telegram.org/bot" _ TG_TOKEN _ "/setMessageReaction" }}
{{ reaction_json = '[{"type":"emoji","emoji":"🔥"}]' }}
{{ react = http.post(tg_url, 'content', { 
    'chat_id' => ret.result.chat.id, 
    'message_id' => ret.result.message_id,
    'is_big' => 1,
    'reaction' => reaction_json
}) }}
{{ react.content }}
{{ END }}
