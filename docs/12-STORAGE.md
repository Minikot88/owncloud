# File Storage `/mnt/owncloud-data`

## ใช้ทำอะไร

อธิบายพื้นที่เก็บ binary file จริง การตรวจ capacity/permission และการ backup อย่างปลอดภัย

เส้นทางจริง:

- Host: `/mnt/owncloud-data`
- Container: `/mnt/data`
- ownCloud data directory: `/mnt/data/files`
- Owner/mode ปัจจุบัน: `www-data:root`, `0750`

## ขั้นตอน

### Step 1: ตรวจ mount/permission

```bash
findmnt -T /mnt/owncloud-data
stat -c '%A %U:%G %n' /mnt/owncloud-data
docker inspect --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{println}}{{end}}' owncloud-server
```

### Step 2: ตรวจพื้นที่และ inode

```bash
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
sudo du -sh -x /mnt/owncloud-data
```

`du -sh -x` เป็นการตรวจแบบตื้นใน filesystem เดียว ไม่ใช้ `du /` หรือ scan ทั้ง Server

### Step 3: เข้าใจสิ่งที่เก็บ

- `/mnt/owncloud-data`: binary, config และไฟล์ที่ ownCloud จัดการ
- PostgreSQL: users, permissions, shares, file index, metadata
- Redis: cache/lock ชั่วคราว

### Step 4: ทำ manual storage backup ที่สอดคล้องกัน

1. ประกาศ maintenance
2. เปิด maintenance mode
3. ทำ PostgreSQL backup ในช่วงเดียวกัน
4. archive storage/config ไปยัง approved backup location
5. สร้าง SHA-256

```bash
docker exec -u www-data owncloud-server occ maintenance:mode --on
STORAGE_BACKUP_ID="$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -o root -g root -m 0700 "/var/backups/owncloud/manual-${STORAGE_BACKUP_ID}"
sudo tar --acls --xattrs --numeric-owner -C /mnt -czf "/var/backups/owncloud/manual-${STORAGE_BACKUP_ID}/owncloud-data.tar.gz" owncloud-data
sudo sha256sum "/var/backups/owncloud/manual-${STORAGE_BACKUP_ID}/owncloud-data.tar.gz" | sudo tee "/var/backups/owncloud/manual-${STORAGE_BACKUP_ID}/SHA256SUMS" >/dev/null
docker exec -u www-data owncloud-server occ maintenance:mode --off
```

## ตรวจสอบว่าสำเร็จ

```bash
sudo tar -tzf "/var/backups/owncloud/manual-${STORAGE_BACKUP_ID}/owncloud-data.tar.gz" | sed -n '1,20p'
sudo sh -c "cd /var/backups/owncloud/manual-${STORAGE_BACKUP_ID} && sha256sum -c SHA256SUMS"
docker exec -u www-data owncloud-server occ status
```

## ถ้ามีปัญหา

1. ถ้า disk/inode ใกล้เต็ม ให้หยุด upload และวางแผนขยายพื้นที่
2. ถ้า permission ผิด ห้าม `chmod -R` ทันที ให้เทียบ owner/mode กับ backup/evidence
3. ถ้า mount หาย ให้หยุด ownCloud ก่อนเพื่อป้องกันเขียนลง mountpoint ว่าง
4. ถ้า backup checksum fail ให้เก็บไฟล์ไว้เป็น evidence และสร้างชุดใหม่

## ข้อควรระวัง

> **WARNING:** Nginx และ Project/Application ห้าม serve/mount/read `/mnt/owncloud-data` ตรง ทุกการเข้าถึงไฟล์ต้องผ่าน ownCloud WebDAV/OCS API

> **WARNING:** ณ วันที่ audit ยังไม่มี scheduled backup สำหรับ storage/config บน Server-App; verified migration snapshot เป็น point-in-time ไม่ใช่ daily backup

> **WARNING:** ห้ามลบหรือย้าย path นี้ และห้าม recursive chown/chmod โดยไม่มี backup + rollback plan

