# Восстановление Claude Code на новом ПК

Полная инструкция для восстановления рабочего окружения Claude Code с мака.

---

## 1. Установка Claude Code

```bash
# Установи Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Проверь
claude --version

# Авторизуйся
claude auth login
```

---

## 2. Установка плагинов

Открой Claude Code и установи все 11 плагинов:

```bash
claude plugins install superpowers
claude plugins install context7
claude plugins install playwright
claude plugins install serena
claude plugins install frontend-design
claude plugins install code-review
claude plugins install typescript-lsp
claude plugins install claude-md-management
claude plugins install security-guidance
claude plugins install figma
claude plugins install claude-code-setup
```

---

## 3. Глобальные настройки (~/.claude/settings.json)

Создай файл `~/.claude/settings.json` с базовой структурой. Пермишены будут накапливаться по мере работы, но основные настройки:

```json
{
  "permissions": {
    "allow": [
      "WebSearch",
      "Read(//home/USERNAME/**)",
      "Read(//tmp/**)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(git checkout:*)",
      "Bash(git fetch:*)",
      "Bash(git merge:*)",
      "Bash(git stash:*)",
      "Bash(git log:*)",
      "Bash(git reset:*)",
      "Bash(gh pr:*)",
      "Bash(gh issue:*)",
      "Bash(gh api:*)",
      "Bash(gh repo:*)",
      "Bash(gh auth:*)",
      "Bash(gh run:*)",
      "Bash(gh release:*)",
      "Bash(gh gist:*)",
      "Bash(gh search:*)",
      "Bash(docker compose:*)",
      "Bash(docker exec:*)",
      "Bash(docker cp:*)",
      "Bash(docker stats:*)",
      "Bash(docker kill:*)",
      "Bash(docker rm:*)",
      "Bash(npm run:*)",
      "Bash(npm install:*)",
      "Bash(npm ls:*)",
      "Bash(npm list:*)",
      "Bash(npx tsc:*)",
      "Bash(npx eslint:*)",
      "Bash(npx prettier:*)",
      "Bash(npx vite:*)",
      "Bash(npx ts-node:*)",
      "Bash(pnpm install:*)",
      "Bash(pnpm dev:*)",
      "Bash(pnpm lint:*)",
      "Bash(pnpm build:*)",
      "Bash(pnpm exec:*)",
      "Bash(yarn install:*)",
      "Bash(yarn build:*)",
      "Bash(yarn lint:*)",
      "Bash(yarn test:*)",
      "Bash(yarn add:*)",
      "Bash(yarn remove:*)",
      "Bash(python3 -c:*)",
      "Bash(python3 -m json.tool)",
      "Bash(pip3 install:*)",
      "Bash(node -e:*)",
      "Bash(claude --version)",
      "Bash(claude mcp:*)",
      "Bash(ssh -o:*)",
      "Bash(sshpass -p:*)",
      "Bash(colima status:*)",
      "Bash(colima list:*)",
      "Bash(brew list:*)",
      "Bash(brew install:*)",
      "Bash(kubectl get:*)",
      "Bash(kubectl logs:*)",
      "Bash(kubectl exec:*)",
      "Bash(for ns:*)",
      "Bash(for dir:*)",
      "Bash(for commit:*)",
      "Bash(done)",
      "Bash(sort -k1 -h)",
      "Bash(grep -v \"^$\")",
      "Bash(python3 -c \"import sys,json:*)",
      "Skill(update-config)",
      "Skill(update-config:*)",
      "mcp__plugin_context7_context7__resolve-library-id",
      "mcp__plugin_context7_context7__query-docs",
      "mcp__plugin_playwright_playwright__browser_navigate",
      "mcp__plugin_playwright_playwright__browser_take_screenshot",
      "mcp__plugin_playwright_playwright__browser_click",
      "mcp__plugin_playwright_playwright__browser_fill_form",
      "mcp__plugin_playwright_playwright__browser_press_key",
      "mcp__plugin_playwright_playwright__browser_wait_for",
      "mcp__plugin_playwright_playwright__browser_snapshot",
      "mcp__plugin_playwright_playwright__browser_console_messages",
      "mcp__plugin_playwright_playwright__browser_network_requests",
      "mcp__plugin_playwright_playwright__browser_evaluate",
      "mcp__plugin_serena_serena__list_dir",
      "mcp__plugin_serena_serena__activate_project",
      "mcp__plugin_serena_serena__read_file",
      "mcp__plugin_serena_serena__find_file",
      "mcp__plugin_serena_serena__get_symbols_overview",
      "mcp__plugin_serena_serena__execute_shell_command",
      "mcp__plugin_serena_serena__write_memory",
      "mcp__plugin_serena_serena__read_memory",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:raw.githubusercontent.com)",
      "WebFetch(domain:hub.docker.com)",
      "WebFetch(domain:docs.remnawave.com)",
      "WebFetch(domain:gist.github.com)",
      "WebFetch(domain:gist.githubusercontent.com)",
      "WebFetch(domain:developers.cloudflare.com)",
      "WebFetch(domain:community.cloudflare.com)"
    ]
  },
  "model": "claude-opus-4-6[1m]",
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "serena@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "figma@claude-plugins-official": true,
    "claude-code-setup@claude-plugins-official": true
  },
  "effortLevel": "max"
}
```

