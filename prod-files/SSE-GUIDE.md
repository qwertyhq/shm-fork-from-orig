# SHM Real-Time Events — SSE & WebSocket

## Обзор

SHM отправляет события в реальном времени при изменении данных в базе. Поддерживаются два протокола на одном сервере (`realtime-server.pl`, порт 9083):

| | SSE | WebSocket |
|---|---|---|
| Протокол | HTTP GET, `text/event-stream` | HTTP Upgrade, binary frames |
| Направление | Сервер → клиент | Двунаправленный (используем только сервер → клиент) |
| Реконнект | Автоматический (встроен в EventSource API) | Ручной (нужен свой код) |
| Прокси | Работает через любой HTTP прокси | Требует поддержки WebSocket Upgrade |
| Рекомендация | **По умолчанию** | Fallback (если SSE недоступен) |

## Архитектура

```
                          ┌─────────────────────────────────┐
                          │         realtime-server.pl      │
  Browser ──── SSE ──────►│  :9083                          │◄──── Redis SUBSCRIBE
  Browser ──── WS ───────►│  Определяет протокол по         │      shm:events
                          │  заголовку Upgrade: websocket   │
                          └─────────────────────────────────┘
                                         ▲
                                         │ Redis PUBLISH
                          ┌──────────────┴──────────────────┐
                          │  DataNotify.pm                   │
                          │  Хуки на _set, _add, _delete     │
                          │  в Core::Sql::Data               │
                          └──────────────────────────────────┘
```

Цепочка: DB write → DataNotify.pm → Redis PUBLISH → realtime-server.pl → SSE/WS → браузер

---

## SSE (Server-Sent Events)

### Подключение

```javascript
const es = new EventSource('https://your-domain.com/sse?user_id=USER_ID');

es.onopen = () => console.log('Connected');

es.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data);
};

es.onerror = () => console.log('Reconnecting...');
// EventSource переподключается автоматически
```

### Пример ответа сервера

```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
Access-Control-Allow-Origin: *
X-Accel-Buffering: no

: ping

data: {"action":"update","table":"user_services","user_id":"1","timestamp":1774636854}

data: {"action":"create","table":"spool","user_id":"1","timestamp":1774636854}

: ping
```

---

## WebSocket

### Подключение

```javascript
const ws = new WebSocket('wss://your-domain.com/ws?user_id=USER_ID');

ws.onopen = () => console.log('Connected');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data);
  // Тот же формат JSON что и SSE
};

ws.onclose = (e) => {
  if (e.code !== 1000) {
    // Реконнект с exponential backoff
    setTimeout(() => connect(), Math.min(5000 * Math.pow(2, attempt), 60000));
  }
};
```

### Требования к прокси

