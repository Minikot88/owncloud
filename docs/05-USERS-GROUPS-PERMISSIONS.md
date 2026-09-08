# ผู้ใช้ กลุ่ม และสิทธิ์

## ใช้ทำอะไร

ใช้บริหาร local ownCloud users, groups, quota และสิทธิ์ share ตามหลัก least privilege

## ขั้นตอน

### Step 1 — สร้าง group และจัดสมาชิก

1. เปิด tunnel ตาม [02-ACCESS.md](02-ACCESS.md), login ด้วยผู้ดูแลที่ได้รับอนุมัติ แล้วเปิด **Users**.
2. สร้างหรือเลือก group ตามรูปแบบ `project01` ถึง `project10`.
3. เพิ่มสมาชิกที่ได้รับอนุมัติใน group; เมื่อต้องถอนสิทธิ์ ให้ลบสมาชิกจาก group แล้วตรวจ shares ที่ได้รับผลกระทบ.

### Step 2 — สร้าง user และกำหนด quota

1. ใน **Users** เลือกสร้าง user ใหม่ แล้วกำหนด user identifier ตามมาตรฐานที่อนุมัติ.
2. เลือก group ของโครงการและกำหนด quota ที่จำเป็น; บันทึกแล้วตรวจว่า user แสดง group/quota ที่ตั้งไว้.
3. ส่ง password เริ่มต้นผ่านช่องทางที่ได้รับอนุมัติเท่านั้น; ห้าม paste, echo หรือบันทึก password ใน terminal, ticket, document หรือ log.

### Step 3 — Disable, enable และ reset password

1. เมื่อต้องพักการเข้าถึง ให้เลือก user ใน **Users** แล้วใช้ action **Disable**; ตรวจว่า user เข้าใช้งานไม่ได้.
2. เมื่อต้องเปิดกลับ ให้ใช้ action **Enable** หลังได้รับอนุมัติ; ตรวจ group และ quota ซ้ำก่อนแจ้งผู้ใช้.
3. เมื่อต้อง reset password ให้ใช้ action reset password ใน Web Admin และกรอกค่าใหม่แบบ interactive ใน UI เท่านั้น; ห้ามส่งค่าเป็น command argument หรือแสดงบนจอร่วมกัน.

### Step 4 — Delete หลังผ่าน ownership/retention gate

1. ก่อน delete ให้ยืนยันเจ้าของข้อมูล, ตรวจการโอน ownership ที่อนุมัติ, และตรวจ retention/การเก็บรักษาที่เกี่ยวข้อง.
2. บันทึก approval ตามกระบวนการ แล้วจึงใช้ action **Delete** ใน Web Admin.
3. ตรวจผลกระทบต่อ group, share และการเข้าถึงข้อมูลหลัง delete.

### Step 5 — Share folder และกำหนดสิทธิ์

1. ใน **Files** เลือก folder > **Share** แล้วเลือก group ก่อนรายบุคคลเมื่อเหมาะสม.
2. เลือก **read-only** เมื่อต้องให้ดู/ดาวน์โหลดอย่างเดียว; เลือก **read-write** เฉพาะเมื่อผู้รับต้องแก้ไขหรือเพิ่มไฟล์.
3. เปิดสิทธิ์ **share** เฉพาะผู้รับที่ต้องส่งต่อ share ตามงานที่อนุมัติ; ไม่เปิดโดยค่าเริ่มต้น.
4. ทดสอบทั้งสมาชิกที่ได้รับสิทธิ์และผู้ใช้ที่ไม่ได้รับสิทธิ์; ลดสิทธิ์หรือถอด share ทันทีหากผลไม่ตรงขอบเขต.

## ตรวจสอบว่าสำเร็จ

ผู้ใช้แสดง group และ quota ถูกต้อง; สมาชิกโครงการเข้าถึงโฟลเดอร์ที่อนุญาตได้ และ non-member เข้าไม่ได้

## ถ้ามีปัญหา

ตรวจสถานะ enabled, group membership, quota และ permissions ของ share. ตรวจว่าผู้ใช้เป็น local ownCloud เพราะ external auth ที่ระบุในระบบปัจจุบันถูกปิดใช้งาน

## ข้อควรระวัง

> **WARNING:** ไม่มี Admin account สำหรับ backend/application; backend ต้องใช้ service user และ app password ผ่าน WebDAV/OCS ตามการอนุมัติ

> **WARNING:** Disable/delete และลดสิทธิ์อาจตัดการเข้าถึงทันที ให้ทดสอบและแจ้งเจ้าของข้อมูลก่อน
