# OWNCLOUD DEPLOYMENT REPORT

Date: 2026-08-18 (Asia/Bangkok)  
Scope: ownCloud Community Classic internal deployment on Server-App  
Classification: TLP:RED

## Executive summary

ownCloud Community Classic was deployed as an isolated central service on Server-App. The internal service, MariaDB, Redis, OCS API, WebDAV lifecycle, persistence, storage isolation, security controls, backup, and existing-production regression checks passed. No resource on Server-DB was accessed or changed.

Public browser access was intentionally not enabled because no approved dedicated hostname, DNS record, or trusted TLS certificate was supplied. The final status is **READY WITH WARNINGS** for internal operation and **BLOCKED** for public Web UI publication.

## Versions and architecture

| Component | Version / image | Result |
|---|---|---|
| ownCloud Community Classic | 11.0.0, `owncloud/server@sha256:79b286cc06ec8bed102e76d7ee9abc6cc864635e8aa6ed391881bc1926eaeae7` | PASS |
| MariaDB | 10.11.18, pinned digest `sha256:161be354206906ea8584929bde5ac59cdce0770fbfd5dd76131429f7dd80aab5` | PASS |
| Redis | 7.4.10, pinned digest `sha256:9702d01c1f10c3ea9f48211b4362e44f154ff02d063e6f7268eba804059f53bf` | PASS |

- Docker project: `owncloud`
- Containers: `owncloud-server`, `owncloud-db`, `owncloud-redis`
- Network: `owncloud-network`
- Named volumes: `owncloud-db-data`, `owncloud-redis-data`
- Install path: `/opt/owncloud`
- File storage: `/mnt/owncloud-data`
- Backend listener: `127.0.0.1:9200` only
- Server-DB PostgreSQL 16: **NOT TOUCHED**

## Validation results

| Check | Result |
|---|---|
| All three containers healthy | PASS |
| MariaDB ping and ownCloud connection | PASS |
| Redis ping | PASS |
| ownCloud status and `ocadmin` presence | PASS |
| OCS capabilities | PASS |
| WebDAV unauthorized request rejected | PASS |
| WebDAV wrong token rejected | PASS |
| WebDAV create/upload/download/rename/delete | PASS |
| Persistence after scoped container restart | PASS |
| Test-file checksum | PASS |
| Test trash cleanup | PASS; only one `acceptance-*` trash file existed and it was removed through `occ` |
| `/mnt/owncloud-data` is not an Nginx root/alias | PASS |
| Non-ownCloud containers cannot bind-mount the data path or an ancestor | PASS |
| Privileged containers | NO |
| Docker socket mounted | NO |
| MariaDB public port | NO |
| Redis public port | NO |
| ownCloud backend public port | NO |
| Bootstrap admin variables retained in running container | NO (`0`) |
| Nginx configuration test | PASS |
| Failed system services | 0 |
| Existing application HTTP/HTTPS | PASS (`200` / `200`) |

The first acceptance attempt found that ownCloud 11 does not provide `occ user:info`. The check was changed to the supported `occ user:list`, reviewed, and the complete acceptance test was rerun successfully.

## Network and security

- Public listeners after deployment remain `22`, `80`, and `443` only.
- The ownCloud backend is bound to loopback at `127.0.0.1:9200`.
- MariaDB `3306` and Redis `6379` are Docker-internal only.
- UFW remains active with default deny incoming.
- Nginx was not modified or reloaded because public DNS/TLS prerequisites are absent.
- `/mnt/owncloud-data` is mode `0750`, owned by `www-data:root`.
- `/opt/owncloud/secrets` is root-owned mode `0700`; the admin recovery file is root-owned mode `0600`.
- Runtime containers contain no `OWNCLOUD_ADMIN_*` variables after bootstrap.

Pre-existing warning: SSH port 22 remains allowed by the current broad rule. This deployment did not alter SSH or firewall policy.

## Backup and evidence

- Pre-deploy backup: `/home/research/security-backups/owncloud-predeploy-20260818/opt-owncloud-before.tar.gz`
- Deploy rollback set: `/var/backups/owncloud/owncloud-deploy-20260818-103731`
- Initial consistent backup: `/var/backups/owncloud/owncloud-initial-20260818-110108-950136903`
- Acceptance receipt: `/opt/owncloud/backups/acceptance-20260818.tsv`
- Final verification: `/opt/owncloud/backups/final-verification-20260818.txt`
- Evidence checksums: `/opt/owncloud/backups/evidence-SHA256SUMS`

All deploy and initial-backup SHA-256 manifests verified successfully. Backup status remains **WARN** because an isolated restore test has not been performed. The root-only secret recovery archive is plaintext-at-rest and must be encrypted to an approved recipient before any off-host copy; no recipient or key was invented.

## Credential recovery

- Admin username: `ocadmin`
- The generated password was never printed in logs or this report.
- An authorized administrator can retrieve it locally with `sudo cat /opt/owncloud/secrets/admin-password`, then change it through ownCloud administration.
- Project integrations must use separate credentials or app passwords; the admin credential must not be embedded in applications.

## Public access blocker

**BLOCKED — PUBLIC WEB ACCESS**

Required before publishing:

1. Approved dedicated hostname.
2. DNS record resolving to the approved endpoint.
3. Trusted TLS certificate matching that hostname.
4. Separate Nginx virtual host with validation and regression testing.

HSTS must not be enabled until trusted HTTPS is working. No existing application hostname or certificate was reused.

## Rollback

Use `/opt/owncloud/docs/ROLLBACK.md`. Rollback must stop/remove only the three ownCloud containers and its network without deleting volumes, restore the saved configuration as required, and revalidate Nginx and existing applications. Never use `docker compose down -v` or prune commands.

## Final status

```text
OWNCLOUD DEPLOYMENT REPORT

Version: 11.0.0
MariaDB Version: 10.11.18
Redis Version: 7.4.10

Preflight: PASS
Existing Docker Modified: NONE
ownCloud: PASS
MariaDB: PASS
Redis: PASS
Storage: /mnt/owncloud-data
Upload: PASS
Download: PASS
Persistence: PASS
WebDAV/API: PASS
Direct File Web Access: BLOCKED
ownCloud Backend Public: NO
MariaDB Public: NO
Redis Public: NO
Nginx: PASS (unchanged)
DNS/TLS: BLOCKED
Existing Applications: PASS
Public Ports Before: 22, 80, 443
Public Ports After: 22, 80, 443
Unexpected Public Ports: NONE
Future NAS Ready: YES (migration not yet executed)
Failed Services: 0
Backup: WARN — isolated restore and approved off-host encryption pending

FINAL STATUS: READY WITH WARNINGS
```
