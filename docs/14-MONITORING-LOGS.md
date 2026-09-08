# Monitoring และ Logs

## ใช้ทำอะไร

ใช้ตรวจ health, restart, disk, background jobs, backup และ log ของทุกส่วนโดยไม่อ่าน secret

## ขั้นตอน

### Step 1: Quick Health Check — Server-App

```bash
docker ps --filter name=owncloud --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker inspect --format '{{.Name}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
docker exec -u www-data owncloud-server occ status
docker exec owncloud-redis redis-cli ping
curl -kfsS -o /dev/null -w 'owncloud_https=%{http_code}\n' https://127.0.0.1:8443/status.php
systemctl --failed --no-pager
```

### Step 2: Quick Health Check — Server-DB

```bash
ssh db-server
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker inspect --format '{{.Name}} health={{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-postgres
systemctl is-active owncloud-postgres-backup.timer
systemctl --failed --no-pager
```

ตรวจ `athena-engine-postgres16` ด้วย `docker ps/inspect` metadata เท่านั้น ห้าม exec/restart

### Step 3: ดู application logs

```bash
sudo tail -n 100 /mnt/owncloud-data/files/owncloud.log
docker logs --tail 100 --timestamps owncloud-server
docker logs --tail 100 --timestamps owncloud-redis
sudo tail -n 100 /var/log/nginx/access.log
sudo tail -n 100 /var/log/nginx/error.log
```

### Step 4: ดู PostgreSQL/backup logs

บน Server-DB:

```bash
docker logs --tail 100 --timestamps owncloud-postgres
sudo journalctl -u owncloud-postgres-backup.service --since '24 hours ago' --no-pager
systemctl list-timers --all --no-pager | grep owncloud-postgres-backup
```

### Step 5: ตรวจ cron/background jobs

```bash
docker exec -u www-data owncloud-server occ config:app:get core backgroundjobs_mode
docker exec -u www-data owncloud-server occ background:queue:status
docker top owncloud-server -eo pid,ppid,user,comm,args
```

ต้องเห็น mode `cron` และ process `/usr/sbin/cron -l`

### Step 6: ตรวจ capacity

```bash
df -h /mnt/owncloud-data
df -i /mnt/owncloud-data
sudo du -sh -x /mnt/owncloud-data
```

### Step 7: ตรวจ backup failure

```bash
sudo systemctl status owncloud-postgres-backup.service --no-pager
sudo journalctl -p err -u owncloud-postgres-backup.service --no-pager
```

อย่าดูแค่มี `.dump`; ต้องตรวจ service exit status และ SHA-256

## ตรวจสอบว่าสำเร็จ

- ownCloud/Redis/PostgreSQL healthy
- restart count ไม่เพิ่มโดยไม่ทราบสาเหตุ
- HTTP 200
- background queue มี `Last Checked` ใหม่
- backup timer active และ run ล่าสุดสำเร็จ
- disk/inode ไม่ใกล้เต็ม
- failed systemd services = 0

## ถ้ามีปัญหา

1. จับ timestamp และชื่อ component
2. เก็บ log ช่วงสั้นด้วย `--since`
3. ตรวจ dependency ตามลำดับ PostgreSQL -> storage -> Redis -> ownCloud -> Nginx
4. ถ้า error เกิดหลัง change ให้ rollback change ล่าสุด
5. ถ้าข้อมูล/permission ไม่ตรง ให้ maintenance ก่อนแก้

## ข้อควรระวัง

> **WARNING:** Log อาจมี username/path/IP ซึ่งเป็นข้อมูลภายใน ห้ามส่งออกนอกระบบ TLP:RED

> **WARNING:** healthcheck ของ `owncloud-postgres` ปัจจุบันสร้าง peer-auth failure log noise เป็นระยะ Docker healthy จึงไม่ใช่หลักฐาน application login เพียงอย่างเดียว

> **WARNING:** ไม่มี scheduled file/config backup บน Server-App และ backup script DB มี fixed-count validation ต้อง monitor เป็นพิเศษ

