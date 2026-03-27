# SHM WebSocket — Real-Time API

## Что это

WebSocket сервер встроен прямо в SHM. Когда в биллинге меняются данные — ваш фронтенд получает сигнал мгновенно (< 200мс). Без polling, без BFF, без дополнительных сервисов.

## Как подключиться

```
wss://ваш-shm-домен/ws?session_id=СЕССИЯ_ЮЗЕРА
```

Используется та же `session_id` что и для REST API. Без валидной сессии — 401.

## Минимальный пример (10 строк)

```javascript
const ws = new WebSocket('wss://admin.example.com/ws?session_id=' + sessionId);

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === 'balance_update')  fetchUser();
  if (msg.type === 'service_update')  fetchServices();
};

ws.onclose = () => setTimeout(connect, 3000);
```

## Типы событий

| Тип | Когда | Что делать |
|-----|-------|-----------|
| `connected` | Подключение установлено | Ничего, всё ок |
| `balance_update` | Оплата, списание, бонус, изменение профиля | Запросить `GET /user` |
| `service_update` | Услуга создана/удалена/изменена | Запросить `GET /user/service` |
| `service_status` | Активация/блокировка услуги | Запросить `GET /user/service` |
| `system_notification` | Задача spool обработана | По желанию |

## Формат сообщения

```json
{
  "type": "balance_update",
  "data": {
    "action": "update",
    "table": "users"
  },
  "timestamp": 1774615587
}
```

Сами данные (баланс, список услуг) в сообщении НЕ приходят — только сигнал "обновилось". Данные запрашиваете обычным REST.

## React hook

```typescript
import { useEffect, useRef } from 'react';

function useSHMWebSocket(sessionId: string) {
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    function connect() {
      const ws = new WebSocket(
        `wss://admin.example.com/ws?session_id=${sessionId}`
      );

      ws.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        if (msg.type === 'balance_update') fetchUser();
        if (msg.type === 'service_update') fetchServices();
      };

      // Не реконнектиться при 4000 (too many connections)
      ws.onclose = (e) => {
        if (e.code !== 4000) setTimeout(connect, 3000);
      };

      wsRef.current = ws;
    }

    connect();
    return () => wsRef.current?.close();
  }, [sessionId]);
}
```

## Как проверить

В консоли браузера (F12):
```javascript
const ws = new WebSocket('wss://admin.example.com/ws?session_id=ВАША_СЕССИЯ');
ws.onmessage = (e) => console.log(JSON.parse(e.data));
// Измените баланс юзера в админке — в консоли появится событие
```

С сервера:
```bash
# Должен вернуть 401 (без сессии)
curl -i -H "Upgrade: websocket" -H "Connection: upgrade" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGVzdA==" \
  http://localhost/ws
```

## Архитектура

```
Браузер / Telegram Web App
  ↕ WebSocket (wss://shm-domain/ws?session_id=xxx)
Nginx (api контейнер)
  → location /ws → proxy_pass core:9083
Core контейнер:
  ├── shm-server.pl :9082 — REST API (FastCGI)
  └── ws-server.pl  :9083 — WebSocket (Perl)
      ├── Авторизация через MySQL (таблица sessions)
      ├── Redis SUBSCRIBE (канал shm:events)
      └── Push клиентам при получении события
```

Новых контейнеров нет. ws-server.pl запускается рядом с shm-server.pl внутри core.

## Ограничения

- 5 соединений на юзера (6-е отклоняется с кодом 4000)
- Авторизация только по session_id (3 дня жизни)
- Каждый юзер видит только свои события

## Настройка (docker-compose)

### Что нужно в SHM docker-compose:

**api контейнер** — nginx проксирует `/ws`:
```yaml
api:
  volumes:
    - "./prod-files/entry-api.sh:/entry.sh"
    - "./prod-files/ws-location.conf:/etc/nginx/ws-location.conf"
```

**core контейнер** — ws-server запускается при старте:
```yaml
core:
  environment:
    REDIS_HOST: redis
    REDIS_PORT: 6379
  volumes:
    - "./prod-files/ws-server.pl:/app/bin/ws-server.pl"
    - "./prod-files/entry-core.sh:/entry.sh"
    - "./prod-files/WebSocketNotify.pm:/app/lib/Local/WebSocketNotify.pm"
    - "./prod-files/DataNotify.pm:/app/lib/Local/DataNotify.pm"
    - "./prod-files/ws_init.pl:/app/lib/Local/ws_init.pm"
```

**spool контейнер** — публикует события в Redis:
```yaml
spool:
  environment:
    REDIS_HOST: redis
    REDIS_PORT: 6379
  volumes:
    - "./prod-files/spool.pl:/app/bin/spool.pl"
    - "./prod-files/WebSocketNotify.pm:/app/lib/Local/WebSocketNotify.pm"
    - "./prod-files/DataNotify.pm:/app/lib/Local/DataNotify.pm"
```

### Что нужно на фронтенде:

```env
VITE_ENABLE_WEBSOCKET=true
VITE_WS_URL=wss://ваш-shm-домен/ws
```

## Файлы prod-files

| Файл | Назначение |
|------|-----------|
| `ws-server.pl` | Perl WebSocket сервер (IO::Select, без CPAN зависимостей) |
| `entry-core.sh` | Запускает ws-server рядом с FastCGI |
| `entry-api.sh` | Инжектит location /ws в nginx |
| `ws-location.conf` | Nginx location для WebSocket proxy |
| `DataNotify.pm` | Хуки на _set/_add/_delete → Redis PUBLISH |
| `WebSocketNotify.pm` | Модуль публикации в Redis |
| `ws_init.pl` | Автозагрузка DataNotify для core (через PERL5OPT) |
| `spool.pl` | Override spool с загрузкой DataNotify |
