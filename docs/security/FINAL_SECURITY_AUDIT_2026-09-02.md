# FINAL OWNCLOUD SECURITY AUDIT

> **TLP:RED — สำหรับผู้ดูแลระบบที่ได้รับอนุญาตเท่านั้น**  
> วันที่ตรวจ: 2026-09-02 (Asia/Bangkok)  
> ขอบเขต: Server-App `10.8.12.10`, Server-DB `10.8.12.11`, ownCloud Production และทรัพยากรที่เกี่ยวข้อง

## สรุปผล

| ระดับ | คงเหลือ |
|---|---:|
| Critical | 0 |
| High | 3 |
| Medium | 6 |
| Low | 5 |
| Informational | 6 |

**FINAL STATUS: NOT READY**

Production ใช้งานได้และ regression ผ่าน แต่ยังไม่พร้อมขอเปิด Internet/Domain/SIA จนกว่าจะ rotate/revoke credential ที่เคยอยู่ใน Git history และยืนยันผลซ้ำ ห้ามตีความรายงานนี้ว่า “ไม่มีช่องโหว่ 100%” เพราะไม่มี vulnerability scanner ที่ทำงานสำเร็จในรอบนี้

## ผลตาม Acceptance

| หัวข้อ | ผล | หลักฐานย่อ |
|---|---|---|
| Known Exploitable Findings Remaining | **LIST** | credential exposure 3 รายการด้านล่าง; ไม่พบหลักฐานว่าถูกนำไปใช้ แต่ยังปิดความเสี่ยงไม่ได้ |
| OS | WARN | Ubuntu 24.04.4; standard security updates = 0; ทั้งสองเครื่องยังต้อง reboot เพื่อ activate update |
| SSH | WARN | key-only, root login off, fail2ban active; Server-App port 22 ยังรับ Anywhere เพราะไม่มี Admin/VPN CIDR ที่อนุมัติ |
| Nginx | WARN | config PASS, CSP ชุดเดียว, hidden-file direct access 404; มี legacy duplicate headers และยังไม่เปิด HSTS บน loopback/self-signed |
| ownCloud | WARN | 11.0.0 healthy; security apps enabled; custom `groupalert` disabled; enterprise `admin_audit` ใช้ไม่ได้กับ Community |
| Docker | WARN | privileged=false, no Docker socket, private/internal binds ถูกต้อง; containers ยังเป็น writable root filesystem และบางตัวรันเป็น root |
| PostgreSQL | WARN | owncloud-postgres 16.15 healthy; source restricted; SCRAM; TLS ภายในยัง off |
| Redis | PASS | Redis 7.4.11 healthy, ไม่มี host-published 6379, ใช้ cache/file locking |
| Storage | PASS | `/mnt/owncloud-data` permission ถูกต้อง, ownCloud mount เพียง container เดียว, Nginx/Application อื่นไม่ serve/mount ตรง |
| WebDAV | PASS | unauthenticated 401; authenticated PROPFIND/upload/download/move/delete ผ่าน |
| OCS API | PASS | capabilities และ share create/read/update/delete/revoke ผ่าน |
| Project Isolation | WARN | RLS/FORCE RLS และ cross-project denial ที่ DB ผ่าน; ยังไม่ได้ทดสอบ distinct service credential ครบ project01–project10 end-to-end |
| Secrets | **FAIL** | tracked index/files ถูก sanitize แล้ว แต่มี root-only local copies ที่จำเป็นต้องคงไว้ และ credential ใน history/นอก scope ยัง rotate ไม่ครบ |
| Backup | WARN | PostgreSQL backup ผ่าน; App/config/storage มี automated online copy + checksum/retention แต่ไม่ใช่ cross-system atomic recovery point ร่วมกับ DB |
| Restore | WARN | isolated PostgreSQL restore ผ่าน; App/config/storage archive ยังไม่ได้ restore rehearsal |
| Unexpected Network-facing Ports | NONE | Server-App 22/80/443; 8443/9200 loopback; Server-DB 5432/5433 private bind |
| Vulnerability Scan | **NOT AVAILABLE** | deep scan transport ปิดก่อนคืน scan ID; ไม่มี approved local scanner จึงรายงานเป็น Host/Container Security Assessment เท่านั้น |
| Existing Production | PASS | frontend, backend, worker, Nginx, HTTPS และ containers healthy |
| Failed Services | 0 | ทั้ง Server-App และ Server-DB |
| Rollback | PASS | pre-change backup + SHA-256; compose rollback ถูกทดสอบจริงเมื่อ `admin_audit` ไม่ compatible |
| DOMAIN | NOT CONFIGURED — PENDING | ไม่อยู่ใน scope รอบนี้ |
| SIA | NOT REQUESTED / PENDING | ไม่เชื่อมต่อหรือแก้ SIA ในรอบนี้ |