> **ВАЖНО**: Замени `USERNAME` на свой юзернейм в новой системе. Пути `/Users/qwertyhq/` станут другими.

---

## 4. Клонирование репозиториев

```bash
mkdir -p ~/code && cd ~/code

# Основные репы
git clone git@github.com:YOUR_USER/shm-fork-from-orig.git
git clone git@github.com:YOUR_USER/wbap.git
git clone git@github.com:YOUR_USER/remna-configs.git
git clone git@github.com:YOUR_USER/ai-bot.git
git clone git@github.com:YOUR_USER/wbap_v2.git
git clone git@github.com:YOUR_USER/mtbolt.git
```

---

## 5. Проектные настройки (.claude/)

### shm-fork-from-orig/.claude/settings.json

```json
{
  "permissions": {
    "allow": [
      "Bash(perl -c prod-files/realtime-server.pl)",
      "Bash(docker-compose -f contributing/docker-compose.yml ps)",
      "Bash(docker exec:*)",
      "Bash(docker cp:*)",
      "Read(//PATH_TO/shm-fork-from-orig/**)",
      "Bash(sshpass -p:*)",
      "Bash(ssh -o:*)",
      "WebFetch(domain:blocklist.rkn.gov.ru)",
      "WebFetch(domain:eais.rkn.gov.ru)",
      "WebFetch(domain:who.is)",
      "WebFetch(domain:hub.docker.com)",
      "WebFetch(domain:raw.githubusercontent.com)"
    ],
    "additionalDirectories": [
      "/tmp"
    ]
  },
  "model": "claude-opus-4-6[1m]"
}
```

### shm-fork-from-orig/.claude/settings.local.json

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(npx eslint:*)",
      "Bash(docker compose:*)",
      "Bash(brew install:*)",
      "Bash(git log:*)",
      "Bash(git fetch:*)",
      "Bash(git merge:*)",
      "Bash(git stash:*)",
      "Bash(git push:*)",
      "Bash(gh pr:*)"
    ],
    "deny": [
      "Bash(curl *)",
      "Read(./.env)"
    ]
  },
  "model": "claude-opus-4-6[1m]"
}
```

### ai-bot/.claude/settings.json

```json
{
  "permissions": {
    "allow": [
      "Bash(git -C ~/code/ai-bot log --oneline -20)",
      "Bash(./node_modules/.bin/tsc --noEmit)",
      "Bash(npm run:*)",
      "Bash(npm install:*)",
      "Bash(npx ts-node:*)"
    ]
  }
}
```

---

## 6. Память (Memory Files)

Создай структуру памяти. Claude Code создаёт директории автоматически при первом запуске в каждом проекте, но ты можешь предсоздать ключевые файлы.

### ~/.claude/projects/-PATH-TO-shm-fork-from-orig/memory/MEMORY.md

```markdown
# Memory Index

- [feedback_no_coauthor.md](feedback_no_coauthor.md) — Never add Co-Authored-By or AI attribution to git commits
- [feedback_docker_only.md](feedback_docker_only.md) — WBAP is Docker-only development, never run npm/pnpm locally
- [feedback_api_wait.md](feedback_api_wait.md) — Don't connect wbap_v2 to APIs without user's guidance
- [project_shm_overview.md](project_shm_overview.md) — 3-repo workspace: SHM + WBAP + remna-configs
- [project_migration_dedik.md](project_migration_dedik.md) — Миграция на дедик OVH
```

### feedback_no_coauthor.md

```markdown
---
name: No co-author in commits
description: Never add Co-Authored-By or any AI attribution to git commits
type: feedback
---

