# การดูแล Docker ของ ownCloud

## ใช้ทำอะไร

ใช้ดูสถานะ log และควบคุมเฉพาะ container ของ ownCloud

Container ของ ownCloud บน Server-App มี 2 ตัว:

- `owncloud-server`
- `owncloud-redis`

Database อยู่ Server-DB ใน `owncloud-postgres`

## ขั้นตอน

### Step 1: ดูสถานะ

```bash
docker ps --filter name=owncloud --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env ps
```

### Step 2: ดู health และ restart count

```bash
docker inspect --format 'NAME={{.Name}} STATUS={{.State.Status}} HEALTH={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} RESTARTS={{.RestartCount}}' owncloud-server owncloud-redis
```

### Step 3: ดู log

```bash
docker logs --tail 100 --timestamps owncloud-server
docker logs --tail 100 --timestamps owncloud-redis
```

เพิ่ม `--since 30m` เมื่อต้องการช่วงเวลาสั้น

### Step 4: Restart เฉพาะ ownCloud

```bash
docker restart owncloud-server
docker exec -u www-data owncloud-server occ status
```

การ restart ทำให้ Web UI/API หยุดชั่วคราว ต้องประกาศ downtime ก่อน

### Step 5: Stop/Start แบบเจาะจง

```bash
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env stop owncloud-server
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env start owncloud-server
```

ใช้กับ maintenance ที่มีแผนเท่านั้น

### Step 6: ตรวจ Redis โดยไม่ restart

```bash
docker exec owncloud-redis redis-cli ping
```

Restart Redis เฉพาะเมื่อวิเคราะห์แล้วว่า Redis ค้าง:

```bash
docker restart owncloud-redis
docker exec owncloud-redis redis-cli ping
```

## ตรวจสอบว่าสำเร็จ

```bash
docker inspect --format '{{.Name}} {{.State.Health.Status}} restarts={{.RestartCount}}' owncloud-server owncloud-redis
curl -kfsS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/status.php
```

ต้องได้ `healthy` และ HTTP `200`

## ถ้ามีปัญหา

1. ตรวจ log container ที่ fail
2. ตรวจ `df -h` และ `df -i`
3. ตรวจ PostgreSQL/Redis ก่อน restart ซ้ำ
4. ถ้า restart count เพิ่มต่อเนื่อง ให้หยุด restart loop และ rollback config/image ล่าสุด

## ข้อควรระวัง

> **WARNING:** ห้ามใช้ `docker compose down`, `docker compose down -v`, `docker system prune`, `docker volume prune` หรือ image prune โดยไม่ตรวจ impact

> **WARNING:** งาน ownCloud ห้าม restart/exec/rename/recreate `athena-engine-postgres16`

