# ownCloud Community Classic Installation

Status: **INTERNAL DEPLOYMENT COMPLETED 2026-08-18 — PUBLIC DNS/TLS PENDING**

## Pinned bill of materials (verified 2026-08-18)

- ownCloud Classic `11.0.0`, linux/amd64 digest `sha256:79b286cc06ec8bed102e76d7ee9abc6cc864635e8aa6ed391881bc1926eaeae7`
- MariaDB `10.11.18-jammy`, linux/amd64 digest `sha256:161be354206906ea8584929bde5ac59cdce0770fbfd5dd76131429f7dd80aab5`
- Redis `7.4.10-alpine`, linux/amd64 digest `sha256:9702d01c1f10c3ea9f48211b4362e44f154ff02d063e6f7268eba804059f53bf`

Official references:

- https://doc.owncloud.com/server/latest/admin_manual/installation/installing_with_docker.html
- https://doc.owncloud.com/server/latest/admin_manual/installation/system_requirements.html
- https://github.com/owncloud/core/releases/tag/v11.0.0

## Controlled order

1. Capture live Docker, listener, Nginx, firewall, filesystem, capacity, and existing-site baseline.
2. Back up `/etc/nginx` into a root-owned timestamped directory; keep the Nginx archive root-owned with mode `0600`.
3. Stage the reviewed files in `/opt/owncloud`; the deploy script generates permanent `.env` runtime values (without admin variables), a temporary `.bootstrap.env`, and root-only `secrets/admin-password` recovery file. It removes only its temporary bootstrap file after recreating the server without bootstrap variables.
4. Pull the pinned images and verify the platform/digests.
5. Inspect the pinned image ownership behavior, then create `/mnt/owncloud-data` without mode 777.
6. Validate both base and bootstrap Compose configurations; verify port 9200 is still free. The internal initial gate requires 50 GiB root free, 8 GiB available RAM, at least 8 CPUs, and inode use below 90%; a workload quota/capacity plan remains required before public production.
7. Start MariaDB and Redis, wait for health, then start ownCloud.
8. Test only through loopback before any Nginx change.
9. End the deploy script at the healthy/status check; run the separate acceptance script for UI/WebDAV lifecycle, persistence, exposure, mount, secret, and regression checks before final GO.
10. The internal deployment and acceptance test passed. Do not create a public Nginx vhost until a dedicated hostname, DNS record, and trusted certificate are approved.

Never run prune commands or `docker compose down -v`. After bootstrap, remove the admin bootstrap variables only after the credential recovery/change procedure is verified.