Never add "Co-Authored-By" or any AI/Claude attribution to git commit messages.

**Why:** User explicitly requested this — they don't want AI authorship visible in commits.

**How to apply:** When making git commits, never append Co-Authored-By lines. Just the commit message itself.
```

### feedback_docker_only.md

```markdown
---
name: Docker-only development
description: WBAP development is Docker-only — never run npm/pnpm locally, always use docker compose
type: feedback
---

WBAP development is Docker-only. Never suggest running npm/pnpm commands locally.

**Why:** The user does not have node/npm set up locally. All development and builds go through Docker containers.

**How to apply:** Use `docker compose -f docker-compose.dev.yml up -d` for dev (HMR via volume mount), `docker compose up -d --build` for production.
```

### feedback_api_wait.md

```markdown
---
name: Wait for API instructions
description: Don't connect wbap_v2 to real APIs without user's explicit guidance
type: feedback
---

When connecting wbap_v2 to real SHM/Remnawave APIs, wait for the user's explicit instructions before proceeding.

**Why:** User wants to guide the API integration themselves.

**How to apply:** Can proceed with i18n, PWA, Docker, polish independently. But for API client, auth flow, and data fetching — ask first.
```

---

## 7. CLAUDE.md файлы (уже в репах)

Эти файлы закоммичены в репозитории, они приедут с `git clone`:
- `shm-fork-from-orig/CLAUDE.md` — 488 строк, полная архитектура SHM
- `wbap/CLAUDE.md` — 272 строки, React/TS фронтенд гайд
- `remna-configs/CLAUDE.md` — 130 строк, VPN конфигурация

---

## 8. Инфраструктура — дедик OVH и серверы

### Архитектура

```
Клиент → Выходная нода (64.112.124.5:443, Caddy TLS)
       → NetBird WireGuard mesh (~36ms)
       → Дедик OVH (79.137.69.236, Caddy HTTP :8080)
       → VM на Proxmox (10.10.10.0/24 vmbr1)
```

Дедик невидим из интернета — порты 80/443 не слушают.
При блокировке IP выходной ноды — меняешь VPS за 5 минут (Caddy + NetBird).

### Серверы

| Сервер | IP | User | Auth | Роль |
|--------|----|------|------|------|
| Дедик OVH (Proxmox) | 79.137.69.236 | root | SSH key (ed25519 Termius) | Все сервисы, Ryzen 7 9700X, 64GB RAM |
| Proxmox Web UI | 79.137.69.236:8006 | root@pam | — | Управление VM |
| Выходная нода | 64.112.124.5 | root | SSH key + пароль `4mATe0QmC7j2` | Caddy TLS + socat |
| Нода Estonia | 144.31.178.179 | root | пароль `81yUomu0xJk2` | Remnawave node |
| PBS Web UI | 10.10.10.40:8007 | root@pam | `xuRzDuf#3jzPOE` | Бэкапы |
| Grafana | g.z-hq.com | admin | `ui0zSf&25ww8Lb` | Мониторинг |
| Remnawave Panel | p.z-hq.com | — | Caddy auth: `5FwmrKJrrB4Fnyny8Hwd` | VPN панель |

### NetBird mesh

| Сервер | NetBird IP |
|--------|-----------|
| Дедик | 100.118.112.136 |
| Выходная нода | 100.118.189.81 |

Setup key: `918C4643-0868-48BF-B251-ED18FF179D7D`

```bash
# Установка NetBird
curl -fsSL https://pkgs.netbird.io/install.sh | sh
netbird up --setup-key 918C4643-0868-48BF-B251-ED18FF179D7D
```

### VM на Proxmox

| ID | Имя | IP | CPU/RAM/Диск | Сервисы |
|----|-----|----|-------------|---------|
| 100 | shm | 10.10.10.10 | 2/4GB/30GB | api, core, spool, mysql, redis, admin, client, webdav, phpmyadmin |
| 101 | remna | 10.10.10.20 | 2/4GB/20GB | remnawave backend, postgres:17, valkey, subscription-page, dro-php |
| 102 | wbap | 10.10.10.30 | 1/2GB/10GB | wbap app + postgres:16 |
| 103 (LXC) | pbs | 10.10.10.40 | 1/2GB/8GB | Proxmox Backup Server |

