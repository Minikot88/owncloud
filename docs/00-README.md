# คู่มือปฏิบัติการ ownCloud Production

## ใช้ทำอะไร

ใช้เป็นจุดเริ่มต้นสำหรับผู้ดูแลและทีมโครงการของ ownCloud Community 11.0.0 โดยแยกงานเว็บ ผู้ใช้ ไฟล์ และ API ให้ชัดเจน

## ขั้นตอน

### Step 1 — เข้าใจองค์ประกอบ

ownCloud คือ file manager สำหรับผู้ใช้และโครงการ. Docker เป็นตัวรันบริการ ownCloud และ Redis; Nginx เป็น reverse proxy รับคำขอเว็บ/API แล้วส่งเข้า ownCloud. PostgreSQL เก็บ metadata, users, permissions, shares และ index ไม่ได้เก็บ binary ของไฟล์. Redis ใช้ cache และ file locking. ไฟล์ binary จริงอยู่ที่ `/mnt/owncloud-data` ซึ่ง ownCloud จัดการ

```text
User/Project -> ownCloud WebDAV/API -> Nginx -> ownCloud (Docker)
                                             -> PostgreSQL: metadata/users/permissions/shares/index
                                             -> Redis: cache/file locking
                                             -> /mnt/owncloud-data: binary files
```

### Step 2 — เลือกคู่มือที่ตรงงาน

- [00 ภาพรวม](00-README.md), [01 สถาปัตยกรรม](01-ARCHITECTURE.md), [02 การเข้าถึง](02-ACCESS.md), [03 Web Admin](03-WEB-ADMIN.md)
- [04 งานไฟล์](04-FILE-OPERATIONS.md), [05 ผู้ใช้/กลุ่ม/สิทธิ์](05-USERS-GROUPS-PERMISSIONS.md), [06 WebDAV/OCS](06-API-WEBDAV-OCS.md), [07 การเชื่อมโครงการ](07-PROJECT-INTEGRATION.md)
- [08 Configuration](08-CONFIGURATION.md), [09 Docker operations](09-DOCKER-OPERATIONS.md), [10 PostgreSQL](10-POSTGRESQL.md), [11 Redis](11-REDIS.md)
- [12 Storage](12-STORAGE.md), [13 Backup/restore](13-BACKUP-RESTORE.md), [14 Monitoring/logs](14-MONITORING-LOGS.md), [15 Security](15-SECURITY.md)
- [16 Update/upgrade](16-UPDATE-UPGRADE.md), [17 Troubleshooting](17-TROUBLESHOOTING.md), [18 NAS migration](18-NAS-MIGRATION.md), [19 Domain/TLS migration](19-DOMAIN-TLS-MIGRATION.md)
- [20 Disaster recovery](20-DISASTER-RECOVERY.md), [21 Daily/weekly/monthly checklist](21-DAILY-WEEKLY-MONTHLY-CHECKLIST.md), [22 Command cheatsheet](22-COMMAND-CHEATSHEET.md)

## ตรวจสอบว่าสำเร็จ

ผู้ปฏิบัติงานเลือกคู่มือเฉพาะงาน และเข้าใจว่า Files ใช้ WebDAV/OCS ไม่ใช่การอ่าน storage โดยตรง

## ถ้ามีปัญหา

เริ่มที่ [02-ACCESS.md](02-ACCESS.md) หากเปิดหน้าเว็บไม่ได้ หรือใช้ [01-ARCHITECTURE.md](01-ARCHITECTURE.md) เพื่อแยกชั้นที่เกี่ยวข้อง

## ข้อควรระวัง

> **WARNING:** Project/Application ต้องใช้ WebDAV หรือ OCS API เท่านั้น ห้าม mount หรืออ่าน `/mnt/owncloud-data` โดยตรง

> **WARNING:** ห้ามแก้ไข PostgreSQL container `athena-engine-postgres16`; ไม่ใช่ส่วนของ ownCloud
