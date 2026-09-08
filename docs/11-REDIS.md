# Redis และ File Locking

## ใช้ทำอะไร

Redis ใช้ cache และ distributed file locking เพื่อป้องกันการเขียนไฟล์ชนกัน ไม่ใช่ที่เก็บไฟล์จริง

Container ปัจจุบัน: `owncloud-redis`, Docker internal port `6379`, ไม่มี host port

## ขั้นตอน

### Step 1: ตรวจ health

```bash
docker inspect --format 'STATUS={{.State.Status}} HEALTH={{.State.Health.Status}} RESTARTS={{.RestartCount}}' owncloud-redis
docker exec owncloud-redis redis-cli ping
```

ต้องได้ `healthy` และ `PONG`

### Step 2: ยืนยัน ownCloud ใช้ Redis locking

```bash
docker exec -u www-data owncloud-server occ config:system:get memcache.locking
```

ต้องได้ `\OC\Memcache\Redis`

### Step 3: ดู log

```bash
docker logs --tail 100 --timestamps owncloud-redis
```

### Step 4: Restart เมื่อจำเป็น

ประกาศผลกระทบก่อน เพราะ lock/cache จะหายชั่วคราว

```bash
docker restart owncloud-redis
docker exec owncloud-redis redis-cli ping
docker exec -u www-data owncloud-server occ status
```

### Step 5: ตรวจ persistence volume

```bash
docker inspect --format '{{range .Mounts}}{{.Name}} {{.Destination}} {{.RW}}{{end}}' owncloud-redis
```

Volume ปัจจุบันคือ `owncloud-redis-data` ที่ `/data`

## ตรวจสอบว่าสำเร็จ

```bash
docker exec owncloud-redis redis-cli ping
docker exec -u www-data owncloud-server occ background:queue:status
```

Redis ต้องตอบและ background queue ต้องอ่านได้

## ถ้ามีปัญหา

1. ตรวจ memory/disk และ Docker health
2. ตรวจ network `owncloud-network`
3. ตรวจ ownCloud log ว่ามี lock timeout หรือ connection refused
4. Restart Redis ครั้งเดียวหลังเก็บ log
5. ถ้ายัง fail ให้หยุด writes/เข้า maintenance ก่อนแก้ config

## ข้อควรระวัง

> **WARNING:** Redis ไม่ใช่ database หลักและไม่เก็บ binary file ห้ามใช้ Redis backup แทน PostgreSQL/storage backup

> **WARNING:** ห้าม publish `6379` ออก host หรือ Internet

