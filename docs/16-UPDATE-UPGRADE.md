# Update และ Upgrade

## ใช้ทำอะไร

ใช้ปรับ ownCloud, Redis, PostgreSQL หรือ Nginx แบบมี backup, compatibility gate และ rollback

Current pinned images:

- `owncloud/server:11.0.0` pinned by digest
- `redis:7.4-alpine` pinned by digest
- `postgres:16` (`owncloud-postgres`) pinned by digest

## ขั้นตอน

### Step 1: อ่าน release notes และกำหนด scope

- ตรวจ supported upgrade path ของ ownCloud ทีละ major/minor
- ตรวจ PHP/PostgreSQL/Redis compatibility
- ระบุ image digest ใหม่ ไม่ใช้ floating `latest`
- ระบุ maintenance window, owner และ rollback threshold
- ยืนยันว่าแผนไม่แตะ `athena-engine-postgres16`

### Step 2: เก็บ baseline

```bash
docker inspect --format '{{.Name}} image={{.Image}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
docker exec -u www-data owncloud-server occ status
docker exec -u www-data owncloud-server occ app:list
sudo nginx -t
```

บน Server-DB:

```bash
docker inspect --format '{{.Name}} image={{.Image}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-postgres
```

### Step 3: Backup และ verify

1. PostgreSQL backup + SHA-256
2. `/mnt/owncloud-data` backup + SHA-256
3. `/opt/owncloud` และ Nginx vhost backup
4. isolated restore PostgreSQL
5. บันทึก image IDs/digests เดิม

ใช้ [13-BACKUP-RESTORE.md](13-BACKUP-RESTORE.md)

### Step 4: ทดสอบ image ใหม่ใน isolated environment

- ใช้สำเนา DB/storage ที่ไม่มี Production writes
- ทดสอบ OCC, login, WebDAV, OCS, Redis locking, cron และ restart persistence
- ทดสอบ rollback image/config เดิม

### Step 5: เข้า maintenance

```bash
docker exec -u www-data owncloud-server occ maintenance:mode --on
docker exec -u www-data owncloud-server occ status
```

หยุด background writes ตาม runbook ของ version นั้น

### Step 6: Pull pinned image และ apply เฉพาะ service

แก้ digest ใน `/opt/owncloud/compose.yml` หลังสำรอง แล้ว validate:

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --services
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --images
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env pull owncloud-server
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env up -d --no-deps owncloud-server
```

### Step 7: รัน ownCloud upgrade

```bash
docker exec -u www-data owncloud-server occ upgrade
docker exec -u www-data owncloud-server occ status
docker exec -u www-data owncloud-server occ app:list
```

### Step 8: Test ก่อนเปิด maintenance

- OCC
- Admin login/Web UI
- Redis/cron
- WebDAV upload/download/rename/delete
- OCS create/update/delete share
- existing file read-only
- restart persistence

### Step 9: ออกจาก maintenance

```bash
docker exec -u www-data owncloud-server occ maintenance:mode --off
docker exec -u www-data owncloud-server occ status
```

### Step 10: Rollback เมื่อ fail

1. กลับเข้า maintenance
2. คืน Compose/config จาก backup
3. ใช้ pinned image digest เดิม
4. Restore DB/storage เฉพาะเมื่อ migration เปลี่ยน schema/data และ isolated rollback ผ่านแล้ว
5. ทดสอบทุก gate ก่อนเปิดบริการ

## ตรวจสอบว่าสำเร็จ

```bash
docker inspect --format '{{.Name}} image={{.Image}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
docker exec -u www-data owncloud-server occ status
curl -kfsS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/status.php
```

## ถ้ามีปัญหา

- หยุดเมื่อ OCC upgrade fail, schema mismatch, file/share mismatch หรือ container crash loop
- เก็บ logs/image ID/config hash
- rollback ตาม threshold ที่กำหนด
- ห้ามทดลองแก้ DB table ตรงเพื่อให้ upgrade ผ่าน

## ข้อควรระวัง

> **WARNING:** ห้ามใช้ `latest` โดยไม่ review/pin digest และห้าม upgrade ข้าม unsupported path

> **WARNING:** ห้าม upgrade/restart `athena-engine-postgres16` ในงาน ownCloud

> **WARNING:** ต้องมี file/config backup จริงก่อน upgrade; migration snapshot เก่าไม่แทน current backup

