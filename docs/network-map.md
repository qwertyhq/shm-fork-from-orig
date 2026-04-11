# Сетевая карта

## Общая схема

```
                         ИНТЕРНЕТ
                            │
                   ┌────────┴────────┐
                   │  DNS (Cloudflare) │
                   └────────┬────────┘
                            │
              ┌─────────────┴─────────────┐
              │  Выходная нода             │
              │  64.112.124.5              │
              │  Caddy :443 (TLS)          │
              │  socat :3000, :2222         │
              │  NetBird: 100.118.189.81   │
              └─────────────┬─────────────┘
                            │ WireGuard (NetBird mesh, ~36ms)
              ┌─────────────┴─────────────┐
              │  Дедик OVH (Proxmox)       │
              │  79.137.69.236 (vmbr0)     │
              │  10.10.10.1 (vmbr1)        │
              │  Caddy :8080 (HTTP router) │
              │  NetBird: 100.118.112.136  │
              │  Docker: monitoring stack  │
              └─────────────┬─────────────┘
                            │ vmbr1 (10.10.10.0/24, NAT)
          ┌─────────┬───────┴───────┬─────────┐
          │         │               │         │
     ┌────┴────┐ ┌──┴───┐ ┌───┴───┐ ┌──┴──┐
     │ VM 100  │ │VM 101│ │VM 102 │ │LXC  │
     │  shm    │ │remna │ │ wbap  │ │ pbs │
     │.10.10.10│ │.10.20│ │.10.30 │ │.10.40│
     │         │ │      │ │       │ │     │
     │ Docker: │ │Docker│ │Docker:│ │ PBS │
     │ api     │ │remna │ │ wbap  │ │     │
     │ core    │ │ wave │ │ pg16  │ │     │
     │ spool   │ │pg17  │ │       │ │     │
     │ mysql   │ │valkey│ │       │ │     │
     │ redis   │ │sub-  │ │       │ │     │
     │ admin   │ │page  │ │       │ │     │
     │ client  │ │      │ │       │ │     │
     │ webdav  │ │      │ │       │ │     │
     └─────────┘ └──────┘ └───────┘ └─────┘
```

## Маршрут трафика для каждого домена

```
z-hq.com (WBAP):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.30:42424

admin.ev-agency.io (SHM Admin):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.10:8081

bill.ev-agency.io (SHM Client):
  клиент → Cloudflare → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.10:8082

p.z-hq.com (Remnawave Panel):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.20:3000
  (Caddy добавляет X-Forwarded-Proto: https)

nl.ev-agency.io (Subscription):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.20:3010

dro.ev-agency.io (PHP redirect + payment proxy):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 10.10.10.20:8090

status.z-hq.com (Kuma):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 127.0.0.1:4001

g.z-hq.com (Grafana):
  клиент → 64.112.124.5:443 → NetBird → :8080 → 127.0.0.1:3456
```

## Маршрут для Remnawave нод

```
Remnawave нода (напр. 144.31.178.179):
  нода ← 64.112.124.5:3000 (socat) ← NetBird ← дедик iptables ← 10.10.10.20:3000
  (панель подключается К нодам, не наоборот)
```

## Внутренние порты VM

### VM 100 (SHM) — 10.10.10.10
| Порт | Сервис |
|------|--------|
| 80 | api (nginx → FastCGI + WebSocket/SSE) |
| 8081 | admin UI |
| 8082 | client UI |
| 8083 | phpMyAdmin |
| 8088 | WebDAV |
| 9100 | Node Exporter |

### VM 101 (Remna) — 10.10.10.20
| Порт | Сервис |
|------|--------|
| 3000 | Remnawave API |
| 3001 | Remnawave metrics |
| 3010 | Subscription page |
| 6767 | PostgreSQL |
| 8090 | dro-php (PHP-Apache: redirect + payment proxy) |
| 9100 | Node Exporter |

### VM 102 (WBAP) — 10.10.10.30
| Порт | Сервис |
|------|--------|
| 42424 | WBAP app |
| 9100 | Node Exporter |

### LXC 103 (PBS) — 10.10.10.40
| Порт | Сервис |
|------|--------|
| 8007 | PBS Web UI |

### Хост
| Порт | Сервис |
|------|--------|
| 8080 | Caddy (HTTP router) |
| 4001 | Uptime Kuma |
| 3456 | Grafana |
| 9100 | Node Exporter |
| 9115 | Blackbox Exporter |
| 9191 | Prometheus |
| 8006 | Proxmox Web UI |
| 22 | SSH |
| 9874 | AI Support Bot (Telegram) |
| 29899/udp | NetBird |