### Домены → маршруты

| Домен | Сервис | Куда проксируется |
|-------|--------|-------------------|
| z-hq.com | WBAP | 10.10.10.30:42424 |
| admin.ev-agency.io | SHM Admin | 10.10.10.10:8081 |
| bill.ev-agency.io | SHM Client (Cloudflare proxy) | 10.10.10.10:8082 |
| webdav.ev-agency.io | SHM WebDAV | 10.10.10.10:8088 |
| p.z-hq.com | Remnawave Panel | 10.10.10.20:3000 |
| nl.ev-agency.io | Subscription Page | 10.10.10.20:3010 |
| dro.ev-agency.io | PHP redirect + платёжный прокси | 10.10.10.20:8090 |
| status.z-hq.com | Uptime Kuma | 127.0.0.1:4001 |
| g.z-hq.com | Grafana | 127.0.0.1:3456 |

### Сервисы на хосте (Docker)

- Caddy (:8080) — HTTP маршрутизация по Host header
- Uptime Kuma (:4001)
- Prometheus (:9191) + Node Exporter (:9100) + Blackbox Exporter (:9115)
- Grafana (:3456)
- AI Support Bot (:9874, Telegram bot)

### Бэкапы

- **ZFS snapshots**: каждые 15 мин, хранит 96 шт (24ч), cron `/etc/cron.d/zfs-snapshots`
- **PBS**: ежедневно 4:00, retention: 7д + 4нед + 3мес, инкрементальные с дедупликацией (~5.5GB)

### Мониторинг & алерты

- Node Exporter на хосте + 3 VM → Prometheus → Grafana
- Blackbox Exporter: HTTP health checks всех сервисов
- Grafana дашборды: `Infrastructure Overview` (`/d/infra-main`), `Dedik Full Metrics` (`/d/dedik-full`)
- Telegram алерты:
  - Grafana (тред 151154): Service Down, High CPU/RAM >90%, Disk Full >85%
  - fail2ban (тред 70318): дайджест банов каждые 30 мин
  - Remnawave (треды 15554/28416): создание/блокировка пользователей, статус нод

### Безопасность

- fail2ban: SSH brute-force на дедике и выходной ноде (5 попыток → бан 1ч)
- iptables дедик: chain `NETBIRD-SAFETY` на vmbr0 (только 22, 8006, 51820, ICMP)
- iptables выходная нода: chain `EXIT-FW` на eth0 (только 22, 80, 443, 3000, 2222, 51820, ICMP)

### Порты через выходную ноду (socat → NetBird)

| Порт | Назначение | systemd unit |
|------|-----------|--------------|
| 3000 | Remnawave ноды | socat-remna-3000.service |
| 2222 | Remnawave SSH | socat-remna-2222.service |

### Caddyfile — выходная нода (64.112.124.5)

`/etc/caddy/Caddyfile` — все домены проксируются одинаково:
```
домен.com {
    reverse_proxy 100.118.112.136:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

### Caddyfile — дедик (:8080)

`/etc/caddy/Caddyfile` — auto_https off, роутинг по `@host` матчерам:
- Remnawave panel: обязательно `header_up X-Forwarded-Proto https` (ProxyCheckMiddleware)
- WBAP: `/telegram-web-app.js` → proxy telegram.org, `/sse` → SHM API

### SSH ключи

Скопируй SSH ключи с мака:
```bash
scp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub NEW_PC:~/.ssh/
```

Ключи для серверов хранились на маке в `/tmp/` — их надо пересоздать или скопировать:
- Дедик OVH: ed25519 (Generated By Termius)
- Выходная нода: тот же ed25519
- Дедик → VM: RSA `/root/.ssh/id_rsa`

### SHM SSH сервер (server_id=18)

- host: `10.10.10.10` (VM SHM)
- transport: ssh
- key_id: 14 (ed25519, сгенерирован SHM)
- api.host: `https://p.z-hq.com` (Remnawave API)

### Ключевые особенности

