# Известные проблемы и TODO

## Активные проблемы

### 1. Remnawave Subscription Page — пропатчен ProxyCheckMiddleware
**Что**: Middleware в subscription page закрывает TCP соединение если нет `X-Forwarded-Proto: https`. Пропатчен через Docker volume mount — файл `/opt/remnawave/patches/proxy-check.middleware.js` подменяет оригинальный.
**Риск**: При обновлении Docker образа `remnawave/subscription-page` патч может перестать работать если изменится путь к файлу.
**Решение**: После обновления проверить что subscription page отвечает. Если нет — обновить путь в docker-compose volume mount.

### 2. SHM BLOCK/PROLONGATE — пустой UUID для некоторых пользователей
**Что**: Шаблон `remnawave-2.tpl` при BLOCK/PROLONGATE читает UUID из SHM storage (`vpn_mrzb_{us.id}`). Для некоторых пользователей записей нет → UUID пустой → запрос падает с 404.
**Причина**: CREATE событие не сохранило UUID в storage (старая миграция с Marzban).
**Текущий статус** (2026-04-08):
- us_id=8569 — **починен** (вручную добавлен storage)
- us_id=452, 1847, 8633 — ACTIVE, но **нет в Remnawave** (старые, не починить)
- 11 BLOCK без storage — не критично, услуги уже заблокированы
- REMOVED — ретраи spool, пропадут сами
**Решение для будущих**: шаблон remnawave-2.tpl корректно пишет storage при CREATE. Проблема только с исторически пропущенными.

### 3. SSE disconnect/reconnect loop
**Что**: В логах WBAP видно постоянный цикл `SSE client connected / disconnected` для user 1.
**Причина**: Длинная цепочка (клиент → выходная нода → NetBird → дедик → SHM API) может вызывать таймауты SSE.
**Решение**: Увеличить таймауты в Caddy для SSE, или переключить на polling.

### 4. После рестарта Remnawave — нужно дождаться синхронизации нод
**Что**: После рестарта `docker restart remnawave` новые пользователи не могут подключиться пока ноды не получат обновлённый конфиг.
**Причина**: Remnawave при старте синхронизирует пользователей с нодами (~976 users, ~3 сек). До этого новые UUID неизвестны нодам.
**Решение**: Подождать 15-20 сек после рестарта. Логи покажут `Started all nodes with profile ... in XXXms`.

---

## TODO (отложено)

### Безопасность
- [x] fail2ban на дедик и выходную ноду — с Telegram дайджестом
- [x] Firewall iptables на дедике (chain NETBIRD-SAFETY) и выходной ноде (chain EXIT-FW)
- [ ] Suricata IDS — отложено (overkill для текущей архитектуры)
- [ ] Сменить SSH порт на нестандартный (22 → 22222) — отложено

### Бэкапы
- [ ] Offsite: настроить синхронизацию PBS → OVH S3 Object Storage
- [ ] Тест восстановления: проверить что VM восстанавливается из PBS

### Мониторинг
- [x] Telegram алерты из Grafana (тред 151154) — 5 правил
- [x] fail2ban Telegram дайджест (тред 70318) — каждые 30 мин
- [x] Дашборд Dedik Full Metrics (/d/dedik-full)
- [ ] Дашборд для Remnawave нод (статус, трафик)
- [ ] Мониторинг NetBird mesh (пинг между пирами)

### Инфраструктура
- [ ] Security AI — перенести на дедик
- [ ] Обновить hostname дедика и выходной ноды на читаемые
- [ ] Настроить логротацию для Caddy логов на выходной ноде
- [ ] Добавить cAdvisor для мониторинга Docker контейнеров

### Ноды Remnawave
- [x] Finland и Netherlands — подключены (были offline, запущены)
- [x] Estonia (144.31.178.179) — remnawave-node был остановлен, запущен
- [ ] RU-White Bride (185.241.195.16:443) — порт не отвечает при проверке

### dro.ev-agency.io
- [ ] PHP-Apache контейнер `dro-php` на VM remna — нет persistence, при обновлении remna docker-compose может потеряться (отдельный контейнер, не в compose)
