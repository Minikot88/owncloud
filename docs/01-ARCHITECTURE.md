# สถาปัตยกรรม ownCloud Production

## ใช้ทำอะไร

ใช้ระบุขอบเขตระบบและเส้นทางข้อมูลก่อนวิเคราะห์หรือเปลี่ยนแปลงการปฏิบัติการ

## ขั้นตอน

### Step 1 — ระบุสองเซิร์ฟเวอร์

`research-app` (`10.8.12.10`) รัน Compose project `owncloud` ที่ `/opt/owncloud`: `owncloud-server` (host `127.0.0.1:9200->8080`) และ `owncloud-redis` (container-only `6379`). Nginx รับ HTTPS ที่ `127.0.0.1:8443` แล้ว proxy ไป `9200`.

`research-db` (`10.8.12.11`) รัน `owncloud-postgres` PostgreSQL 16.13 ที่ `10.8.12.11:5433->5432`; database `owncloud`, role `owncloud_app`, prefix `oc_`.

### Step 2 — ตาม data flow

```text
Client -> 8443 Nginx -> 9200 owncloud-server -> 5433 owncloud-postgres (metadata)
                                      |-> Redis (locking)
                                      `-> /mnt/data/files (binary storage)
```

host `/mnt/owncloud-data` bind-mount เป็น `/mnt/data`; effective data directory คือ `/mnt/data/files`. ภายนอก Server-App เปิดเพียง TCP 22/80/443; database จำกัด app source ที่ `10.8.12.10/32` ด้วย network filtering และ HBA.

### Step 3 — รักษา trust boundary

ผู้ใช้ผ่าน HTTPS; app-to-DB เป็นเส้นทางเฉพาะ; Redis ไม่มี host publication. Projects ใช้ WebDAV/OCS เท่านั้น และ custom integration ใช้ schema `owncloud_integration` ที่ผ่านการทบทวน

## ตรวจสอบว่าสำเร็จ

แผนงานระบุได้ว่า metadata อยู่ PostgreSQL, binary อยู่ ownCloud storage และจุดเข้าเว็บคือ Nginx

## ถ้ามีปัญหา

หากหน้าเว็บไม่ตอบ ให้ตรวจ tunnel/Nginx ก่อน; หากเป็นข้อมูล/lock ให้แยก ownCloud, Redis และ database ตาม flow ข้างต้น

## ข้อควรระวัง

> **WARNING:** `public.oc_*` เป็น 51 ตารางที่ ownCloud จัดการ ห้าม custom SQL write

> **WARNING:** `athena-engine-postgres16` เป็นระบบที่ได้รับการปกป้องของงานอื่น ห้าม exec, restart, configure, backup หรือแก้ไข
