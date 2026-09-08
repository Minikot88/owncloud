# Backup และ Restore

## ใช้ทำอะไร

ใช้ดู policy จริง รัน backup ตรวจ checksum และทดสอบ restore แบบ isolated ก่อนแตะ Production

## สถานะปัจจุบัน

| รายการ | สถานะ |
|---|---|
| PostgreSQL | อัตโนมัติทุกวัน 02:30 + random delay ≤15 นาที |
| PostgreSQL retention | 30 วัน |
| PostgreSQL location | Server-DB: `/var/backups/owncloud-postgres/` |
| PostgreSQL script | `/usr/local/sbin/owncloud-postgres-backup` |
| File/config scheduled backup | **ยังไม่มีบน Server-App** |
| Verified migration snapshot | `/var/backups/owncloud-pg-migration/20260830T035016Z` |
| Migration rollback archive | `ARCHIVED — ROLLBACK ONLY`; มีหลักฐาน rollback ยุค MariaDB และไม่ใช่ runtime |

Verified PostgreSQL backup ล่าสุดจาก audit: `/var/backups/owncloud-postgres/20260830T044941Z`

## ขั้นตอน

### Step 1: ตรวจ timer และผลรันล่าสุด

บน Server-DB:

```bash
systemctl is-enabled owncloud-postgres-backup.timer
systemctl is-active owncloud-postgres-backup.timer
systemctl list-timers --all --no-pager | grep owncloud-postgres-backup
sudo journalctl -u owncloud-postgres-backup.service -n 100 --no-pager
```

### Step 2: สั่ง PostgreSQL backup เมื่อได้รับอนุมัติ

```bash
sudo systemctl start owncloud-postgres-backup.service
sudo systemctl status owncloud-postgres-backup.service --no-pager
sudo journalctl -u owncloud-postgres-backup.service -n 100 --no-pager
```

หา directory ล่าสุดและตรวจ checksum:

```bash
sudo find /var/backups/owncloud-postgres -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
BACKUP_DIR=/var/backups/owncloud-postgres/YYYYMMDDTHHMMSSZ
sudo sh -c "cd '${BACKUP_DIR}' && sha256sum -c SHA256SUMS"
```

แทน `YYYYMMDDTHHMMSSZ` ด้วย directory ที่ตรวจแล้ว ห้ามใช้ path ที่เดา

### Step 3: ทำ file/config backup คู่กัน

ดูขั้นตอน maintenance + archive ใน [12-STORAGE.md](12-STORAGE.md)

ต้องเก็บอย่างน้อย:

- `/mnt/owncloud-data`
- `/opt/owncloud/compose.yml`
- `/opt/owncloud/.env` แบบ root-only
- Nginx ownCloud vhost/certificate metadata
- PostgreSQL dump ช่วงเวลาเดียวกัน
- SHA-256 manifest

### Step 4: ทดสอบ isolated restore

รันบน Server-DB เท่านั้น ตัวอย่างนี้ไม่ publish port และไม่เชื่อม network:

```bash
RESTORE_ID="owncloud-restore-$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR=/var/backups/owncloud-postgres/YYYYMMDDTHHMMSSZ
RESTORE_IMAGE="$(docker inspect --format '{{.Image}}' owncloud-postgres)"
test -n "${RESTORE_IMAGE}"
docker image inspect "${RESTORE_IMAGE}" >/dev/null
docker volume create "${RESTORE_ID}-data"
docker run -d --name "${RESTORE_ID}" --network none \
  --mount "type=volume,source=${RESTORE_ID}-data,target=/var/lib/postgresql/data" \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_DB=owncloud_restore \
  "${RESTORE_IMAGE}"
docker exec -u postgres "${RESTORE_ID}" pg_isready -d owncloud_restore
sudo docker cp "${BACKUP_DIR}/owncloud.dump" "${RESTORE_ID}:/tmp/owncloud.dump"
docker exec -u postgres "${RESTORE_ID}" pg_restore --exit-on-error --verbose --no-owner --dbname=owncloud_restore /tmp/owncloud.dump
```

