# TEMPORARY OWNCLOUD IP ACCESS REPORT

Date: 2026-08-25  
Server-App: `research-app` (`10.8.12.10`)  
Server-DB/PostgreSQL: not accessed or modified

## Result

| Check | Result |
|---|---|
| ownCloud Version | Community Classic 11.0.0 |
| MariaDB Version | 10.11.18 |
| Redis Version | 7.4.10 |
| URL | `https://10.8.12.10:8443` |
| Web UI | PASS — login endpoint HTTP 200 |
| Admin Login | PASS — authenticated OCS/WebDAV validation |
| Upload | PASS — 8 MiB verification payload |
| Download | PASS — SHA-256 matched |
| Rename | PASS |
| Delete | PASS; verification folder removed |
| WebDAV | PASS — PROPFIND/MKCOL/PUT/GET/MOVE/DELETE |
| API | PASS — authenticated OCS capabilities |
| Persistence | PASS — data verified after scoped `owncloud-server` restart |
| Storage | `/mnt/owncloud-data` |
| Direct Storage Web Access | BLOCKED — no Nginx reference; no other container mount |
| TLS | SELF-SIGNED TEMPORARY |
| Certificate SAN | `IP Address:10.8.12.10` |
| Certificate Validity | 2026-08-25 through 2026-09-24 UTC |
| 8443 Firewall Source | `10.128.162.172/32` only |
| 8443 Allowed From Anywhere | NO |
| 9200 Public | NO — `127.0.0.1:9200` only |
| MariaDB Public | NO — Docker internal only |
| Redis Public | NO — Docker internal only |
| Nginx | PASS — syntax valid and active |
| Existing Production | PASS — HTTP 301 to approved HTTPS URL; HTTPS 200; containers healthy |
| Failed Services | 0 |
| Public Ports | 22, 80, 443, and source-restricted 8443 |
| Unexpected Public Ports | NONE |
| Future Domain Migration Ready | YES — documented, not executed |

## Security Validation

- ownCloud container privileged mode: `false`
- Docker socket mounts in ownCloud stack: `0`
- Other containers mounting `/mnt/owncloud-data`: `0`
- Nginx references to `/mnt/owncloud-data`: `0`
- `trusted_domains`: exact values only; no wildcard
- `trusted_proxies`: exact Docker gateway `10.0.8.1`
- Wildcard CORS on the temporary vhost: NO
- Unknown Host on port 8443: connection closed by Nginx guard
- Unauthenticated and wrong-credential WebDAV requests: rejected
- Temporary certificate key: `root:root`, mode `0600`
- HSTS is intentionally omitted from this temporary self-signed IP endpoint

## Backups

- Production configuration backup: `/var/backups/owncloud/ip-access-20260825-224334-739898783`
- Documentation backup: `/var/backups/owncloud/ip-access-docs-20260825-224740-042079211`
- Acceptance receipt: `/var/backups/owncloud/ip-access-acceptance-20260825-224500.tsv`
- SHA-256 manifests: PASS

## Files Created

- `/etc/nginx/sites-available/owncloud-ip-8443`
- `/etc/nginx/sites-enabled/owncloud-ip-8443`
- `/etc/nginx/ssl/owncloud-ip-8443/owncloud-ip-8443.crt`
- `/etc/nginx/ssl/owncloud-ip-8443/owncloud-ip-8443.key`
- `/opt/owncloud/scripts/temporary-ip-access/apply-ip-access.sh`
- `/opt/owncloud/scripts/temporary-ip-access/accept-ip-access.sh`
- `/opt/owncloud/scripts/temporary-ip-access/rollback-ip-access.sh`

## Files Modified

- `/opt/owncloud/docs/OPERATIONS.md`
- `/opt/owncloud/docs/SECURITY.md`
- `/opt/owncloud/docs/API-WEBDAV.md`
- `/opt/owncloud/docs/ROLLBACK.md`
- ownCloud `trusted_proxies` gained exact Docker gateway `10.0.8.1`
- UFW gained one exact temporary allow rule for `10.128.162.172/32` to `10.8.12.10:8443/tcp`

## Deployment Notes

The first apply attempt exposed a parser mismatch: `ufw status` omits the `IN` field while the exact-rule parser expected the `ufw status verbose` layout. The temporary rule/vhost were removed and the clean state was verified. The parser was changed only to consume verbose status, independently reviewed with a GO verdict, and the second apply passed all gates.

The first Nginx reload also activated an existing on-disk HTTP-to-HTTPS redirect for `itservice.research.psu.ac.th`. Current behavior is HTTP 301 to `https://itservice.research.psu.ac.th/` and HTTPS 200; its HTTPS body and TLS fingerprint remained unchanged.

## Rollback

Run only from the approved admin source inside the protected tmux session with a valid sudo cache:

```bash
/opt/owncloud/scripts/temporary-ip-access/rollback-ip-access.sh \
  /var/backups/owncloud/ip-access-20260825-224334-739898783
```

Rollback removes only the temporary exact UFW rule, Nginx vhost, certificate, and trusted-proxy addition, then validates Nginx, listeners, ownCloud health, and Existing Production.

## Remaining Warnings

- The certificate is self-signed and browsers will warn until an approved hostname/DNS/trusted certificate is available.
- The temporary certificate expires on 2026-09-24 UTC and must be replaced or the endpoint retired before expiry.
- Port 8443 is usable only from `10.128.162.172/32`; changing the admin source requires an explicit reviewed firewall update.
- Migrate to an approved hostname on port 443, validate it, then run the rollback above to close 8443.

## FINAL STATUS

**READY FOR INTERNAL USE**
