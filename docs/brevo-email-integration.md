# Brevo Email Integration — Deployment Guide

## Обзор

Интеграция email-уведомлений через Brevo HTTP API для SHM.
Включает: транзакционные email-события (6 шт.), верификацию email, сброс пароля.

---

## Что сделано

### 1. Brevo HTTP сервер (server_id=20, gid=13)

| Параметр | Значение |
|----------|----------|
| server_id | 20 |
| name | brevo-email |
| host | `https://api.brevo.com/v3/smtp/email` |
| server_gid | 13 (brevo, http) |
| transport | http |
| settings.method | post |
| settings.content_type | application/json |
| settings.template_id | brevo_system_email (fallback) |
| settings.headers.api-key | `xkeysib-...` |

### 2. Шаблоны (7 шт.)

| Template ID | Назначение | Источник данных |
|-------------|-----------|-----------------|
| brevo_service_created | Создание услуги | event → user/us |
| brevo_service_blocked | Блокировка услуги | event → user/us |
| brevo_low_balance | Низкий баланс | event → user/us |
| brevo_service_prolonged | Продление услуги | event → user/us |
| brevo_payment_received | Оплата получена | event → user/us |
| brevo_forecast | Прогноз | event → user/us |
| **brevo_system_email** | **Верификация / сброс пароля** | **task.settings.{to,subject,message}** |

Шаблоны 1-6 привязаны к событиям (event_settings.template_id).
Шаблон `brevo_system_email` — fallback из server.settings.template_id.

### 3. События (6 шт., ids 46-51)

| ID | Event | Template |
|----|-------|----------|
| 46 | create | brevo_service_created |
| 47 | block | brevo_service_blocked |
| 48 | not_enough_money | brevo_low_balance |
| 49 | prolongate | brevo_service_prolonged |
| 50 | payment | brevo_payment_received |
| 51 | forecast | brevo_forecast |

### 4. Кастомный Const.pm

**Файл:** `prod-files/Const.pm`

Единственное отличие от оригинала:
```perl
# Оригинал (app/lib/Core/Const.pm):
GROUP_ID_MAIL => 2,   # указывает на VPN/SSH группу — email не работает

# Кастомный (prod-files/Const.pm):
GROUP_ID_MAIL => 13,  # указывает на Brevo HTTP группу — email работает
```

---

## Деплой

### 1. Убедиться что файл существует

```bash
ls -la prod-files/Const.pm
```

### 2. Docker Compose уже обновлён

В `docker-compose-prop.yml` добавлены volume mount-ы для **core** и **spool**:

```yaml
# В секции core:
volumes:
  - "./prod-files/Const.pm:/app/lib/Core/Const.pm"

# В секции spool:
volumes:
  - "./prod-files/Const.pm:/app/lib/Core/Const.pm"
```

### 3. Перезапуск

```bash
docker compose -f docker-compose-prop.yml up -d core spool
```

### 4. Проверка

```bash
# Проверить что Const.pm подмонтирован:
docker compose -f docker-compose-prop.yml exec core grep GROUP_ID_MAIL /app/lib/Core/Const.pm
# Ожидаемый вывод: GROUP_ID_MAIL => 13,
```

---

## Как это работает

### Транзакционные email (6 событий)

```
Событие → Core::Events::make()
  → Spool запись с server_gid=13
  → Http.pm берёт template_id из event_settings
  → Шаблон (brevo_*) парсится с user/us данными
  → POST https://api.brevo.com/v3/smtp/email
```

### verify_email / passwd_reset (через Const.pm mount)

```
User.pm → verify_email() / passwd_reset_request()
  → Spool запись с server_gid=GROUP_ID_MAIL (=13 через наш Const.pm)
  → task.settings = {to, subject, message}
  → Http.pm: template_id не в event_settings и не в task.settings
  → Fallback: берёт template_id из server.settings = "brevo_system_email"
  → Шаблон парсит task.settings.to/subject/message
  → POST https://api.brevo.com/v3/smtp/email
```

### Приоритет template_id в Http.pm

```perl
$task->event_settings->{template_id}  # 1. Из события (для 6 транзакционных)
$task->settings->{template_id}         # 2. Из spool task
$server{settings}->{template_id}       # 3. Из сервера (fallback для verify/reset)
```

---

## Защита от спама Telegram-only пользователям

Все 6 шаблонов содержат guard:
```
{{ IF user.emails }}
  ... email JSON ...
{{ END }}
```

Если у пользователя нет email — шаблон возвращает пустую строку, Brevo не вызывается.

Для `brevo_system_email` (verify/reset) — `to` берётся из `task.settings.to`, который заполняется самим пользователем при вводе email.

---

## Файлы

| Файл | Описание |
|------|----------|
| `prod-files/Const.pm` | Кастомный Const.pm (GROUP_ID_MAIL=13) |
| `tempaltes/email/brevo_system_email.tpl` | Универсальный шаблон для verify/reset |
| `tempaltes/email/brevo_*.tpl` | 6 транзакционных шаблонов |
| `docker-compose-prop.yml` | Volume mounts для core и spool |

---

## Feature Request для SHM

Чтобы не монтировать Const.pm, нужна возможность конфигурировать GROUP_ID_MAIL
через настройки. См. раздел ниже.
