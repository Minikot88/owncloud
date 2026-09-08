# Security Operations

## ใช้ทำอะไร

อธิบาย security boundary ปัจจุบันและวิธีดูแลแบบ Least Privilege

## Security Model ปัจจุบัน

| จุด | Exposure |
|---|---|
| Server-App SSH/HTTP/HTTPS | 22, 80, 443 |
| ownCloud Admin HTTPS | `127.0.0.1:8443` ผ่าน SSH tunnel |
| ownCloud backend | `127.0.0.1:9200` |
| Redis | Docker internal `6379`; ไม่มี host port |
| ownCloud PostgreSQL | `10.8.12.11:5433`; source `10.8.12.10` เท่านั้น |
| Other Production PostgreSQL | `10.8.12.11:5432`; `athena-engine-postgres16`, ห้ามแตะ |
| File storage | `/mnt/owncloud-data`, direct access prohibited |

## ขั้นตอน

### Step 1: ตรวจ listeners/firewall

Server-App:

```bash
ss -lnt
sudo ufw status verbose
sudo sshd -T | grep -E '^(port|passwordauthentication|permitrootlogin|pubkeyauthentication) '
```

ค่าปัจจุบัน: SSH key enabled, password auth disabled, root login disabled

Server-DB:

```bash
ss -lnt
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v --line-numbers
docker exec owncloud-postgres sed -n '1,120p' /etc/postgresql/pg_hba.conf
```

### Step 2: ใช้ Least Privilege

- Admin account ใช้เฉพาะบริหาร ownCloud
- Backend ใช้ service user แยกต่อ Project
- กลุ่ม/โฟลเดอร์แยก `project01` ถึง `project10`
- ให้ permission ต่ำสุดที่งานต้องใช้
- Integration DB ใช้ `owncloud_integration_app`; ห้ามใช้ `owncloud_app` หรือ PostgreSQL superuser ใน Project

### Step 3: ใช้ App Password

1. Login ด้วย service user ผ่าน Web Admin
2. เปิด Personal/Security settings
3. สร้าง credential สำหรับ application เดียว
4. เก็บใน approved secret store
5. ทดสอบ WebDAV/OCS
6. revoke เมื่อเลิกใช้หรือสงสัยรั่ว

### Step 4: ป้องกัน secret

- `/opt/owncloud/.env` และ DB secret เป็น root-only
- ห้าม `cat`, screenshot, copy หรือแนบไฟล์เหล่านี้
- ใช้ placeholder ใน command/report
- Backup secret ต้อง encrypted และแยกสิทธิ์จาก data backup
- Rotation ต้อง backup -> change -> test -> rollback plan

### Step 5: ป้องกัน file storage

```bash
stat -c '%A %U:%G %n' /mnt/owncloud-data
docker inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}' owncloud-server
```

อนุญาต mount เฉพาะ `owncloud-server`; Nginx/Project ห้าม mount/serve ตรง

### Step 6: ตรวจ backup protection

```bash
sudo stat -c '%A %U:%G %n' /var/backups/owncloud-pg-migration/20260830T035016Z
ssh db-server
sudo stat -c '%A %U:%G %n' /var/backups/owncloud-postgres
```

Backup ต้อง root-only และ checksum verified

### Step 7: ทบทวนรายเดือน

- Admin/service users
- Groups/quotas/shares
- App passwords/tokens
- SSH keys
- UFW/HBA rules
- Backup access/retention
- Certificate expiry

## ตรวจสอบว่าสำเร็จ

- Server-App externally reachable เฉพาะ 22/80/443
- 8443/9200 เป็น loopback
- 5433 bind private และ HBA source `/32`
- Redis ไม่มี host port
- Projects ทดสอบ unauthorized access แล้ว fail
- Secret files root-only และไม่มีค่า secret ใน report/log

## ถ้ามีปัญหา

1. revoke credential ที่สงสัยรั่ว
2. จำกัด access โดยไม่ปิด firewall protection
3. เก็บ audit evidence
4. rotate ผ่าน change plan
5. ตรวจ data/share access หลัง rotation

## ข้อควรระวัง

> **WARNING:** ห้ามเปิด 8443, 9200, 5433 หรือ 6379 เป็น `0.0.0.0`/Anywhere

> **WARNING:** ห้าม Project อ่าน `/mnt/owncloud-data` ตรง และห้ามเขียน `public.oc_*`

> **WARNING:** ห้ามแก้ network/config/data/role/schema ของ `athena-engine-postgres16`