## Finding ที่ยังเปิด

### High

| ID | Finding | สถานะ / สิ่งที่ต้องทำ |
|---|---|---|
| H-01 | Server-App operator sudo password เคยถูก commit และ credential ปัจจุบันยังไม่ได้ rotate | **OPEN** — เปลี่ยน password ด้วย operator ที่ได้รับอนุญาต แล้วทดสอบ sudo/SSH; ห้ามบันทึกรหัสใหม่ลง repository |
| H-02 | DBeaver/research database credential เคยอยู่ใน Git history; สถานะ credential ปัจจุบันยืนยันไม่ได้โดยไม่แตะฐานข้อมูลระบบอื่น | **OPEN — EXTERNAL CREDENTIAL ROTATION REQUIRED** — ให้ owner ของ `athena-engine-postgres16` rotate และตรวจ dependency; งานนี้ไม่แตะ container ดังกล่าว |
| H-03 | private RSA key ของ SIA เคยถูก commit; active/revoked status ไม่ทราบ และ SIA ไม่อยู่ใน authorization | **OPEN — OWNER REVOCATION REQUIRED** — ให้ SIA owner revoke/replace และยืนยัน inventory ก่อนล้าง Git history |

ไม่มีหลักฐานว่าทั้งสามรายการถูกนำไปใช้โจมตี แต่การเปิดเผย credential ที่อาจยังใช้ได้ถือเป็น exploitable path จนกว่าเจ้าของสิทธิ์จะ rotate/revoke และ retest

### Medium

| ID | Finding | การควบคุมปัจจุบัน / แนวทางปิด |
|---|---|---|
| M-01 | SSH 22 ของ Server-App ยังอนุญาต source กว้าง | password/root login ปิดและ fail2ban ทำงาน; ปิดเมื่อได้รับ approved Admin/VPN CIDR และมี lockout test |
| M-02 | `owncloud-postgres` ใช้ `ssl=off` | bind private `10.8.12.11:5433` และ firewall allow เฉพาะ `10.8.12.10/32`; วางแผน TLS/mTLS แยกพร้อม compatibility test |
| M-03 | ทั้งสอง host แสดง reboot required | standard security updates คงเหลือ 0; นัด maintenance/reboot ทีละเครื่องพร้อม regression และ rollback |
| M-04 | dedicated administrator audit coverage ไม่ครบ | ownCloud Community ใช้ `admin_audit` enterprise ไม่ได้และ host auditd inactive; เก็บ core/Nginx/Docker logs แล้ววางแผน approved audit facility |
| M-05 | project01–project10 ยังไม่มี distinct service-credential E2E matrix | DB RLS structural/cross-project gate ผ่าน; ทดสอบ credential แยกครบ 10 projects ก่อนเปิดใช้งาน integration ภายนอก |
| M-06 | App/config/storage backup เป็น online copy และยังไม่มี restore rehearsal | มี SHA-256/retention และ PostgreSQL isolated restore ผ่าน แต่ยังไม่พิสูจน์ coordinated recovery point; ทดสอบ restore แบบ isolated และกำหนด maintenance/quiesce procedure |

### Low

1. ownCloud containers ยังไม่ได้ใช้ read-only root filesystem, non-root user และ `no-new-privileges` ครบทุกตัว; ต้องทดสอบ compatibility ก่อนเปลี่ยน
2. TOTP app พร้อมใช้งานแต่ยังไม่ได้ enforce สำหรับ admin
3. `qownnotesapi` มี legacy accepted integrity warning; core integrity ไม่พบ mismatch
4. response ยังมี legacy duplicate `X-Frame-Options`/`X-Content-Type-Options` และ cookie หนึ่งรายการไม่มี SameSite; ไม่พบ CSP ซ้ำ
5. มี non-security package updates และ host agents/loopback listeners เดิมที่ต้องติดตามตามรอบ maintenance

### Informational

