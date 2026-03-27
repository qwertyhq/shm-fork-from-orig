# SHM Real-Time Events (SSE)

SHM отправляет события в реальном времени при изменении данных в базе. Используется Server-Sent Events (SSE) — стандартный HTTP протокол, работает через любой прокси.

## Подключение

```javascript
const es = new EventSource('https://your-domain.com/sse?user_id=USER_ID');

es.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data);
  // { action: "update", table: "user_services", user_id: "1", timestamp: 1774636854 }
};
```

`user_id` — ID пользователя SHM, для которого нужны события.

## Формат событий

```json
{
  "action": "create" | "update" | "delete",
  "table": "user_services" | "users" | "pays" | "storage" | "spool",
  "user_id": "1",
  "timestamp": 1774636854
}
```

| Поле | Описание |
|------|----------|
| `action` | Тип операции: `create`, `update`, `delete` |
| `table` | Таблица SHM, в которой произошло изменение |
| `user_id` | ID пользователя |
| `timestamp` | Unix timestamp события |

## Какие таблицы отслеживать

| Таблица | Когда срабатывает | Что делать |
|---------|-------------------|------------|
| `user_services` | Активация, блокировка, продление услуги | Перезапросить список услуг |
| `users` | Изменение баланса, профиля | Перезапросить данные пользователя |
| `pays` | Новый платёж | Перезапросить баланс/историю платежей |
| `storage` | Изменение хранилища (VPN конфиги и т.д.) | Перезапросить данные хранилища |
| `spool` | Создание задачи в очереди | Обычно можно игнорировать |

## Пример: React hook

```typescript
import { useEffect, useState } from 'react';

function useSSE(userId: number, sseUrl: string) {
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    if (!userId) return;

    const es = new EventSource(`${sseUrl}?user_id=${userId}`);

    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);

    es.onmessage = (event) => {
      const data = JSON.parse(event.data);

      switch (data.table) {
        case 'user_services':
        case 'services':
          // Перезапросить услуги
          break;
        case 'users':
        case 'pays':
          // Перезапросить пользователя/баланс
          break;
      }
    };

    return () => es.close();
  }, [userId, sseUrl]);

  return { connected };
}
```

## Пример: Vanilla JavaScript

```html
<script>
const userId = 1;
const es = new EventSource(`https://your-domain.com/sse?user_id=${userId}`);

es.onopen = () => document.getElementById('status').textContent = 'Online';

es.onmessage = (event) => {
  const data = JSON.parse(event.data);

  if (data.table === 'user_services') {
    // Обновить UI услуг
    fetchServices();
  }
  if (data.table === 'users' || data.table === 'pays') {
    // Обновить баланс
    fetchBalance();
  }
};

es.onerror = () => document.getElementById('status').textContent = 'Reconnecting...';
</script>
```

## Keepalive

Сервер отправляет `: ping` каждые 30 секунд. EventSource игнорирует это автоматически. Если пинг не приходит дольше 60 секунд — соединение потеряно.

## Авто-реконнект

EventSource API автоматически переподключается при обрыве. Не нужно писать свою логику реконнекта.

## Debounce

SHM отправляет несколько событий на одно действие (spool обрабатывает задачи поэтапно). Рекомендуется debounce ~800мс перед запросом данных:

```javascript
const timers = {};

function onEvent(data) {
  const category = data.table === 'user_services' ? 'services' : 'user';

  clearTimeout(timers[category]);
  timers[category] = setTimeout(() => {
    if (category === 'services') fetchServices();
    else fetchUser();
  }, 800);
}
```

Без debounce первый fetch может получить ещё старые данные (spool не успел обработать).

## Настройка на сервере

### Nginx (api контейнер)

Файл `sse-location.conf` монтируется в api контейнер:

```nginx
location /sse {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

### Caddy

```caddy
handle /sse {
    reverse_proxy http://api:80
}
```

### Docker Compose

В `api` сервисе:
```yaml
volumes:
  - "./prod-files/sse-location.conf:/etc/nginx/sse-location.conf"
```

В `core` сервисе:
```yaml
volumes:
  - "./prod-files/realtime-server.pl:/app/bin/realtime-server.pl"
```

## Протокол WebSocket (fallback)

Тот же сервер поддерживает WebSocket на том же порту. Если нужен WS:

```javascript
const ws = new WebSocket('wss://your-domain.com/ws?user_id=1');
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  // Тот же формат данных что и SSE
};
```

WebSocket требует правильной настройки прокси (Upgrade headers). SSE работает через любой HTTP прокси без дополнительной настройки.
