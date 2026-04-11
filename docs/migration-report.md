# Отчёт по миграции на дедик OVH

**Дата**: 2026-04-07 — 2026-04-08

## Что было

Один VPS (188.124.51.229, 6 vCPU, 12GB RAM, 74GB диск, 70% занято) — все сервисы в Docker без изоляции:
- SHM (9 контейнеров)
- Remnawave (4 контейнера + caddy-with-auth)
- WBAP (2 контейнера)
- Мониторинг (Kuma, Prometheus, Grafana)
- B2B Aleria, Security AI и другие

## Что стало

### Архитектура по гайду DigneZzZ

```
Клиент → Выходная нода (64.112.124.5:443, Caddy TLS)
       → NetBird WireGuard mesh (~36ms)
       → Дедик OVH (79.137.69.236, Caddy HTTP :8080)
       → VM/LXC на Proxmox (10.10.10.0/24)
```

- Дедик невидим из интернета (порты 80/443 закрыты)
- При блокировке РКН — меняешь выходную ноду за 5 минут
- Полная изоляция сервисов в отдельных VM

### Выполненные работы

#### Фаза 1: Установка и настройка Proxmox
- [x] Установка Proxmox VE 9 на дедик OVH (Ryzen 7 9700X, 64GB, 2x NVMe 512GB)
- [x] Настройка ZFS mirror: compression=lz4, autotrim=on, ARC limit 16GB
- [x] Приватная сеть vmbr1 (10.10.10.0/24) + NAT masquerade
- [x] Отключён enterprise repo, включён no-subscription

#### Фаза 2: Создание VM
- [x] VM 100 (shm): 2 CPU, 4GB RAM, 30GB — Ubuntu 24.04 cloud-init + Docker
- [x] VM 101 (remna): 2 CPU, 4GB RAM, 20GB — Ubuntu 24.04 cloud-init + Docker
- [x] VM 102 (wbap): 1 CPU, 2GB RAM, 10GB — Ubuntu 24.04 cloud-init + Docker
- [x] LXC 103 (pbs): 1 CPU, 2GB RAM, 8GB — Debian 12 + Proxmox Backup Server
- [x] CPU type: host (для поддержки x86-64-v2)

#### Фаза 3: Миграция данных
- [x] SHM: mysqldump (361MB) → restore, 7730 users, 3992 storage records
- [x] SHM: data volume (pay_systems + 171 template файлов)
- [x] Remnawave: pg_dumpall (13MB) → restore
- [x] WBAP: pg_dumpall (38MB) → restore
- [x] Uptime Kuma: rsync /srv/uptime (364MB)

#### Фаза 4: NetBird + Выходная нода
- [x] Регистрация NetBird cloud (P2P mesh)
- [x] Установка NetBird agent на дедик (100.118.112.136) и выходную ноду (100.118.189.81)
- [x] Caddy на дедике: HTTP :8080, маршрутизация по Host header
- [x] Caddy на выходной ноде: HTTPS :443, TLS termination, proxy через NetBird
- [x] socat проброс портов 3000, 2222 для Remnawave нод (systemd units)

#### Фаза 5: Переключение DNS
- [x] z-hq.com → 64.112.124.5 (выходная нода)
- [x] admin.ev-agency.io → 64.112.124.5
- [x] bill.ev-agency.io → 64.112.124.5 (через Cloudflare proxy)
- [x] webdav.ev-agency.io → 64.112.124.5
- [x] p.z-hq.com → 64.112.124.5
- [x] nl.ev-agency.io → 64.112.124.5
- [x] status.z-hq.com → 64.112.124.5
- [x] g.z-hq.com → 64.112.124.5

#### Фаза 6: Мониторинг
- [x] Node Exporter на хост + 3 VM → Prometheus
- [x] Blackbox Exporter: HTTP health checks всех сервисов
- [x] Grafana: Services Overview дашборд (статус, response time, CPU, RAM, диск)
- [x] Grafana datasource: Prometheus подключён

