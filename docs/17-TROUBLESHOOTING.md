# Troubleshooting

## ใช้ทำอะไร

ใช้วิเคราะห์ตามอาการจาก layer ภายนอกเข้าใน โดยเก็บ evidence ก่อน restart/rollback

## ขั้นตอน

### Step 1: เก็บ Quick Baseline

```bash
date -Is
docker ps --filter name=owncloud --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker exec -u www-data owncloud-server occ status
docker exec owncloud-redis redis-cli ping
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
systemctl --failed --no-pager
```

### Step 2: เลือกอาการด้านล่าง

### Web UI เข้าไม่ได้ / SSH Tunnel เข้าไม่ได้

- **อาการ:** Browser ต่อ `https://127.0.0.1:8443` ไม่ได้
- **ตรวจ:** helper window, local listener, SSH, Nginx
- **คำสั่ง Windows:** `Test-NetConnection 127.0.0.1 -Port 8443`
- **คำสั่ง Server-App:** `curl -kI https://127.0.0.1:8443/` และ `sudo nginx -t`
- **สาเหตุ:** tunnel ปิด, key/path ผิด, local port ชน, Nginx/backend down
- **แก้:** ปิด process ที่ชน แล้วเปิด `open-owncloud-tunnel.ps1` ใหม่; แก้ Nginx เฉพาะเมื่อ validation ชี้ชัด
- **หยุด/rollback:** Nginx syntax fail หลังแก้ config

### 502 Bad Gateway

- **อาการ:** Nginx ตอบ 502
- **ตรวจ:** `curl -fsS http://127.0.0.1:9200/status.php`, `docker logs --tail 100 owncloud-server`
- **สาเหตุ:** `owncloud-server` down/unhealthy หรือ backend bind หาย
- **แก้:** ตรวจ DB/Redis/storage ก่อน restart `owncloud-server`
- **หยุด/rollback:** container crash loop หรือ config ล่าสุดเปลี่ยน DB/port

### ownCloud unhealthy

- **ตรวจ:** `docker inspect --format '{{json .State.Health}}' owncloud-server`
- **สาเหตุ:** DB, storage, Redis, application startup
- **แก้:** ตรวจ dependency ตามลำดับ; restart ครั้งเดียวหลังเก็บ log
- **หยุด/rollback:** health ไม่กลับหรือ restart count เพิ่มต่อเนื่อง

### PostgreSQL connect ไม่ได้

- **ตรวจจาก App:** `nc -zvw3 10.8.12.11 5433`
- **ตรวจ DB:** `docker inspect --format '{{.State.Health.Status}} {{json .NetworkSettings.Ports}}' owncloud-postgres`
- **ตรวจ access:** HBA, UFW, DOCKER-USER
- **สาเหตุ:** bind/firewall/HBA/container/network route
- **แก้:** คืน config ที่ตรวจแล้ว; ห้ามเปิด Anywhere
- **หยุด/rollback:** การแก้จะกระทบ 5432 หรือ `athena-engine-postgres16`

### Redis down

- **ตรวจ:** `docker exec owncloud-redis redis-cli ping`
- **สาเหตุ:** container/memory/disk/network
- **แก้:** เก็บ log แล้ว restart `owncloud-redis` ครั้งเดียว
- **หยุด/rollback:** lock errors ต่อเนื่อง; เข้า maintenance ก่อน config change

### WebDAV 401

- **อาการ:** authentication failed
- **ตรวจ:** URL, username, App Password และ tunnel แล้วใช้คำสั่งด้านล่างหลังโหลด credential จาก approved secret source

```bash
OWNCLOUD_URL='https://127.0.0.1:8443'
USERNAME='USERNAME'
APP_PASSWORD='APP_PASSWORD'
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X PROPFIND -H 'Depth: 0' "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/"
```

- **สาเหตุ:** credential ผิด/หมดอายุ, URL ผิด, account disabled
- **แก้:** สร้าง/revoke App Password ผ่าน secure workflow; ห้ามพิมพ์ token ใน report
- **หยุด:** พบ brute-force/credential leak

