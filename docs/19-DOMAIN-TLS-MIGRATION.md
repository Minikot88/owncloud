# แผนย้ายไป Domain และ TLS ที่เชื่อถือได้

## ใช้ทำอะไร

ใช้เปลี่ยนจาก SSH tunnel `https://127.0.0.1:8443` ไปเป็น `https://cloud.<approved-domain>` บน port 443 เดิม

## ขั้นตอน

### Step 1: กำหนดชื่อและอนุมัติ

```bash
APPROVED_DOMAIN='cloud.example.org'
SERVER_APP_IP='APPROVED_SERVER_APP_IP'
```

ต้องอนุมัติ domain, DNS zone, certificate issuer, owner, maintenance window และ rollback ก่อน

### Step 2: Backup current config

สำรองพร้อม SHA-256:

- `/opt/owncloud/compose.yml`
- `/opt/owncloud/.env`
- `/mnt/owncloud-data/config/config.php`
- `/etc/nginx/sites-available/owncloud-loopback-8443`
- `/etc/nginx/sites-enabled/`
- certificate metadata

### Step 3: สร้าง DNS

สร้าง A/AAAA ตาม network design ที่อนุมัติ แล้วตรวจ:

```bash
dig +short "${APPROVED_DOMAIN}"
```

IP ต้องตรง Server-App/load balancer ที่อนุมัติ ห้ามชี้ไป private IP ถ้า DNS policy ไม่รองรับ

### Step 4: ติดตั้ง certificate

- ใช้ certificate จาก approved CA
- Private key ต้อง `root:root 0600`
- Certificate chain ต้องครบ
- ห้ามคัดลอก private key ลง workspace/chat

ตัวอย่างตรวจ metadata:

```bash
sudo openssl x509 -in /etc/nginx/ssl/APPROVED_DOMAIN/fullchain.pem -noout -subject -issuer -dates -fingerprint -sha256
sudo stat -c '%A %U:%G %n' /etc/nginx/ssl/APPROVED_DOMAIN/privkey.pem
```

### Step 5: สร้าง Nginx vhost บน 443 เดิม

vhost ต้องมี:

```nginx
listen 443 ssl;
listen [::]:443 ssl;
server_name cloud.example.org;
ssl_certificate /etc/nginx/ssl/APPROVED_DOMAIN/fullchain.pem;
ssl_certificate_key /etc/nginx/ssl/APPROVED_DOMAIN/privkey.pem;
client_max_body_size 2g;
location / {
    proxy_pass http://127.0.0.1:9200;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Port 443;
}
```

แทน example ด้วย approved domain และใช้ hardening/proxy timeouts จาก vhost loopback ที่ผ่าน review

### Step 6: Update ownCloud trusted URL

ตรวจ index ก่อน:

```bash
docker exec -u www-data owncloud-server occ config:system:get trusted_domains
```

ณ audit มี index 0/1 สำหรับ `localhost`/`127.0.0.1`; ถ้ายังเหมือนเดิมให้เพิ่ม index 2:

```bash
docker exec -u www-data owncloud-server occ config:system:set trusted_domains 2 --value="${APPROVED_DOMAIN}"
docker exec -u www-data owncloud-server occ config:system:set overwrite.cli.url --value="https://${APPROVED_DOMAIN}"
```

แก้ `OWNCLOUD_TRUSTED_DOMAINS` และ `OWNCLOUD_OVERWRITE_CLI_URL` ใน root-only `/opt/owncloud/.env` ด้วย เพื่อไม่ให้ค่าหายหลัง recreate

### Step 7: Validate ก่อน reload

```bash
sudo nginx -t
sudo docker compose -f /opt/owncloud/compose.yml --env-file /opt/owncloud/.env config --services
sudo systemctl reload nginx
```

### Step 8: Test โดยยังคง tunnel

```bash
curl --resolve "${APPROVED_DOMAIN}:443:${SERVER_APP_IP}" -fsS -o /dev/null -w '%{http_code}\n' "https://${APPROVED_DOMAIN}/status.php"
openssl s_client -connect "${SERVER_APP_IP}:443" -servername "${APPROVED_DOMAIN}" </dev/null
```

ทดสอบ Browser login, WebDAV, OCS, upload/download และ redirect URL

### Step 9: Cutover DNS และ observe

- ลด TTL ล่วงหน้า
- เปลี่ยน DNS ตาม window
- monitor access/error logs
- คง SSH tunnel เป็น break-glass จน observation gate ผ่าน

### Step 10: Retire temporary tunnel access

หลัง DNS/TLS/WebDAV/OCS/persistence ผ่านและได้รับอนุมัติ:

- ปิด loopback vhost/helper เฉพาะส่วนที่ไม่ต้องใช้แล้ว
- ทดสอบ 443 domain อีกครั้ง
- ห้ามเปิด port ใหม่

## ตรวจสอบว่าสำเร็จ

- DNS ตรง target
- certificate chain/hostname/expiry ถูกต้อง
- Nginx syntax PASS
- ownCloud trusted domain/CLI URL ถูกต้อง
- Web UI/WebDAV/OCS PASS
- external ports ยังเป็น 22/80/443 เท่านั้น

## ถ้ามีปัญหา

1. คืน DNS TTL/record เดิม
2. คืน Nginx/ownCloud config จาก backup
3. กลับใช้ SSH tunnel
4. เก็บ TLS/Nginx evidence โดยไม่เก็บ private key

## ข้อควรระวัง

> **WARNING:** ห้ามเปิด 8443/9200 ต่อ Internet และห้ามเพิ่ม port เมื่อ 443 เดิมรองรับได้

> **WARNING:** ห้ามลบ tunnel/break-glass path ก่อน domain test และ rollback gate ผ่าน