```nginx
# nginx
location /ws {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

Внимание: некоторые reverse proxy (например Caddy с caddy-security плагином) могут ломать WebSocket. В таких случаях используйте SSE.

---

## Формат событий

Оба протокола отправляют одинаковый JSON:

```json
{
  "action": "create | update | delete",
  "table": "user_services",
  "user_id": "1",
  "timestamp": 1774636854
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| `action` | string | `create`, `update`, `delete` |
| `table` | string | Таблица SHM, в которой произошло изменение |
| `user_id` | string | ID пользователя |
| `timestamp` | number | Unix timestamp |

## Какие таблицы отслеживать

| Таблица | Когда срабатывает | Что делать |
|---------|-------------------|------------|
| `user_services` | Активация, блокировка, продление, смена тарифа | Перезапросить список услуг |
| `users` | Изменение баланса, профиля | Перезапросить данные пользователя |
| `pays` | Новый платёж, списание | Перезапросить баланс/историю |
| `storage` | Изменение хранилища (VPN конфиги) | Перезапросить данные хранилища |
| `spool` | Создание задачи в очереди | Можно игнорировать |

Таблицы `sessions`, `spool_history`, `configs` **не генерируют события** (отфильтрованы в DataNotify.pm).

---

## Рекомендации

### Debounce (обязательно)

SHM обрабатывает действия через spool (очередь задач). Одно действие пользователя порождает 2-4 события за 1-2 секунды:

```
user_services update  (задача создана)        +0.0с
spool create          (spool принял)           +0.005с
storage update        (spool выполнил)         +0.7с
user_services update  (финальный статус)       +1.7с
```

Без debounce первый `fetchServices()` получит старые данные. Рекомендуемый debounce — 800мс:

```javascript
const timers = {};

function onEvent(data) {
  const key = ['user_services', 'services'].includes(data.table) ? 'services' : 'user';

  clearTimeout(timers[key]);
  timers[key] = setTimeout(() => {
    if (key === 'services') fetchServices();
    else fetchUser();
  }, 800);
}
```

### Keepalive

Сервер отправляет ping каждые 30 секунд:
- **SSE:** `: ping\n\n` (SSE comment, EventSource игнорирует автоматически)
- **WS:** WebSocket ping frame (браузер отвечает pong автоматически)

Если ping не приходит 60+ секунд — соединение потеряно.

### CORS

Сервер отправляет `Access-Control-Allow-Origin: *`. SSE и WS работают cross-origin.

---

## Примеры интеграции

### React hook (SSE)

```typescript
import { useEffect, useState } from 'react';

function useSSE(userId: number, sseUrl: string) {
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    if (!userId) return;

    const es = new EventSource(`${sseUrl}?user_id=${userId}`);
    const timers: Record<string, ReturnType<typeof setTimeout>> = {};

    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);

    es.onmessage = (event) => {
      const data = JSON.parse(event.data);
      const key = ['user_services', 'services'].includes(data.table) ? 'services' : 'user';

      clearTimeout(timers[key]);
      timers[key] = setTimeout(() => {
        if (key === 'services') fetchServices();
        else fetchUser();
      }, 800);
    };

    return () => {
      Object.values(timers).forEach(clearTimeout);
      es.close();
    };
  }, [userId, sseUrl]);

  return { connected };
}
```

### Vanilla JavaScript

```html
<script>
const userId = 1;
const sseUrl = 'https://your-domain.com/sse';
const es = new EventSource(`${sseUrl}?user_id=${userId}`);
const timers = {};

es.onopen = () => {
  document.getElementById('status').textContent = 'Online';
};

es.onmessage = (event) => {
  const data = JSON.parse(event.data);
  const key = ['user_services', 'services'].includes(data.table) ? 'services' : 'user';

  clearTimeout(timers[key]);
  timers[key] = setTimeout(() => {
    if (key === 'services') fetchServices();
    else fetchUser();
  }, 800);
};

es.onerror = () => {
  document.getElementById('status').textContent = 'Reconnecting...';
};
</script>
```

### Python

```python
import requests
import json

def listen_sse(base_url, user_id):
    response = requests.get(
        f'{base_url}/sse?user_id={user_id}',
        stream=True,
        headers={'Accept': 'text/event-stream'}
    )
    for line in response.iter_lines(decode_unicode=True):
        if line.startswith('data: '):
            event = json.loads(line[6:])
            print(f"{event['action']} on {event['table']}")

listen_sse('https://your-domain.com', 1)
```

### curl (тестирование)

```bash
# SSE
curl -N https://your-domain.com/sse?user_id=1

# Отправить тестовое событие через Redis
redis-cli PUBLISH shm:events '{"action":"update","table":"users","user_id":"1","timestamp":1234567890}'
```

---

## Настройка сервера

### Docker Compose

```yaml
services:
  api:
    volumes:
      - "./prod-files/ws-location.conf:/etc/nginx/ws-location.conf"
      - "./prod-files/sse-location.conf:/etc/nginx/sse-location.conf"

  core:
    environment:
      REDIS_HOST: redis
      REDIS_PORT: 6379
      PERL5OPT: "-MLocal::ws_init"
    volumes:
      - "./prod-files/realtime-server.pl:/app/bin/realtime-server.pl"
      - "./prod-files/WebSocketNotify.pm:/app/lib/Local/WebSocketNotify.pm"
      - "./prod-files/DataNotify.pm:/app/lib/Local/DataNotify.pm"
      - "./prod-files/ws_init.pl:/app/lib/Local/ws_init.pm"
      - "./prod-files/entry-core.sh:/entry.sh"
```

### Nginx — SSE (sse-location.conf)

```nginx
location /sse {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    chunked_transfer_encoding off;
}
```

### Nginx — WebSocket (ws-location.conf)

```nginx
location /ws {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

### Caddy

```caddy
your-domain.com {
    handle /sse {
        reverse_proxy http://api:80
    }
}
```

### entry-api.sh (инжект в nginx)

```bash
# SSE
if [ -f /etc/nginx/sse-location.conf ] && ! grep -q "sse-location" /etc/nginx/nginx.conf; then
    sed -i '/location = \/shm\/healthcheck.cgi/i \        include /etc/nginx/sse-location.conf;' /etc/nginx/nginx.conf
fi

# WebSocket
if [ -f /etc/nginx/ws-location.conf ] && ! grep -q "ws-location" /etc/nginx/nginx.conf; then
    sed -i '/location = \/shm\/healthcheck.cgi/i \        include /etc/nginx/ws-location.conf;' /etc/nginx/nginx.conf
fi
```

### entry-core.sh (запуск сервера)

```bash
if [ -f /app/bin/realtime-server.pl ]; then
    perl /app/bin/realtime-server.pl &
    echo "Realtime server started on port ${WS_PORT:-9083}"
fi
```

---

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `WS_PORT` | `9083` | Порт realtime-server.pl |
| `REDIS_HOST` | `redis` | Хост Redis |
| `REDIS_PORT` | `6379` | Порт Redis |
| `WS_REDIS_CHANNEL` | `shm:events` | Канал Redis pub/sub |

## Файлы

| Файл | Назначение |
|------|------------|
| `prod-files/realtime-server.pl` | Dual-protocol сервер (SSE + WS) |
| `prod-files/sse-location.conf` | Nginx конфиг для /sse |
| `prod-files/ws-location.conf` | Nginx конфиг для /ws |
| `prod-files/entry-api.sh` | Инжект конфигов в nginx |
| `prod-files/entry-core.sh` | Запуск realtime-server |
| `prod-files/DataNotify.pm` | Хуки на DB write → Redis PUBLISH |
| `prod-files/WebSocketNotify.pm` | Redis PUBLISH модуль |
| `prod-files/ws_init.pl` | Автозагрузка DataNotify |
