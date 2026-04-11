# Runbooks — типовые операции

## Выходная нода заблокирована / нужна замена

1. Купить новый VPS (любой провайдер, Ubuntu 24.04, минимум 1 CPU / 1GB RAM)
2. Установить NetBird:
```bash
curl -fsSL https://pkgs.netbird.io/install.sh | sh
netbird up --setup-key <SETUP_KEY_ИЗ_NETBIRD>
```
3. Добавить SSH ключ дедика:
```bash
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAAACAQ..." >> /root/.ssh/authorized_keys
```
4. Установить Caddy:
```bash
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```
5. Скопировать Caddyfile с текущей выходной ноды или написать по шаблону — все домены проксируются на `100.118.112.136:8080` (NetBird IP дедика)
6. Установить socat и создать systemd units для портов 3000, 2222
7. Переключить DNS всех доменов на новый IP
8. Caddy автоматически получит Let's Encrypt сертификаты

**Время**: ~5-10 минут

---

## Добавить новый домен

### На выходной ноде (64.112.124.5):
Добавить блок в `/etc/caddy/Caddyfile`:
```
newdomain.com {
    reverse_proxy 100.118.112.136:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```
```bash
caddy fmt --overwrite /etc/caddy/Caddyfile
systemctl reload caddy
```

### На дедике (79.137.69.236):
Добавить handler в `/etc/caddy/Caddyfile` внутри блока `:8080`:
```
@newdomain host newdomain.com
handle @newdomain {
    reverse_proxy 10.10.10.XX:PORT
}
```
```bash
caddy fmt --overwrite /etc/caddy/Caddyfile
systemctl reload caddy
```

### DNS:
Направить A-запись на IP выходной ноды (64.112.124.5)

---

## Восстановление VM из PBS бэкапа

```bash
# Список бэкапов
pvesm list pbs-backup

# Восстановить VM 100 (SHM) из последнего бэкапа
qmrestore pbs-backup:backup/vzdump-qemu-100-YYYY_MM_DD-HH_MM_SS.vma.zst 100 \
  --storage local-zfs --force
```

---

## Восстановление из ZFS snapshot

```bash
# Список снапшотов
zfs list -t snapshot | grep auto-

# Откатить (ОСТОРОЖНО — удалит текущие данные)
zfs rollback data/zd0@auto-YYYYMMDD-HHMM
```

---

## Создать новую VM

```bash
# На дедике
qm create 1XX --name имя --cores 2 --memory 4096 --net0 virtio,bridge=vmbr1 \
  --scsihw virtio-scsi-pci --agent enabled=1 --onboot 1 --ostype l26 --cpu host

qm set 1XX --scsi0 local-zfs:0,import-from=/tmp/ubuntu-24.04-cloud.img,size=30G
qm set 1XX --boot order=scsi0
qm set 1XX --ide2 local-zfs:cloudinit
qm set 1XX --serial0 socket --vga serial0
qm set 1XX --ipconfig0 ip=10.10.10.XX/24,gw=10.10.10.1
qm set 1XX --nameserver 1.1.1.1
qm set 1XX --ciuser root
qm set 1XX --sshkeys /root/.ssh/authorized_keys

qm resize 1XX scsi0 30G
qm start 1XX
```
Потом установить Docker:
```bash
ssh root@10.10.10.XX
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

---

## Перезапуск всех сервисов после ребута дедика

Всё должно подняться автоматически (onboot + restart policies). Если нет:
```bash
# VM
qm start 100; qm start 101; qm start 102
pct start 103

# Мониторинг на хосте
cd /opt/monitoring && docker compose up -d

# Проверка
for ip in 10.10.10.10 10.10.10.20 10.10.10.30; do
  ssh root@$ip 'hostname; docker ps --format "{{.Names}}: {{.Status}}"'
done
```

---

## Обновление Remnawave

```bash
ssh root@10.10.10.20
cd /opt/remnawave
docker compose pull
docker compose up -d
```

**ВАЖНО**: после обновления проверить subscription page. ProxyCheckMiddleware пропатчен через volume mount в docker-compose.yml. Если путь к файлу изменится в новой версии — subscription page перестанет отвечать. Проверить:
```bash
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3010/sub/ЛЮБОЙ_UUID
# Должен быть 200, если 000 — нужно обновить путь в volume mount
```

---

## Обновление SHM

```bash
ssh root@10.10.10.10
cd /opt/shm
docker compose pull
docker compose up -d
```

---

## SHM: свежий дамп MySQL

```bash
# На дедике
ssh root@10.10.10.10 'docker exec mysql mysqldump -u root -p$(grep MYSQL_ROOT_PASS /opt/shm/.env | cut -d= -f2) shm' > /tmp/shm-backup.sql
```

## Remnawave: свежий дамп PostgreSQL

```bash
ssh root@10.10.10.20 'docker exec remnawave-db pg_dumpall -U postgres' > /tmp/remna-backup.sql
```

## WBAP: свежий дамп PostgreSQL

```bash
ssh root@10.10.10.30 'docker exec wbap-postgres-1 pg_dumpall -U wbap' > /tmp/wbap-backup.sql
```
