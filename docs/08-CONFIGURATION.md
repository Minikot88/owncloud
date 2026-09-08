# การตั้งค่า ownCloud Production

## ใช้ทำอะไร

ใช้ค้นหา สำรอง แก้ และตรวจสอบไฟล์ตั้งค่าของ ownCloud โดยไม่เปิดเผย secret หรือกระทบระบบอื่น

## ตำแหน่งจริง

| รายการ | ตำแหน่ง | หน้าที่ |
|---|---|---|
| Compose | `/opt/owncloud/compose.yml` | กำหนด `owncloud-server` และ `owncloud-redis` |
| Runtime env | `/opt/owncloud/.env` | เก็บค่ารันและ PostgreSQL credential; `root:root 0600` |
| Bootstrap override | `/opt/owncloud/compose.bootstrap.yml` | ไฟล์จากขั้นติดตั้ง; ไม่ใช้ในงานประจำ |
| ownCloud config | `/mnt/owncloud-data/config/config.php` | effective application config |
| Nginx vhost | `/etc/nginx/sites-available/owncloud-loopback-8443` | HTTPS loopback -> backend 9200 |
| Operations scripts | `/opt/owncloud/scripts/` | audit/acceptance ที่ติดตั้งไว้ |
| PostgreSQL timer | Server-DB: `/etc/systemd/system/owncloud-postgres-backup.timer` | backup DB รายวัน |

ตัวแปรที่มีอยู่ใน `.env` ได้แก่ชื่อด้านล่างเท่านั้น ค่าจริงห้ามพิมพ์ลง terminal/report:

```text
COMPOSE_PROJECT_NAME
OWNCLOUD_HTTP_PORT
OWNCLOUD_TRUSTED_DOMAINS
OWNCLOUD_OVERWRITE_CLI_URL
OWNCLOUD_TRUSTED_PROXIES
OWNCLOUD_DB_PREFIX
OWNCLOUD_PG_PASSWORD
```

## ขั้นตอน

### Step 1: ตรวจค่าที่มีผลจริงแบบไม่เปิด secret

```bash
docker exec -u www-data owncloud-server occ status
docker exec -u www-data owncloud-server occ config:system:get dbtype
docker exec -u www-data owncloud-server occ config:system:get dbhost
docker exec -u www-data owncloud-server occ config:system:get dbname
docker exec -u www-data owncloud-server occ config:system:get dbtableprefix
docker exec -u www-data owncloud-server occ config:system:get datadirectory
```

ค่าที่ถูกต้องคือ `pgsql`, `10.8.12.11:5433`, `owncloud`, `oc_`, `/mnt/data/files`

### Step 2: สำรองก่อนแก้

```bash
CONFIG_BACKUP_ID="$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -o root -g root -m 0700 "/var/backups/owncloud/config-${CONFIG_BACKUP_ID}"
sudo cp --preserve=all /opt/owncloud/compose.yml "/var/backups/owncloud/config-${CONFIG_BACKUP_ID}/"
sudo cp --preserve=all /opt/owncloud/.env "/var/backups/owncloud/config-${CONFIG_BACKUP_ID}/"
sudo cp --preserve=all /mnt/owncloud-data/config/config.php "/var/backups/owncloud/config-${CONFIG_BACKUP_ID}/"
sudo cp --preserve=all /etc/nginx/sites-available/owncloud-loopback-8443 "/var/backups/owncloud/config-${CONFIG_BACKUP_ID}/"
sudo sh -c "cd /var/backups/owncloud/config-${CONFIG_BACKUP_ID} && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS"
```

### Step 3: แก้เฉพาะไฟล์ที่ต้องแก้

- Compose/`.env`: ใช้ `sudoedit`; ห้ามคัดลอก `.env` ไป chat หรือ ticket
- `config.php`: ใช้ `occ config:system:set` เมื่อมี command รองรับ แทนการแก้ PHP ตรง
- Nginx: สำรอง vhost แล้วแก้เฉพาะ vhost ownCloud
- Systemd: เปลี่ยนเฉพาะ `owncloud-postgres-backup.*` หลังมี change plan

ตัวอย่างตรวจ trusted domains แบบ read-only:

```bash
docker exec -u www-data owncloud-server occ config:system:get trusted_domains
```

### Step 4: Validate ก่อน apply

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --services
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --images
sudo nginx -t
```

ผล Compose ต้องมีเพียง `owncloud-redis` และ `owncloud-server`

### Step 5: Apply เฉพาะ service ที่เกี่ยวข้อง

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env up -d --no-deps owncloud-server
docker exec -u www-data owncloud-server occ status
```

## ตรวจสอบว่าสำเร็จ

```bash
docker ps --filter name=owncloud --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -kfsS https://127.0.0.1:8443/status.php
docker exec owncloud-redis redis-cli ping
```

ต้องเห็น ownCloud healthy, status JSON, และ `PONG`

## ถ้ามีปัญหา

1. หยุดการแก้ต่อ
2. ตรวจ `docker logs --tail 100 owncloud-server`
3. เทียบ SHA-256/ไฟล์กับ backup directory
4. คืนเฉพาะไฟล์ที่แก้ แล้ว validate ใหม่
5. ถ้า DB/ไฟล์ข้อมูลผิดปกติ ให้เข้า maintenance และใช้แผน restore ที่ทดสอบ isolated แล้ว

## ข้อควรระวัง

> **WARNING:** ห้ามแสดง `.env`, `config.php` ทั้งไฟล์, container environment หรือ secret value

> **WARNING:** ห้ามแก้ `athena-engine-postgres16` และห้ามใช้ unfiltered `docker compose config` ใน report เพราะอาจ interpolate secret
