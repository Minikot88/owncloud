# OWNCLOUD PRODUCTION DEPLOYMENT REPORT

Report date: 2026-08-13

## Architecture

Selected: Project backends on Server-App -> dedicated ownCloud node -> external
S3. oCIS metadata and temporary uploads reside on the dedicated node. PostgreSQL
stores project references only.

## Status

- ownCloud version selected for future validation: `8.0.6` stable
- Deployment: **BLOCKED**
- Web UI: NOT INSTALLED
- API: NOT INSTALLED
- WebDAV: NOT INSTALLED
- External Storage: BLOCKED
- User Files Stored Permanently On Server-App: NO NEW FILES
- Temporary Upload Data On Server-App: NO NEW DATA; NOT TESTED BECAUSE NOT INSTALLED
- User Files Stored In Server-DB: NO NEW FILES
- Project Spaces: 0/10
- Project Isolation: NOT TESTED
- ownCloud internal ports publicly exposed: NONE
- Port 9200 public: NO
- Existing nginx: ACTIVE; privileged configuration test pending sudo
- Existing production site: HTTP test previously PASS; unchanged by this blueprint
- Docker Security: existing application ports are loopback-only
- Firewall: privileged rule audit BLOCKED because sudo cache is unavailable
- TLS: ownCloud domain/certificate unavailable; existing default uses self-signed
- Secrets: no real secret was created or recorded
- Backup: blueprint backup/checksum required when copied to Server-App

## Changes Applied

- Created documentation and a non-runnable fail-closed Compose blueprint under
  `/opt/owncloud`.
- No ownCloud/OCIS container, image, network, volume, nginx site, firewall rule,
  certificate, or database object was created or modified.
- Backup created before the blueprint:
  `/home/research/security-backups/owncloud-blueprint-20260813-174247/opt-owncloud-before.tar.gz`
- Backup SHA-256:
  `9f13eac3e7482d19b0bded22b16fd35f168be87a6ab3e9f6225bd9c2843a70c6`
- Blueprint manifest: `/opt/owncloud/SHA256SUMS`

## Audit Evidence

- Server-App: Ubuntu 24.04.4, Docker 29.1.3, Compose 2.40.3, 15 GiB RAM,
  196 GiB disk with about 173 GiB available.
- Public listeners observed without sudo: 22, 80, 443.
- Existing backend/frontend bindings: `127.0.0.1:4001` and `127.0.0.1:8080`.
- No listeners observed on 3001, 3005, 9000, or 9443.
- `/opt/owncloud` existed and was empty before this blueprint.
- Server-DB: Ubuntu 24.04.4, Docker active, PostgreSQL container present, port
  5432 bound to `10.8.12.11`; no database changes were made.

## Validation Results

- All ten blueprint files passed `sha256sum -c`.
- `docker compose config -q` passed and `docker compose ps` returned no services.
- No running container name matched `ocis` or `owncloud`.
- Existing frontend remained HTTP `200` on loopback port 8080.
- Existing backend container remained healthy; its root route returned expected
  HTTP `404` rather than a connection failure.
- `itservice.research.psu.ac.th` remained HTTP `200` through nginx.
- Windows TCP validation: ports 22, 80, and 443 reachable; port 9200 not reachable.
- `prod-postgres` remained healthy on `research-db`.
- Audit temporary files created by this work were removed.

## Remaining Blockers

1. Dedicated ownCloud node assignment.
2. External S3 endpoint, region, bucket, access key, and secret key.
3. Stable DNS/URL and trusted TLS certificate.
4. Upload-size/concurrency and resource sizing.
5. Identity source and named administrators.
6. External backup destination, RPO/RTO, and retention.
7. Privileged UFW/nftables/DOCKER-USER/nginx audit requires renewed sudo cache.

## Final Status

**NOT READY**

Installation on Server-App was intentionally prevented because it would violate
the no-upload-bytes-on-Server-App requirement.
