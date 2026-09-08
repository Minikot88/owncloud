# การเชื่อมโครงการกับ ownCloud

## ใช้ทำอะไร

ใช้เชื่อม application ของ `project01`–`project10` ผ่าน service user, app password, WebDAV/OCS และ integration metadata ที่แยกจาก ownCloud core

## ขั้นตอน

### Step 1 — กำหนดขอบเขตโครงการ

ระบุ project code, owner, folder และ least-privilege group ก่อนสร้าง integration

### Step 2 — สร้าง service access

สร้าง service user/app password ตามกระบวนการอนุมัติ, เพิ่มเข้า group ที่จำเป็น และให้สิทธิ์เฉพาะ folder ของโครงการ

### Step 3 — ตั้งค่า backend ด้วย placeholders

```text
OWNCLOUD_URL=APPROVED_REACHABLE_OWNCLOUD_URL
USERNAME=USERNAME
APP_PASSWORD=APP_PASSWORD
```

`https://127.0.0.1:8443` ใช้ได้เฉพาะ Windows/admin workstation ขณะที่ verified SSH tunnel ทำงานอยู่เท่านั้น. Deployed backend ต้องใช้ endpoint ที่เข้าถึงได้และได้รับอนุมัติ; ห้ามสมมติว่า loopback ของ backend ชี้ถึง ownCloud. จัดเก็บค่าจริงใน approved secret handling ของ deployment เท่านั้น และ backend เรียก WebDAV/OCS API

### Step 4 — ทดสอบบวก

ทดสอบ list/create/upload/download/share ภายใน folder ของโครงการ แล้วบันทึก path, etag และผลลัพธ์ที่ไม่เป็นความลับ

### Step 5 — ทดสอบการเข้าถึงที่ต้องถูกปฏิเสธ

ยืนยันว่า service user อ่าน folder ของโครงการอื่นไม่ได้ และไม่สามารถทำคำสั่งนอกสิทธิ์ เช่น delete/share เมื่อไม่ได้รับอนุญาต

### Step 6 — บันทึก integration metadata

ใช้ schema `owncloud_integration` ผ่าน reviewed least-privilege access เท่านั้น. ตารางเก็บ reference/metadata ไม่เก็บ binary หรือ token plaintext:

| ตาราง | วัตถุประสงค์และ key fields |
|---|---|
| `projects` | ระบุโครงการ: `id`, `project_code`, `display_name`, `status`, `created_at`, `updated_at` |
| `files` | อ้างอิงไฟล์ ownCloud ต่อโครงการ: `project_id`, `owncloud_file_id`, `owner_uid`, `dav_path`, `etag`, `logical_size`, `content_checksum`, `mime_type`, timestamps |
| `file_versions` | เก็บ reference ของเวอร์ชันไฟล์: `project_id`, `file_id`, `version_number`, `etag`, `logical_size`, `content_checksum`, `created_at` |
| `file_shares` | เก็บ reference การแชร์: `project_id`, `file_id`, `owncloud_share_id`, `share_type`, `grantee_reference`, `permissions`, `expires_at`, timestamps |
| `service_accounts` | ระบุ service account โดยไม่เก็บ plaintext: `project_id`, `account_name`, `owncloud_uid`, `token_digest`, `active`, timestamps |
| `file_access_logs` | audit การเข้าถึง: `project_id`, optional file/service account, `actor_uid`, `action`, `request_id`, `source_ip`, `occurred_at` |

### Step 7 — แยกขอบเขตข้อมูล

RLS ถูกบังคับกับทั้งหกตารางและมี policy แยก project; ใช้ project code ที่มีอยู่ (`project01`–`project10`) ตามงานที่อนุมัติ

### Step 8 — ตรวจ audit trail

บันทึก action, actor, request identifier และเวลาตาม schema ที่ได้รับอนุมัติ โดยไม่บันทึก app password

### Step 9 — ทบทวนก่อนเปิดใช้

ทบทวน permissions, positive/negative test และวิธี rotation/revocation กับเจ้าของโครงการ

### Step 10 — ปฏิบัติการต่อเนื่อง

เมื่อมี failure ให้ disable/revoke service access ตามกระบวนการ แล้วตรวจ logs ที่เหมาะสมโดยไม่เปิดเผย secrets

## ตรวจสอบว่าสำเร็จ

backend ทำงานผ่าน WebDAV/OCS, positive test ผ่าน, negative test ถูกปฏิเสธ, และ metadata อยู่เฉพาะ integration schema

## ถ้ามีปัญหา

ตรวจ tunnel/endpoint, service user active, group/share permissions และ RLS context; ยกระดับขอ review เมื่อจำเป็นต้องแก้ database access

## ข้อควรระวัง

> **WARNING:** ห้ามเขียนโดยตรงไปที่ `public.oc_*`; ownCloud เป็นผู้จัดการตารางเหล่านี้

> **WARNING:** ห้าม mount หรืออ่าน `/mnt/owncloud-data` และห้ามเก็บ binary, app password หรือ token plaintext ใน integration tables
