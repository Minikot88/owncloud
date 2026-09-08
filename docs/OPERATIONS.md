# ownCloud Operations

Status: **INTERNAL — SSH TUNNEL ONLY**

## Temporary loopback access

ownCloud is not exposed on the Server-App network. Nginx listens at `127.0.0.1:8443`; the application backend remains `127.0.0.1:9200`. On the authorized Windows workstation, run:

```powershell
D:\git\server\10.8.12.10\owncloud-production-setup\open-owncloud-tunnel.ps1
```

Keep that terminal open and browse to `https://127.0.0.1:8443`. The certificate is self-signed, restricted to loopback, and temporary. SSH logs—not HTTP source addresses—are the client-attribution source while tunneling is used. Do not add an inbound UFW rule for `8443`.

## Routine checks

```bash
cd /opt/owncloud
docker compose ps
docker ps --filter name=owncloud
docker inspect owncloud-server
docker inspect owncloud-redis
```

Review logs with bounded output. Never export environment variables or secrets into tickets or reports.

## Background jobs

The official Docker image supports internal cron. Confirm `OWNCLOUD_CROND_ENABLED` and its schedule after deployment, then verify jobs through `occ` and the admin page. Do not use AJAX cron for production.

## Change sequence

```text
Inspect -> Backup -> Validate -> Change -> Validate -> Test -> Rollback if needed
```

Do not use prune operations, broad recursive deletion, or `docker compose down -v`.

## Initial acceptance

Run `scripts/acceptance-test.sh` only from the `owncloud-setup` tmux session after internal deployment. It writes a non-secret root-only receipt at `/opt/owncloud/backups/acceptance-20260818.tsv`, preserves the admin recovery file, and removes only its unique WebDAV test folder; cleanup accepts only WebDAV `204`/`404` and confirms the DAV path is `404`. Browser form login remains blocked until public DNS/TLS is approved; authenticated OCS and WebDAV acceptance must pass before final GO.

The minimum-port transition was accepted with the retained scripts under `/opt/owncloud/scripts/minimum-port-hardening`. Its rollback returns to **no 8443 listener**; it never restores the former network-facing endpoint.
