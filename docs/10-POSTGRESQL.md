# PostgreSQL สำหรับ ownCloud

## ใช้ทำอะไร

ใช้ตรวจ connection, schema, role, health และ backup ของฐานข้อมูล ownCloud บน Server-DB

Server-DB มี PostgreSQL 2 container ที่แยกกัน:

| Container | Host port | หน้าที่ |
|---|---:|---|
| `athena-engine-postgres16` | `10.8.12.11:5432` | Production ของระบบอื่น — ห้ามแตะ |
| `owncloud-postgres` | `10.8.12.11:5433` | Production DB ของ ownCloud |

## ขั้นตอน

### Step 1: เข้า Server-DB

จาก Server-App:

```bash
ssh db-server
```

### Step 2: ตรวจ container โดยไม่เปลี่ยน state

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker inspect --format 'NAME={{.Name}} HEALTH={{.State.Health.Status}} RESTARTS={{.RestartCount}}' owncloud-postgres
docker exec -u postgres owncloud-postgres postgres --version
```

ค่าปัจจุบันคือ PostgreSQL `16.13`, healthy, host bind `10.8.12.11:5433`

### Step 3: ตรวจ database/role/schema

```bash
docker exec -u postgres owncloud-postgres psql -X -v ON_ERROR_STOP=1 -d owncloud -c "select current_database(), current_setting('server_version');"
docker exec -u postgres owncloud-postgres psql -X -v ON_ERROR_STOP=1 -d owncloud -c "select nspname from pg_namespace where nspname in ('public','owncloud_integration') order by 1;"
docker exec -u postgres owncloud-postgres psql -X -v ON_ERROR_STOP=1 -d owncloud -c "select count(*) as owncloud_tables from pg_tables where schemaname='public' and tablename like 'oc\\_%' escape '\\';"
```

ต้องเห็น database `owncloud`, schema 2 ชุด และ ownCloud-managed tables 51 ตาราง

### Step 4: แยก ownership

- `public.oc_*`: ownCloud เป็นผู้สร้าง/จัดการ
- `owncloud_integration.*`: custom metadata/reference
- `owncloud_app`: login role ของ ownCloud
- `owncloud_integration_app`: least-privilege integration login
- `owncloud_integration_owner`: schema owner แบบ NOLOGIN

ตรวจ role flags:

```bash
docker exec -u postgres owncloud-postgres psql -X -d owncloud -c "select rolname,rolsuper,rolcreaterole,rolcreatedb,rolcanlogin,rolbypassrls from pg_roles where rolname like 'owncloud%' order by rolname;"
```

### Step 5: ตรวจ network/access control

จาก Server-App:

```bash
nc -zvw3 10.8.12.11 5433
```

บน Server-DB:

```bash
docker exec owncloud-postgres sed -n '1,120p' /etc/postgresql/pg_hba.conf
sudo ufw status verbose
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

HBA ต้องอนุญาต `owncloud_app` จาก `10.8.12.10/32` เท่านั้น

> Docker DNAT แปลง host port 5433 เป็น container port 5432 ก่อนเข้า `DOCKER-USER` จึงเห็น firewall match ที่ destination port 5432

### Step 6: ตรวจ backup timer

```bash
systemctl is-enabled owncloud-postgres-backup.timer
systemctl is-active owncloud-postgres-backup.timer
systemctl list-timers --all --no-pager | grep owncloud-postgres-backup
sudo journalctl -u owncloud-postgres-backup.service -n 100 --no-pager
```

Schedule ปัจจุบัน: 02:30 ทุกวัน, randomized delay ไม่เกิน 15 นาที, retention 30 วัน

## ตรวจสอบว่าสำเร็จ

```bash
docker exec -u postgres owncloud-postgres psql -X -At -d owncloud -c 'select 1;'
docker exec -u postgres owncloud-postgres psql -X -At -d owncloud -c "select count(*) from owncloud_integration.projects;"
```

ต้องได้ `1` และ projects `10`

## ถ้ามีปัญหา

1. ตรวจ bind `10.8.12.11:5433`
2. ตรวจ HBA ว่ามี `10.8.12.10/32`
3. ตรวจ UFW/DOCKER-USER โดยไม่แก้ rule ทันที
4. ตรวจ `docker logs --tail 100 owncloud-postgres`
5. ถ้า backup fail ให้เก็บ dump/log ไว้และตรวจ unit ก่อนรันซ้ำ

## ข้อควรระวัง

> **WARNING:** ห้าม custom application เขียน `public.oc_*` และห้ามสร้าง/แก้ ownCloud table ด้วย custom SQL

> **WARNING:** `owncloud-postgres` healthcheck ปัจจุบันอาจสร้าง log `peer authentication failed` แม้ Docker รายงาน healthy ให้ตรวจ application connection ร่วมด้วย

> **WARNING:** ห้ามเรียกคำสั่งใด ๆ ภายใน `athena-engine-postgres16` จากคู่มือนี้