1. Vulnerability scanner ไม่พร้อมใช้งานในรอบนี้ จึงไม่มีข้ออ้างว่า CVE = 0
2. HSTS ถูก defer จนมี approved domain และ trusted TLS certificate
3. `startTime/reportAllChanges` จัดเป็น browser/extension injection จาก clean-browser comparison
4. Media Viewer translation messages และ `NavigationDuplicated` เป็น non-fatal console noise; Image Viewer ทำงาน
5. Domain/DNS/TLS public cutover ยังไม่ทำ
6. SIA assessment/connectivity ยังไม่ทำ

## Finding ที่ปิดแล้ว

- ownCloud SSH private key เดิมถูก revoke; key ใหม่อยู่นอก repository และ login ไป Server-App/Server-DB ผ่าน
- private-key files ที่ยืนยันแล้วถูก untrack และเพิ่ม exact path ใน `.gitignore`; current tracked worktree scan ไม่พบ private-key marker
- DBeaver guide ถูกลบ plaintext password และเปลี่ยนเป็น placeholder
- Redis อัปเดตจาก 7.4.10 เป็น 7.4.11 แบบ digest-pinned; health/regression ผ่าน
- ownCloud PostgreSQL อัปเดตจาก 16.13 เป็น 16.15 แบบ digest-pinned; isolated restore/regression ผ่าน
- PostgreSQL healthcheck ใช้ local socket/ถูก role โดยไม่เปิดเผย credential; health ผ่านและไม่มี peer-auth noise ที่เกี่ยวข้อง
- backup validation ไม่ใช้ fixed table/row count แล้ว; ตรวจ required schemas/tables, roles, ACL, constraints, indexes, RLS, catalog และ dynamic counts หลัง isolated restore
- automated App/config backup ถูกติดตั้งพร้อม SHA-256, root-only permission และ retention
- `brute_force_protection`, `password_policy`, `twofactor_totp` ถูก enable ด้วย supported OCC; password policy weak/strong negative-positive test ผ่าน
- `groupalert` custom app ที่มี latent cross-group/XSS design risk ถูก disable ด้วย OCC; app/data เดิมถูกเก็บไว้และ endpoint ไม่ให้ข้อมูลแล้ว
- การทดลอง `admin_audit` ถูก rollback ทั้ง compose/app config เพราะ Community license ไม่รองรับ; `occ status` กลับมาผ่าน

## Architecture และ Network ที่ยืนยัน

### Server-App

- Network-facing TCP: `22`, `80`, `443`
- Loopback ownCloud: `127.0.0.1:8443`, `127.0.0.1:9200`
- `owncloud-server`: `owncloud/server:11.0.0`, healthy
- `owncloud-redis`: `redis:7.4.11-alpine` digest-pinned, healthy, no host port
- MariaDB runtime/container/volume: none
- `/mnt/owncloud-data`: `www-data:root`, mode `0750`; only `owncloud-server` mounts it
- Additional loopback-only listeners belong to existing applications/host agents and are not newly exposed

### Server-DB

- `athena-engine-postgres16`: healthy, restart count unchanged, **Modified: NO**
- immutable baseline hash: `ca68ea2db679135aea0849d6c21d4dfe88ac2dd681882b75ef4f6a08bc5fc246`
- `owncloud-postgres`: PostgreSQL `16.15`, healthy, `10.8.12.11:5433 -> 5432`
- allow source: `10.8.12.10/32` only; other source ถูก drop ใน DOCKER-USER post-DNAT path
- database `owncloud`: ownCloud-managed `public.oc_*` 74 tables
- schema `owncloud_integration`: 6 tables, projects 10, RLS/FORCE RLS, no BYTEA/plaintext token

## Regression Evidence

- Web UI `200`; HTTP vhost redirect `301`; Nginx config test PASS
- WebDAV: unauth `401`; PROPFIND `207`; upload `201`; download checksum MATCH; MOVE `201`; DELETE `204`
- OCS: capabilities PASS; share lifecycle PASS; revoked share returned `404`
- Redis `PONG`; ownCloud `memcache.locking` = Redis
- official ownCloud cron wrapper PASS
- direct `/.env` และ `/config/config.php` = `404`; traversal unauthenticated = `401`
- direct storage paths ไม่ถูก serve เป็น public binary
- Existing backend/frontend/worker/Nginx/HTTPS PASS
- failed systemd services = 0 ทั้งสอง host
- `athena-engine-postgres16` baseline hash ไม่เปลี่ยน

## Backup / Restore / Rollback

### Pre-hardening rollback

