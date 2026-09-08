# Admin Command Cheat Sheet

## ใช้ทำอะไร

หน้าเดียวสำหรับคำสั่งประจำ ตรวจ target ทุกครั้งก่อนกด Enter

## ขั้นตอน

### Step 1: STATUS

```bash
docker ps --filter name=owncloud --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker inspect --format '{{.Name}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
docker exec -u www-data owncloud-server occ status
```

### Step 2: START / STOP / RESTART

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env start owncloud-server
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env stop owncloud-server
docker restart owncloud-server
docker restart owncloud-redis
```

### Step 3: LOGS

```bash
docker logs --tail 100 --timestamps owncloud-server
docker logs --tail 100 --timestamps owncloud-redis
sudo tail -n 100 /mnt/owncloud-data/files/owncloud.log
sudo tail -n 100 /var/log/nginx/error.log
```

### Step 4: BACKUP

บน Server-DB:

```bash
sudo systemctl start owncloud-postgres-backup.service
sudo systemctl status owncloud-postgres-backup.service --no-pager
sudo journalctl -u owncloud-postgres-backup.service -n 100 --no-pager
```

File/config backup: ใช้ maintenance procedure ใน `12-STORAGE.md` และตรวจ SHA-256

### Step 5: RESTORE

```bash
BACKUP_DIR=/var/backups/owncloud-postgres/YYYYMMDDTHHMMSSZ
sudo sh -c "cd '${BACKUP_DIR}' && sha256sum -c SHA256SUMS"
```

จากนั้นทำ isolated restore ตาม `13-BACKUP-RESTORE.md`; ห้าม restore ทับ Production โดยตรง

### Step 6: OCC

```bash
docker exec -u www-data owncloud-server occ status
docker exec -u www-data owncloud-server occ maintenance:mode --on
docker exec -u www-data owncloud-server occ maintenance:mode --off
docker exec -u www-data owncloud-server occ background:queue:status
docker exec -u www-data owncloud-server occ app:list
```

### Step 7: POSTGRES

```bash
ssh db-server
docker inspect --format '{{.Name}} {{.State.Health.Status}} {{json .NetworkSettings.Ports}}' owncloud-postgres
docker exec -u postgres owncloud-postgres psql -X -At -d owncloud -c 'select 1;'
systemctl list-timers --all --no-pager | grep owncloud-postgres-backup
```

`athena-engine-postgres16` ดูได้เฉพาะ `docker ps/inspect` metadata — ห้าม exec/restart/change

### Step 8: REDIS

```bash
docker exec owncloud-redis redis-cli ping
docker inspect --format '{{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-redis
```

### Step 9: NGINX

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo systemctl reload nginx
curl -kfsS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/status.php
```

### Step 10: STORAGE

```bash
findmnt -T /mnt/owncloud-data
stat -c '%A %U:%G %n' /mnt/owncloud-data
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
sudo du -sh -x /mnt/owncloud-data
```

### Step 11: PORTS / FIREWALL

```bash
ss -lnt
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Server-App external: 22/80/443; loopback: 8443/9200; Redis internal

### Step 12: SSH TUNNEL — Windows

```powershell
& 'D:\git\server\10.8.12.10\owncloud-production-setup\open-owncloud-tunnel.ps1'
Test-NetConnection 127.0.0.1 -Port 8443
Start-Process 'https://127.0.0.1:8443'
```

Ctrl+C หรือปิด helper window เพื่อปิด tunnel

## ตรวจสอบว่าสำเร็จ

```bash
docker exec -u www-data owncloud-server occ status
docker exec owncloud-redis redis-cli ping
curl -kfsS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/status.php
systemctl --failed --no-pager
```

## ถ้ามีปัญหา

ไปที่ [17-TROUBLESHOOTING.md](17-TROUBLESHOOTING.md) และเก็บ evidence ก่อน restart/rollback

## ข้อควรระวัง

> **WARNING:** ห้าม `docker system prune`, `docker volume prune`, `docker compose down -v`, direct storage access, unfiltered env dump หรือ secret ใน command line

> **WARNING:** คำสั่งเปลี่ยน state ต้อง Backup -> Validate -> Change -> Test -> Rollback on failure

