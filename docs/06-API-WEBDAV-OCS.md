# WebDAV และ OCS API

## ใช้ทำอะไร

ใช้ให้ developer จัดการไฟล์และ shares ผ่าน API โดยไม่แตะ storage หรือ ownCloud tables โดยตรง

## ขั้นตอน

### Step 1 — ตั้งค่า placeholders

```bash
export OWNCLOUD_URL='https://127.0.0.1:8443'
export USERNAME='USERNAME'
export APP_PASSWORD='APP_PASSWORD'
export SHARE_WITH='USERNAME'
```

### Step 2 — ใช้ WebDAV

```bash
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X PROPFIND -H 'Depth: 1' "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X MKCOL "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -T "./local-file" "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder/file"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -o "./downloaded-file" "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder/file"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X MOVE -H "Destination: ${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder/renamed-file" "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder/file"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X DELETE "${OWNCLOUD_URL}/remote.php/dav/files/${USERNAME}/folder/renamed-file"
```

### Step 3 — ใช้ OCS shares

```bash
curl -k -u "${USERNAME}:${APP_PASSWORD}" -H 'OCS-APIRequest: true' -d 'path=/folder/file' -d 'shareType=0' -d "shareWith=${SHARE_WITH}" -d 'permissions=1' "${OWNCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -H 'OCS-APIRequest: true' "${OWNCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X PUT -H 'OCS-APIRequest: true' -d 'permissions=1' "${OWNCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares/SHARE_ID?format=json"
curl -k -u "${USERNAME}:${APP_PASSWORD}" -X DELETE -H 'OCS-APIRequest: true' "${OWNCLOUD_URL}/ocs/v2.php/apps/files_sharing/api/v1/shares/SHARE_ID?format=json"
```

permission bitmask: read=1, update=2, create=4, delete=8, share=16. รวมเฉพาะสิทธิ์จำเป็น; `-k` ใช้เฉพาะ loopback self-signed certificate ปัจจุบัน

## ตรวจสอบว่าสำเร็จ

PROPFIND/OCS ตอบสำเร็จ, ไฟล์อยู่ตาม path, และ share ทดสอบได้ตาม permissions ที่กำหนด

## ถ้ามีปัญหา

ตรวจ tunnel, URL/path, app password, สิทธิ์ และ header `OCS-APIRequest: true`. อย่าใส่ credential ใน command history หรือ log

## ข้อควรระวัง

> **WARNING:** `DELETE` และ `MOVE` เปลี่ยนข้อมูลจริง; ทดสอบ path ในพื้นที่ที่อนุมัติก่อน และอย่าใช้ credential จริงในเอกสารหรือ source code