ตรวจ schema/counts:

```bash
docker exec -u postgres "${RESTORE_ID}" psql -X -v ON_ERROR_STOP=1 -d owncloud_restore -c "select count(*) from pg_tables where schemaname='public' and tablename like 'oc\\_%' escape '\\';"
docker exec -u postgres "${RESTORE_ID}" psql -X -v ON_ERROR_STOP=1 -d owncloud_restore -c "select count(*) from information_schema.tables where table_schema='owncloud_integration' and table_type='BASE TABLE';"
docker exec -u postgres "${RESTORE_ID}" psql -X -v ON_ERROR_STOP=1 -d owncloud_restore -c "select count(*) from owncloud_integration.projects;"
docker exec -u postgres "${RESTORE_ID}" psql -X -v ON_ERROR_STOP=1 -d owncloud_restore -c "select count(*) from information_schema.table_constraints where table_schema='owncloud_integration';"
docker exec -u postgres "${RESTORE_ID}" psql -X -v ON_ERROR_STOP=1 -d owncloud_restore -c "select count(*) from pg_indexes where schemaname='owncloud_integration';"
```

ค่าปัจจุบันที่ใช้เป็น baseline: `oc_*` 51, integration tables 6, projects 10, constraints 76, indexes 25

ลบเฉพาะ isolated resources หลังบันทึกผล:

```bash
docker rm -f "${RESTORE_ID}"
docker volume rm "${RESTORE_ID}-data"
```

### Step 5: Restore Production

ทำเฉพาะ change window ที่อนุมัติแล้ว:

1. ยืนยัน isolated restore PASS
2. เปิด maintenance และหยุด writes/background jobs
3. สำรอง Production ปัจจุบันอีกชุด
4. Restore ไป dedicated `owncloud-postgres` target ที่ยืนยันแล้ว
5. Restore `/mnt/owncloud-data` และ config จาก backup timestamp เดียวกัน
6. ตรวจ OCC, users/files/shares, WebDAV, OCS และ checksum
7. ปิด maintenance mode หลังทุก gate ผ่าน

### Step 6: Secret recovery

- Secret ไม่อยู่ใน `roles-no-passwords.sql`
- ดึงจาก approved secure credential source หรือทำ controlled rotation
- อัปเดต root-only secret และ Server-App `.env` ใน change เดียวกัน
- ห้ามส่ง secret ผ่าน chat, shell history, command argument หรือ report

## ตรวจสอบว่าสำเร็จ

- `sha256sum -c SHA256SUMS` ทุกไฟล์เป็น `OK`
- `pg_restore` exit code 0
- schemas/counts/constraints/indexes ตรง baseline ที่อนุมัติ
- ไม่มี host port จาก isolated container
- Production ไม่ถูกแก้ระหว่าง restore test

## ถ้ามีปัญหา

1. หยุดก่อน Production restore
2. เก็บ dump, log และ checksum เป็น evidence
3. ลบเฉพาะ isolated container/volume ที่สร้างในรอบนั้น
4. แก้ root cause แล้วสร้าง backup ใหม่
5. ห้ามลด validation เพื่อบังคับ PASS

## ข้อควรระวัง

> **WARNING:** ห้าม restore ทับ Production โดยไม่ผ่าน isolated restore ก่อน

> **WARNING:** PostgreSQL backup script ปัจจุบันตรวจ fixed counts จากวัน migration (users 11, files 4, shares 0) ข้อมูลเพิ่มตามปกติอาจทำให้ service FAIL ต้องตรวจ dump/checksum และแก้ policy ผ่าน change plan แยก

> **WARNING:** Server-App ยังไม่มี automated file/config backup; จุดนี้ต้องแก้ก่อนกำหนด RPO/RTO ที่เชื่อถือได้