### WebDAV 403

- **อาการ:** login ผ่านแต่ถูกห้าม
- **ตรวจ:** group/share/permission bitmask และ path owner
- **สาเหตุ:** least-privilege policy หรือ share permission ไม่พอ
- **แก้:** ให้สิทธิ์ต่ำสุดที่ต้องใช้ผ่าน Web/OCS
- **หยุด:** ต้อง bypass direct storage permission

### Upload fail

- **ตรวจ:** `df -h`, `df -i`, Nginx `client_max_body_size 2g`, ownCloud log, quota
- **สาเหตุ:** disk/inode/quota/full, request timeout, lock, file size
- **แก้:** คืนพื้นที่อย่างปลอดภัย/ปรับ quota/config หลัง backup
- **หยุด/rollback:** ต้องลบ unknown data หรือ recursive permission change

### Disk full / inode full

- **ตรวจ:** `df -h /mnt/owncloud-data`, `df -i /mnt/owncloud-data`, `sudo du -sh -x /mnt/owncloud-data`
- **แก้:** หยุด upload, ขยาย storage หรือใช้ retention ที่อนุมัติ
- **ห้าม:** ลบ data directory, trash/version โดยเดา

### Cron fail

- **ตรวจ:** `occ config:app:get core backgroundjobs_mode`, `occ background:queue:status`, `docker top owncloud-server`
- **สาเหตุ:** cron process หาย, DB/Redis error, long-running job
- **แก้:** เก็บ job/log แล้ว restart ownCloud ตาม change window
- **หยุด:** queue/data integrity error

### Backup fail

- **ตรวจ:** `sudo systemctl status owncloud-postgres-backup.service --no-pager` และ journal
- **สาเหตุ:** health/disk/dump/checksum หรือ fixed-count validation ไม่ตรงหลังข้อมูลเพิ่ม
- **แก้:** เก็บ backup directory/log, ตรวจ `pg_restore --list`/SHA; แก้ script ผ่าน review แยก
- **หยุด:** ห้ามถือ dump ที่ไม่มี checksum/restore test เป็น PASS

### Permission denied

- **ตรวจ:** `stat -c '%A %U:%G %n' /mnt/owncloud-data /mnt/owncloud-data/config/config.php`
- **สาเหตุ:** owner/mode/mount เปลี่ยน
- **แก้:** เทียบ backup/evidence แล้วเปลี่ยนเฉพาะ target
- **หยุด:** ถ้าต้อง `chmod -R`/`chown -R` โดยยังไม่ทราบผลกระทบ

### Certificate warning

- **อาการ:** Browser เตือนที่ loopback
- **สาเหตุ:** current self-signed certificate
- **แก้:** ยืนยัน fingerprint ผ่านช่องทางที่อนุมัติ; ใช้ domain/TLS migration สำหรับ trusted certificate
- **หยุด:** hostname/fingerprint ไม่ตรง baseline หรือ certificate เปลี่ยนโดยไม่ทราบเหตุ

### Step 3: บันทึกผล

บันทึก timestamp, symptom, commands, exit code, container ID/restart count และสิ่งที่เปลี่ยน ห้ามแนบ secret/log ทั้งก้อน

## ตรวจสอบว่าสำเร็จ

- Original symptom หาย
- OCC/WebDAV/OCS/Redis/cron ผ่าน
- restart count คงที่
- ไม่มี unexpected listener
- failed services = 0

## ถ้ามีปัญหา

ถ้าหาสาเหตุไม่ได้ ให้ maintenance, ป้องกัน writes และ escalate พร้อม evidence แทนการลองคำสั่ง destructive

## ข้อควรระวัง

> **WARNING:** ห้ามแก้ DB table, `/mnt/owncloud-data`, firewall หรือ Compose ด้วยการเดา

> **WARNING:** ห้ามใช้ prune/down -v และห้ามแตะ `athena-engine-postgres16`