- Server-App: `/var/backups/owncloud-security-hardening/20260902T044733Z`
- Server-DB: `/var/backups/owncloud-security-hardening/20260902T044733Z`
- SHA-256 validation: PASS

### Current verified backups

- App/config/files policy backup: `/var/backups/owncloud-app/20260902T063753Z`
- PostgreSQL backup: `/var/backups/owncloud-postgres/20260902T065005Z`
- MariaDB rollback-only archive retained: `/var/backups/owncloud-pg-migration/20260830T035016Z`
- SHA-256: PASS
- Isolated PostgreSQL restore: PASS
- App/config/storage restore rehearsal: NOT TESTED
- Cross-system atomic DB + file recovery point: NO; current file/config job is an online copy
- temporary restore container/volume after cleanup: NONE

## Production modified

### Server-App

- `/etc/ssh/sshd_config.d/00-codex-security-hardening.conf`; SSH config reload, root login disabled
- operator `authorized_keys`; new key authorized and old ownCloud key revoked
- `/opt/owncloud/compose.yml`; Redis image pin updated; failed enterprise-audit experiment fully rolled back
- containers/resources: `owncloud-redis` updated; `owncloud-server` recreated only where required and final regression passed
- ownCloud app/config state: brute-force protection, password policy, TOTP capability enabled; `groupalert` and unsupported `admin_audit` disabled
- `/usr/local/sbin/owncloud-app-file-config-backup`
- `/etc/systemd/system/owncloud-app-file-config-backup.service`
- `/etc/systemd/system/owncloud-app-file-config-backup.timer`
- `/etc/owncloud/owncloud-app-backup.conf`

### Server-DB

- `/opt/owncloud-postgres-finalization/config/compose.yaml`; ownCloud PostgreSQL image/healthcheck updated
- `/usr/local/sbin/owncloud-postgres-backup`; structural validation and isolated restore hardened
- ownCloud backup systemd timer/service revalidated
- `owncloud-postgres` updated/recreated only; data persistence and restore passed
- `athena-engine-postgres16`: **not modified, not restarted, not recreated**

## Local repository modified

- `.gitignore` exact credential paths
- secret-bearing tracked files removed from index while approved local copies were retained where required
- access/DBeaver/tunnel/OpenSCAP handoff references changed to external SSH key path/placeholder
- pinned Compose files, backup scripts/systemd units และ SSH baseline synced with Production
- user-owned unrelated Nginx working-tree edit was not modified by this audit

## Required actions before READY

1. Rotate Server-App operator password; validate sudo/SSH and store only in approved secret manager.
2. Have `athena-engine-postgres16` owner rotate the exposed research DB credential without Codex touching that production container.
3. Have SIA owner revoke/replace the exposed RSA key and confirm whether it was active.
4. Rewrite/purge Git history only after owners rotate all affected credentials and an explicit repository-wide change window is approved.
5. Restrict SSH source after approved Admin/VPN CIDR is known and lockout test is prepared.
6. Schedule host reboots with full regression.
7. Complete project01–project10 distinct-credential isolation test.
8. Perform an isolated App/config/storage restore rehearsal and document maintenance/quiesce procedure for a coordinated DB + file recovery point.
9. Run an approved vulnerability scan after hardening, then triage/close all relevant Critical/High/Medium findings.

## Official references reviewed

- [ownCloud Server release notes](https://doc.owncloud.com/server_release_notes.html)
- [ownCloud Server releases](https://doc.owncloud.com/server_releases.html)
- [ownCloud password policy](https://doc.owncloud.com/server/11.0/admin_manual/configuration/server/security/password_policy.html)
- [ownCloud server hardening](https://doc.owncloud.com/server/11.0/admin_manual/configuration/server/harden_server.html)
- [ownCloud login policies](https://doc.owncloud.com/server/11.0/admin_manual/configuration/user/login_policies.html)
- [ownCloud admin audit availability](https://doc.owncloud.com/server/11.0/admin_manual/enterprise/logging/admin_audit.html)
- [PostgreSQL 16.15 release notes](https://www.postgresql.org/docs/16/release-16-15.html)
- [PostgreSQL 16 security information](https://www.postgresql.org/support/security/16/)
- [Redis 7.4 security release notes](https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/redisce/redisce-7.4-release-notes/)

---

**FINAL STATUS: NOT READY**  
เหตุผลหลัก: High credential findings 3 รายการ, Medium controls 6 รายการ และ Vulnerability Scan = NOT AVAILABLE
