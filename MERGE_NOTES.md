# Merge Notes — upstream/master 2.16.4 → qwertyhq fork (2026-05-24)

## Что вмержено

- `security/fix-critical-vulnerabilities` (commit `6fc763a`): SQLi sort_direction, CORS allowlist, EVAL_PERL=0
- `security/webapp-auth-date` (commit `26d868e`): initData replay protection (auth_date staleness check)
- `upstream/master` (tag `2.16.4`, 108 commits, диапазон ~2.8.x → 2.16.4)

Anchor branch (точка отката): `pre-upstream-merge-2026-05-24`.

## Конфликт и его разрешение

Единственный конфликт — `app/lib/Core/User.pm:1491` в `sub api_password_auth_status`.

- HEAD: `get_service('Passkey')`, `get_service('OTP')` + `$settings = $self->get_settings`
- upstream: `get_service('User::Passkey')`, `get_service('User::OTP')` (без settings)

Разрешено: принять upstream-имена сервисов (модули переехали в `Core/User/`), сохранить нашу строку `$settings = $self->get_settings` (нужна для возвращаемого поля `password_set_by_user`).

## Переименования (auto-detected git rename)

- `app/lib/Core/OTP.pm` → `app/lib/Core/User/OTP.pm` (R099)
- `app/lib/Core/Passkey.pm` → `app/lib/Core/User/Passkey.pm` (R097)

## Наши patches, оставшиеся в силе

- `Core/User.pm`: флаг `set_by_user => 1/0` в `passwd()`, `set_new_passwd()`, `reg()`; поле `password_set_by_user` в settings и в ответе `api_password_auth_status`. Совместим с upstream — `Core/User/Passwd.pm` отвечает только за хеширование PBKDF2 `$7$`, не за бизнес-логику смены пароля.
- `Core/Transport/Telegram.pm:1672`: auth_date > 86400 → reject. Расположен после HMAC validation, до `return session`.
- `Core/Sql/Data.pm`: whitelist `sort_direction` (asc/desc).
- `Core/Template.pm`: `EVAL_PERL => 0`.
- `Core/Utils.pm`: `_get_cors_origin()` с allowlist из `config.cors.allowed_origins`.

## Изменения, требующие внимания на проде (volume mounts)

Прод подкладывает override-файлы из `/opt/shm/prod-files/`. После апдейта upstream-образов нужно проверить:

| Файл | Что произошло в upstream | Действие |
|---|---|---|
| `prod-files/Const.pm` | upstream мог добавить новые константы | сравнить с upstream `app/lib/Core/Const.pm`, объединить если нужно |
| `prod-files/spool.pl` | upstream менял `bin/spool.pl` на 11 строк | сравнить с upstream `app/bin/spool.pl`, при необходимости подтянуть |
| `prod-files/Local/{WebSocketNotify,DataNotify,ws_init}.pl|.pm` | upstream удалил `app/lib/Local/*` целиком | наш WS-слой просто перестанет загружаться (нет ссылок). Mount-ы dead, но безвредны. Решить позже — оставить или убрать. |
| `prod-files/realtime-server.pl`, `prod-files/ws-server.pl` | upstream удалил `app/bin/realtime-server.pl` и `app/bin/ws-server.pl` | то же — dead, оставить пока |
| `prod-files/Passkey.pm` (если ещё монтируется) | upstream перенёс `Core/Passkey.pm` → `Core/User/Passkey.pm` | mount на старый путь промахнётся — путь в контейнере исчез. Убрать mount либо переразместить override на новый путь. |
| Image tags `*:latest` в `.env` | upstream опубликовал 2.16.4 | **закрепить версии** `CORE_VERSION=2.16.4` и т.д. перед `docker compose pull` |

## Новые upstream-миграции (обязательные)

- `app/bin/migrations/2.12.1.sql`
- `app/bin/migrations/2.13.0.sql`

Накатываются автоматически через `app/bin/init.pl` при старте контейнера `core`. **Перед накаткой обязательно SQL backup прода.**

## Известные риски для smoke-теста (Этап 3)

- Telegram WebApp авторизация — переписан upstream + наш auth_date fix
- Telegram OIDC login flow (новый upstream test: `t/integration/transport/telegram_oidc_flow.t`)
- Password change flow — наш `set_by_user` patch + upstream PBKDF2 хеш
- Mail отправка — upstream переписал RFC encoding в `Mail.pm`
- HTTP-запросы — upstream добавил `NO_PROXY`
- Brevo интеграция (наша) — не задевалась upstream, должно работать
- Remnawave webhook (наш) — не задевался upstream, должно работать
