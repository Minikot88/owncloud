# Disaster Recovery

## ใช้ทำอะไร

ใช้กู้ระบบเมื่อ Server-App, ownCloud PostgreSQL, storage, Redis, container หรือ config เสีย

Recovery order ที่ต้องยึด:

1. PostgreSQL
2. Storage
3. Configuration
4. ownCloud
5. Redis
6. Nginx
7. Validation

## ขั้นตอน

### Step 1: ประกาศ incident และ freeze

- หยุด writes ถ้ายังทำได้
- บันทึกเวลา/อาการ/container IDs/restart counts
- รักษา failed host/disk/log เป็น evidence
- เลือก backup timestamp เดียวกันสำหรับ DB/storage/config
- ยืนยันว่า storage/config archive ของ timestamp นั้นมีจริงและ SHA-256 ผ่าน; ถ้าไม่มี ให้ประกาศ `BLOCKED — VERIFIED STORAGE BACKUP REQUIRED` แทนการ clean rebuild
- ห้าม restore ทับของเดิมก่อน isolated restore

### Step 2: กู้ PostgreSQL

กรณี `owncloud-postgres` เสีย:

1. ยืนยัน `athena-engine-postgres16` healthy และ **ห้ามแตะ**
2. เลือก `/var/backups/owncloud-postgres/YYYYMMDDTHHMMSSZ`
3. ตรวจ SHA-256
4. ทำ isolated restore ตาม [13-BACKUP-RESTORE.md](13-BACKUP-RESTORE.md)
5. กู้เฉพาะ dedicated `owncloud-postgres` target
6. รักษา bind `10.8.12.11:5433`, HBA `/32`, volume แยก และ no Docker socket

### Step 3: กู้ Storage

1. ระบุ `STORAGE_ARCHIVE` จาก manual/approved backup ที่มี SHA-256; ห้ามสมมติว่า migration snapshot เก่าคือ current backup
2. ตรวจ checksum และ archive listing ใน isolated path ก่อน
3. ตรวจ mount `/mnt/owncloud-data`
4. หยุด `owncloud-server`
5. restore archive พร้อม owner/ACL/xattr
6. ตรวจ SHA-256 และ logical file inventory
7. ห้าม Nginx/Project mount path ตรง

ตัวอย่างตรวจหลัง restore:

```bash
findmnt -T /mnt/owncloud-data
stat -c '%A %U:%G %n' /mnt/owncloud-data
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
```

### Step 4: กู้ Configuration

คืนเฉพาะไฟล์จาก timestamp เดียวกัน:

- `/opt/owncloud/compose.yml`
- `/opt/owncloud/.env` แบบ root-only
- `/mnt/owncloud-data/config/config.php`
- Nginx ownCloud vhost/certificate

Validate ก่อน start:

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --services
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --images
sudo nginx -t
```

### Step 5: เตรียม ownCloud container

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --images
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env pull owncloud-server
```

ใช้ pinned digest ที่บันทึกไว้ ห้าม `latest` และยังไม่ start จน Redis พร้อม

### Step 6: กู้ Redis

Redis ไม่ใช่ authoritative data source หาก volume ใช้ไม่ได้ให้สร้างตาม reviewed Compose แล้วปล่อย ownCloud สร้าง cache/locks ใหม่

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env up -d owncloud-redis
docker exec owncloud-redis redis-cli ping
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env up -d --no-deps owncloud-server
docker exec -u www-data owncloud-server occ status
```

### Step 7: กู้ Nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -kfsS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/status.php
```

### Step 8: Full validation

- OCC/Web UI/Admin login
- users/groups/quotas
- existing file read-only
- WebDAV upload/download/rename/delete
- OCS share/permission
- Redis locking/cron
- restart persistence
- ports/firewall
- PostgreSQL backup + isolated restore ใหม่

## Scenario Guide

### Server-App เสีย

Rebuild OS/Docker -> mount/restore storage -> restore config/secrets -> start Redis/ownCloud -> restore Nginx -> validate

### Server-DB owncloud-postgres เสีย

สร้าง dedicated replacement เฉพาะ ownCloud -> restore verified dump -> apply exact HBA/bind -> test from App -> cutover; ห้ามใช้/แก้ `athena-engine-postgres16`

### Storage เสีย

หยุด writes -> replace/mount storage -> restore files -> verify checksum -> start ownCloud -> compare metadata/files

### Redis เสีย

หยุด writes ถ้ามี lock error -> recreate/restart Redis -> PING -> OCC/WebDAV concurrency test

### ownCloud container เสีย

ใช้ pinned image/Compose เดิม -> recreate only `owncloud-server` -> OCC/API test

### config พัง

คืน backup เฉพาะไฟล์ -> Compose/Nginx validation -> restart only affected service

## ตรวจสอบว่าสำเร็จ

- ข้อมูล/users/groups/shares/permissions ตรง approved baseline
- binary อยู่ `/mnt/owncloud-data`
- DB schemas/counts/constraints ผ่าน
- no unexpected ports
- backup ใหม่และ isolated restore ผ่าน
- failed services = 0

## ถ้ามีปัญหา

- อยู่ maintenance และ rollback ไป backup timestamp ก่อนหน้า
- ห้ามผสม DB/storage/config คนละเวลาโดยไม่ประเมิน delta
- escalate เมื่อ checksum/count/share/permission ไม่ตรง

## ข้อควรระวัง

> **WARNING:** RPO/RTO ยังไม่ได้กำหนดเป็นตัวเลข และไม่มี scheduled file/config backup จึงยังรับประกัน recovery window ไม่ได้ ต้องอนุมัติ policy แยก

> **WARNING:** หากไม่มี manually verified storage/config archive ที่ครอบคลุมข้อมูลที่ต้องกู้ ให้หยุด DR ก่อน overwrite และรายงาน blocker; ห้ามสร้างระบบว่างเพื่อบังคับให้ service ขึ้น

> **WARNING:** ห้ามลบ failed data/volume ก่อน backup retention และ forensic gate
