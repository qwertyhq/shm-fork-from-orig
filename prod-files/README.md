# prod-files

Кастомные файлы для SHM, монтируются через docker-compose volumes.

## Файлы

| Файл | Монтируется в | Контейнер | Назначение |
|------|--------------|-----------|-----------|
| `Const.pm` | `/app/lib/Core/Const.pm` | core | Кастомные константы |
| `DataNotify.pm` | `/app/lib/Local/DataNotify.pm` | core, spool | Хуки на _set/_add/_delete → Redis |
| `WebSocketNotify.pm` | `/app/lib/Local/WebSocketNotify.pm` | core, spool | Публикация событий в Redis |
| `ws_init.pl` | `/app/lib/Local/ws_init.pm` | core | Автозагрузка DataNotify (через PERL5OPT) |
| `spool.pl` | `/app/bin/spool.pl` | spool | Override: загружает DataNotify |
| `ws-server.pl` | `/app/bin/ws-server.pl` | core | Perl WebSocket сервер (:9083) |
| `entry-core.sh` | `/entry.sh` | core | Override: запускает ws-server + FastCGI |
| `nginx.conf` | `/etc/nginx/nginx.conf` | api | Override: добавлен location /ws |

## Архитектура

```
Клиент (браузер / Telegram Web App)
  ↕ WebSocket (wss://your-domain/ws?session_id=xxx)
Nginx (api контейнер)
  → location /ws  → proxy_pass core:9083 (WebSocket)
  → location /shm → fastcgi_pass core:9082 (REST API)
Core контейнер:
  ├── shm-server.pl  :9082 — FastCGI (REST API)
  ├── ws-server.pl   :9083 — WebSocket (Perl, IO::Select)
  └── DataNotify     → Redis PUBLISH при любом изменении в БД
Redis:
  └── канал shm:events — ws-server подписан, пушит клиентам
```

Задержка: **< 200мс** от изменения в БД до WebSocket.

## Env переменные

| Переменная | Контейнер | Значение | Описание |
|-----------|-----------|---------|----------|
| `REDIS_HOST` | core, spool | `redis` | Хост Redis |
| `REDIS_PORT` | core, spool | `6379` | Порт Redis |
| `WS_PORT` | core | `9083` | Порт WebSocket сервера |
| `PERL5OPT` | core | `-MLocal::ws_init` | Автозагрузка DataNotify |