#### Фаза 7: Бэкапы
- [x] ZFS snapshots: каждые 15 мин, хранит 96 штук (24 часа)
- [x] PBS (Proxmox Backup Server): LXC 103, ежедневно 4:00
- [x] PBS retention: 7 дневных + 4 недельных + 3 месячных
- [x] PBS дедупликация: 60GB данных → 5.5GB на диске
- [x] Тестовый бэкап: все 3 VM за ~50 секунд

#### Фаза 8: Persistence
- [x] iptables-persistent на дедике
- [x] socat → systemd units на выходной ноде
- [x] Docker restart policies: unless-stopped / always
- [x] VM/LXC: onboot=1

### Исправленные проблемы

| Проблема | Решение |
|----------|---------|
| MySQL: "CPU does not support x86-64-v2" | Изменён CPU type VM на `host` |
| Remnawave ProxyCheckMiddleware блокирует запросы | Caddy на дедике: `header_up X-Forwarded-Proto https` |
| Subscription page не отвечает | Пропатчен ProxyCheckMiddleware через Docker volume mount |
| WBAP nginx кешировал старый IP (188.124.51.229) | Рестарт контейнера для перерезолва DNS |
| telegram-web-app.js не найден | Добавлен proxy в Caddy: z-hq.com → telegram.org |
| iptables DNAT на 3000 ломал NAT из VM к нодам | Удалены DNAT правила, используется socat через выходную ноду |
| Grafana 502 через выходную ноду | Очищены кешированные staging сертификаты Caddy |
| Remnawave ноды offline | Запущены контейнеры на нодах + убрана блокирующая iptables DROP rule |

#### Фаза 9: Дополнительные исправления (2026-04-08)
- [x] SHM server host обновлён с 188.124.51.229 на 10.10.10.10 (SSH шаблон remnawave-2.tpl)
- [x] SHM SSH ключ (id=14) добавлен на VM SHM
- [x] dro.ev-agency.io — PHP редирект подписок + платёжный прокси (контейнер dro-php на VM remna :8090)
- [x] WBAP рестартнут для перерезолва DNS (nginx кешировал старый IP 188.124.51.229)
- [x] telegram-web-app.js proxy добавлен в Caddy на дедике (z-hq.com → telegram.org)
- [x] Blackbox exporter: отдельные модули для Remnawave (http_remnawave с X-Forwarded-Proto)
- [x] Grafana дашборд Infrastructure Overview — 15 панелей
- [x] Remnawave ноды рестартнуты для синхронизации пользователей после миграции БД
- [x] Prometheus TSDB очищена от дубликатов

#### Фаза 10: Безопасность и алерты (2026-04-08)
- [x] fail2ban на дедике и выходной ноде (SSH, 5 попыток → бан 1ч)
- [x] fail2ban Telegram дайджест каждые 30 мин → тред 70318
- [x] Firewall iptables на дедике (vmbr0: 22, 8006, 51820, ICMP)
- [x] Firewall iptables на выходной ноде (eth0: 22, 80, 443, 3000, 2222, 51820, ICMP)
- [x] Grafana Telegram алерты → тред 151154 (Service Down, Host Down, CPU/RAM/Disk)
- [x] Grafana дашборд Dedik Full Metrics (CPU per core, ZFS ARC, NVMe I/O, network, conntrack)
- [x] ZFS snapshots cron починен
- [x] Починена storage запись для us_id=8569 (vpn_mrzb_8569)
- [x] Бэкап старого VPS на дедик (3.5GB файлы + DB дампы)
- [x] hq-vpn.com домен добавлен через выходную ноду
- [x] Remnawave Telegram OAuth настроен в БД
- [x] Remnawave notification env обновлён на формат v2.7+ (TELEGRAM_NOTIFY_USERS=chat_id:thread_id)
- [x] Torrent blocker включён в Remnawave plugin

### Что НЕ перенесено

- B2B Aleria (остаётся на старом VPS)
- Security AI (отложено)
- Firewall nftables на дедике (решили не делать — дедик скрыт)

### Свободные ресурсы

- CPU: 11 из 16 потоков
- RAM: ~54GB из 64GB
- Диск: ~350GB из 420GB ZFS
