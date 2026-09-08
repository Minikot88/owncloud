# วงจรงานไฟล์

## ใช้ทำอะไร

ใช้ทำ upload, download, rename, delete และ share โดยรักษา metadata กับ binary storage ให้ระบบ ownCloud จัดการ

## ขั้นตอน

### Step 1 — Upload และจัดระเบียบ

ใช้ Files web UI หรือ WebDAV เพื่อสร้างโฟลเดอร์และ upload. ตั้งชื่อ/ย้ายด้วย UI หรือ API แล้วตรวจผลใน client ที่ได้รับสิทธิ์

### Step 2 — Download และ share

download จาก Files หรือ WebDAV. สร้าง share เท่าที่จำเป็น กำหนดผู้รับและสิทธิ์ต่ำสุด แล้วทดสอบด้วยบัญชีผู้รับ

### Step 3 — Delete และกู้คืน

ลบจาก UI/API เมื่อได้รับอนุมัติ; ไฟล์จะเข้าสู่ trashbin ตามกลไก enabled `files_trashbin`. เวอร์ชันจัดการโดย `files_versions`; การมีอยู่/อายุ retention ต้องตรวจใน UI ก่อนอ้างว่ากู้ได้

## ตรวจสอบว่าสำเร็จ

ผู้ส่งเห็นสถานะงานใน Files และผู้รับที่อนุญาตเปิดได้ตามสิทธิ์ ขณะที่ผู้ไม่มีสิทธิ์เปิดไม่ได้

## ถ้ามีปัญหา

ตรวจ quota, path, share permissions และ Trashbin/Versions ใน UI. หากพบ metadata ไม่สอดคล้อง ให้ยกระดับให้ผู้ดูแล ownCloud ตรวจ ไม่แก้ฐานข้อมูลเอง

## ข้อควรระวัง

PostgreSQL เก็บ metadata ของ ownCloud; binary storage อยู่ `/mnt/owncloud-data` ผ่าน `/mnt/data/files` ใน container. Nginx ต้องไม่ serve path นี้โดยตรง

> **WARNING:** ห้ามอ่าน, mount, copy, ลบ หรือแก้ `/mnt/owncloud-data` โดยตรงเพื่อทำงานไฟล์; ใช้ Web UI, WebDAV หรือ OCS API เท่านั้น
