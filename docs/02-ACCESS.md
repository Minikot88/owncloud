# การเข้าถึง ownCloud จาก Windows

## ใช้ทำอะไร

ใช้เปิด SSH tunnel แบบ loopback เพื่อเข้าหน้า Admin อย่างปลอดภัยจาก Windows

## ขั้นตอน

### Step 1 — เปิด helper ที่ตรวจสอบแล้ว

เปิด PowerShell แล้วรัน:

```powershell
& 'D:\git\server\10.8.12.10\owncloud-production-setup\open-owncloud-tunnel.ps1'
```

helper เปิด `127.0.0.1:8443` บน Windows ไปยัง `127.0.0.1:8443` ของ Server-App และตั้ง `ExitOnForwardFailure=yes`.

### Step 2 — เปิดหน้าเว็บ

ขณะหน้าต่าง helper ยังทำงาน เปิด `https://127.0.0.1:8443` ใน browser. ใบรับรองเป็น self-signed ในปัจจุบัน จึงอาจมีคำเตือน browser

### Step 3 — ปิดเมื่อเสร็จ

กด `Ctrl+C` ในหน้าต่าง helper หรือปิดหน้าต่างนั้น

## ตรวจสอบว่าสำเร็จ

หน้า `https://127.0.0.1:8443` เปิดได้เมื่อ tunnel ทำงาน และเปิดไม่ได้หลังปิด tunnel

## ถ้ามีปัญหา

ตรวจว่าไม่มีโปรแกรมใช้ port `8443`; รัน helper ใน PowerShell ใหม่ และตรวจว่าหน้าต่าง helper ไม่ได้ปิดก่อนเปิด browser

## ข้อควรระวัง

> **WARNING:** URL นี้เป็น loopback ผ่าน tunnel เท่านั้น ห้ามเปิดเผยสู่เครือข่ายหรือเปลี่ยน SSH/TLS settings ในขั้นตอนเข้าถึง

> **WARNING:** อย่าแสดงหรือคัดลอกเนื้อหา identity key; helper จัดการ identity file เอง
