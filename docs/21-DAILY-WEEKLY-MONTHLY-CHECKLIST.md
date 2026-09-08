# Checklist รายวัน รายสัปดาห์ รายเดือน

## ใช้ทำอะไร

ใช้เป็นรายการตรวจงานประจำของผู้ดูแล ownCloud พร้อมหลักฐานขั้นต่ำ

## ขั้นตอน

### Step 1: DAILY

- [ ] Containers healthy และ restart count ไม่เพิ่ม

```bash
docker inspect --format '{{.Name}} {{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
ssh db-server "docker inspect --format '{{.Name}} {{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-postgres"
```

- [ ] OCC status และ Redis PING

```bash
docker exec -u www-data owncloud-server occ status
docker exec owncloud-redis redis-cli ping
```

- [ ] Disk/inode

```bash
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
```

- [ ] PostgreSQL backup last run/timer

```bash
ssh db-server "systemctl list-timers --all --no-pager | grep owncloud-postgres-backup"
ssh db-server "systemctl status owncloud-postgres-backup.service --no-pager"
```

- [ ] Failed services

```bash
systemctl --failed --no-pager
ssh db-server 'systemctl --failed --no-pager'
```

### Step 2: WEEKLY

- [ ] ตรวจ ownCloud/Nginx/PostgreSQL/Redis logs ช่วง 7 วัน
- [ ] ตรวจ SHA-256 ของ backup ล่าสุด
- [ ] ตรวจ growth ของ disk/inode และ backup root
- [ ] ตรวจ cron queue มี Last Checked ใหม่
- [ ] ตรวจ UFW/HBA/listeners ไม่มี drift
- [ ] ตรวจ security alerts/login failures โดยเก็บข้อมูลเป็น TLP:RED

คำสั่งหลัก:

```bash
docker exec -u www-data owncloud-server occ background:queue:status
ss -lnt
sudo ufw status verbose
ssh db-server 'ss -lnt; sudo ufw status verbose'
```

### Step 3: MONTHLY

- [ ] ทดสอบ PostgreSQL isolated restore
- [ ] ทบทวน release notes/update path และ pinned digests
- [ ] ทบทวน Admin/service users/groups
- [ ] revoke App Password/token ที่ไม่ใช้
- [ ] ทบทวน quotas/shares/permissions
- [ ] ทบทวน backup retention และ file/config backup gap
- [ ] ตรวจ TLS expiry

```bash
sudo openssl x509 -in /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt -noout -dates -fingerprint -sha256
docker exec -u www-data owncloud-server occ user:report
docker exec -u www-data owncloud-server occ group:list
```

### Step 4: บันทึกหลักฐาน

บันทึกวันเวลา ผู้ตรวจ status/exit code และ ticket ของ anomaly ไม่บันทึก secret หรือ full user listing

## ตรวจสอบว่าสำเร็จ

- Checklist ครบตามรอบ
- anomaly มี owner/deadline
- backup/restore evidence มี checksum
- no unexpected listener/restart/failure

## ถ้ามีปัญหา

1. เปิด incident เมื่อ health/data/backup fail
2. หยุด writes เมื่อมี integrity risk
3. ใช้ troubleshooting/DR guide
4. อย่า mark PASS จาก Docker healthy เพียงรายการเดียว

## ข้อควรระวัง

> **WARNING:** backup DB fixed-count validation และ file/config backup gap ต้องคงเป็น open operational risks จนมี change แยกที่ผ่าน review

> **WARNING:** ห้ามใส่ password/token/user data ลง checklist evidence