- Remnawave ProxyCheckMiddleware: требует `X-Forwarded-Proto: https` — subscription page пропатчен через Docker volume mount
- Remnawave notification env (v2.7+): формат `TELEGRAM_NOTIFY_USERS=chat_id:thread_id`
- bill.ev-agency.io через Cloudflare proxy
- После рестарта Remnawave — подождать 15-20 сек для синхронизации нод (~976 users, ~3 сек)
- 3 ACTIVE пользователя (452, 1847, 8633) без storage записей — старые, не починить

### Типовые операции

```bash
# SSH на дедик
ssh root@79.137.69.236

# SSH на VM (с дедика)
ssh root@10.10.10.10   # SHM
ssh root@10.10.10.20   # Remna
ssh root@10.10.10.30   # WBAP

# Обновить SHM
ssh root@10.10.10.10 "cd /opt/shm && docker compose pull && docker compose up -d"

# Обновить Remnawave
ssh root@10.10.10.20 "cd /opt/remnawave && docker compose pull && docker compose up -d"

# Дамп MySQL (SHM)
ssh root@10.10.10.10 'docker exec mysql mysqldump -u root -p$(grep MYSQL_ROOT_PASS /opt/shm/.env | cut -d= -f2) shm' > shm-backup.sql

# Дамп PostgreSQL (Remna)
ssh root@10.10.10.20 'docker exec remnawave-db pg_dumpall -U postgres' > remna-backup.sql

# Дамп PostgreSQL (WBAP)
ssh root@10.10.10.30 'docker exec wbap-postgres-1 pg_dumpall -U wbap' > wbap-backup.sql

# Проверка всех VM
for ip in 10.10.10.10 10.10.10.20 10.10.10.30; do
  ssh root@$ip 'hostname; docker ps --format "{{.Names}}: {{.Status}}"'
done

# Замена выходной ноды (при блокировке) — 5 минут:
# 1. Новый VPS + NetBird + Caddy + socat
# 2. DNS всех доменов → новый IP
```

---

## 9. Зависимости системы

```bash
# Основные
brew install sshpass git gh docker colima
# или на Linux:
# apt install sshpass git docker.io docker-compose
# snap install gh

# Node.js (для ai-bot и локальных тулов)
# Через nvm или brew
brew install node

# Perl (для SHM тестов, опционально — всё через Docker)
# brew install perl

# Python3 (для json-парсинга в CLI)
# Обычно уже есть
```

---

## 10. Docker окружение

```bash
# macOS: Colima (вместо Docker Desktop)
brew install colima docker docker-compose
colima start --cpu 4 --memory 8

# Linux: Docker напрямую
# apt install docker.io docker-compose-plugin

# Запуск SHM dev-окружения
cd ~/code/shm-fork-from-orig
docker-compose -f contributing/docker-compose.yml up -d

# Запуск WBAP dev-окружения
cd ~/code/wbap
docker compose -f docker-compose.dev.yml up -d
```

---

## 11. Superpowers плагин (локальная копия)

На маке есть локальная копия superpowers в `~/.claude/plugins/superpowers/`. Она устанавливается автоматически через marketplace, но если нужна кастомная версия:

```bash
cd ~/.claude/plugins/
git clone https://github.com/anthropics/claude-plugins-official.git superpowers-src
# или используй маркетплейс — плагин обновится автоматически
```

---

## 12. Чеклист после установки

- [ ] Claude Code установлен и авторизован
- [ ] Все 11 плагинов установлены
- [ ] `~/.claude/settings.json` создан с правильными путями
- [ ] Репозитории клонированы
- [ ] `.claude/` директории в репах настроены
- [ ] Memory файлы созданы
- [ ] SSH ключи скопированы
- [ ] NetBird подключен к mesh-сети
- [ ] Docker работает
- [ ] `docker-compose up` запускается в SHM и WBAP
- [ ] `claude` запускается в каждом репо без ошибок

---

## Заметки

- **Пермишены накапливаются**: при работе Claude будет спрашивать разрешения — одобренные сохраняются в `settings.json`. Со временем файл вырастет как на маке (450+ строк).
- **Модель**: `claude-opus-4-6[1m]` — Opus с 1M контекстом. Это стоит больше токенов, но даёт лучшие результаты.
- **effortLevel**: `"max"` — максимальная тщательность ответов.
- **Aleria OSINT** — отдельный проект, если нужен — клонируй отдельно, у него своя память в `~/.claude/projects/`.
