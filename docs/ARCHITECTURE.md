# ownCloud Production Architecture

Status: **PRODUCTION — POSTGRESQL ACTIVE**

```text
Users -> Nginx 80/443
  -> 127.0.0.1:9200 -> owncloud-server
  -> 10.8.12.11:5433 -> owncloud-postgres (PostgreSQL 16.13)
  -> owncloud-redis (Docker internal only)
  -> host /mnt/owncloud-data mounted as container /mnt/data
```

- Server-App containers: `owncloud-server`, `owncloud-redis`.
- Server-DB ownCloud database: `owncloud-postgres` on private bind `10.8.12.11:5433`.
- Allowed PostgreSQL source: Server-App `10.8.12.10/32` only.
- Protected Server-DB production container: `athena-engine-postgres16`; ownCloud operations must not modify it.
- Install root: `/opt/owncloud`.
- Host data path: `/mnt/owncloud-data`; binary files remain here.
- Redis has no published host port.
- ownCloud backend is published only on `127.0.0.1:9200`; the admin tunnel is `127.0.0.1:8443`.
- Nginx and other applications must never use `/mnt/owncloud-data` as `root`, `alias`, or a direct mount.
- No MariaDB runtime, volume, listener, secret, or Compose dependency remains.

The future NAS may replace the backing filesystem at `/mnt/owncloud-data`; the container path remains `/mnt/data`.
