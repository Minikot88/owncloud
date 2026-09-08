# แผนย้าย File Storage ไป NAS/NFS

## ใช้ทำอะไร

ใช้ย้าย binary storage จาก local disk ไป NAS โดยรักษา path `/mnt/owncloud-data` เดิม เพื่อไม่ต้องเปลี่ยน Compose

ปัจจุบัน: `/mnt/owncloud-data` -> local filesystem

เป้าหมาย: `/mnt/owncloud-data` -> approved NAS/NFS mount

## ขั้นตอน

### Step 1: Preflight

กำหนดค่าใน maintenance window:

```bash
NAS_EXPORT='NAS_HOST:/approved/export'
NAS_STAGE=/mnt/owncloud-data.nas-staging
MIGRATION_ID="$(date -u +%Y%m%dT%H%M%SZ)"
LOCAL_ROLLBACK="/mnt/owncloud-data.local-rollback-${MIGRATION_ID}"
```

ตรวจ capacity, NFS version, UID/GID mapping, latency, locking, backup และ firewall ระหว่าง App/NAS เท่านั้น

ตรวจ client prerequisite:

```bash
command -v rsync
command -v mount.nfs4
```

Audit ปัจจุบันพบ `rsync` แต่ยังไม่มี `mount.nfs4`; ก่อน migration ต้องติดตั้ง Ubuntu official package `nfs-common` ผ่าน change ที่อนุมัติ แล้วตรวจ command ซ้ำ ห้ามสร้าง replacement tool เอง

### Step 2: Backup ก่อนย้าย

- PostgreSQL backup + isolated restore
- current storage/config backup + SHA-256
- Compose/Nginx baseline
- mount/fstab baseline

### Step 3: Mount NAS ที่ staging path

```bash
sudo install -d -o www-data -g root -m 0750 "${NAS_STAGE}"
sudo mount -t nfs4 "${NAS_EXPORT}" "${NAS_STAGE}"
findmnt -T "${NAS_STAGE}"
sudo -u www-data test -r "${NAS_STAGE}"
sudo -u www-data test -w "${NAS_STAGE}"
```

### Step 4: Initial rsync ขณะระบบยังเปิด

```bash
sudo rsync -aHAX --numeric-ids --delete-delay --info=progress2 /mnt/owncloud-data/ "${NAS_STAGE}/"
```

ตรวจ owner/mode และ sample checksum; อย่า cutover จาก initial sync อย่างเดียว

### Step 5: Freeze writes และ final sync

```bash
docker exec -u www-data owncloud-server occ maintenance:mode --on
sudo docker stop owncloud-server
sudo rsync -aHAX --numeric-ids --delete --itemize-changes /mnt/owncloud-data/ "${NAS_STAGE}/"
```

สร้าง manifests:

```bash
sudo sh -c 'cd /mnt/owncloud-data && find . -type f -print0 | sort -z | xargs -0 sha256sum' > "/tmp/source-${MIGRATION_ID}.sha256"
sudo sh -c "cd '${NAS_STAGE}' && find . -type f -print0 | sort -z | xargs -0 sha256sum" > "/tmp/nas-${MIGRATION_ID}.sha256"
diff -u "/tmp/source-${MIGRATION_ID}.sha256" "/tmp/nas-${MIGRATION_ID}.sha256"
```

### Step 6: เปลี่ยน mount โดยรักษา path เดิม

1. เพิ่ม NFS entry ใน `/etc/fstab` หลังสำรองไฟล์
2. unmount staging
3. ย้าย local directory เป็น rollback copy
4. สร้าง mountpoint เดิมและ mount ตาม fstab

```bash
sudo cp --preserve=all /etc/fstab "/var/backups/owncloud/fstab.before-${MIGRATION_ID}"
sudo umount "${NAS_STAGE}"
sudo mv /mnt/owncloud-data "${LOCAL_ROLLBACK}"
sudo install -d -o www-data -g root -m 0750 /mnt/owncloud-data
sudo mount /mnt/owncloud-data
findmnt -T /mnt/owncloud-data
stat -c '%A %U:%G %n' /mnt/owncloud-data
```

### Step 7: Start และ test

```bash
sudo docker start owncloud-server
docker exec -u www-data owncloud-server occ status
docker exec -u www-data owncloud-server occ maintenance:mode --off
```

ทดสอบ existing file read-only, upload/download/rename/delete, OCS share, Redis locking, cron และ restart persistence

### Step 8: Rollback เมื่อ fail

```bash
docker exec -u www-data owncloud-server occ maintenance:mode --on
sudo docker stop owncloud-server
sudo umount /mnt/owncloud-data
sudo rmdir /mnt/owncloud-data
sudo mv "${LOCAL_ROLLBACK}" /mnt/owncloud-data
sudo cp --preserve=all "/var/backups/owncloud/fstab.before-${MIGRATION_ID}" /etc/fstab
sudo docker start owncloud-server
docker exec -u www-data owncloud-server occ maintenance:mode --off
```

ใช้ rollback เฉพาะเมื่อ `LOCAL_ROLLBACK` ถูกตรวจ target แล้วและไม่มี write หลัง cutover ที่ยังไม่ได้ delta-copy กลับ

## ตรวจสอบว่าสำเร็จ

- mount path ยังเป็น `/mnt/owncloud-data`
- owner/mode และ checksum match
- logical file count/size match
- WebDAV/OCS/persistence ผ่าน
- PostgreSQL ไม่เก็บ binary
- Project ยังเข้าถึงผ่าน API เท่านั้น

## ถ้ามีปัญหา

- permission/UID mapping ผิด: หยุดก่อน start
- checksum mismatch: final sync ใหม่ ห้าม cutover
- NFS latency/lock fail: rollback local storage
- mount หายหลัง reboot: rollback แล้วแก้ fstab ใน staging test

## ข้อควรระวัง

> **WARNING:** ห้าม mount NAS ทับ local directory ขณะ ownCloud ยังเขียน และห้ามลบ local rollback copy จนผ่าน retention gate

> **WARNING:** ห้ามเปลี่ยน Compose path; รักษา `/mnt/owncloud-data` เดิม

> **WARNING:** NAS/NFS port ต้องเปิดเฉพาะ private network ที่อนุมัติ ไม่เปิด Internet

> **WARNING:** `mount.nfs4` ยังไม่ติดตั้ง ณ วัน audit; คู่มือนี้เป็น future plan และห้ามเริ่ม cutover จน prerequisite gate ผ่าน
