# ownCloud Rollback

1. Preserve `/mnt/owncloud-data` and do not modify `athena-engine-postgres16`.
2. Restore the verified `owncloud-postgres` backup into an isolated PostgreSQL container first.
3. Validate `public.oc_*`, users, file metadata, shares, and `owncloud_integration` before any Production database switch.
4. Restore `/opt/owncloud` only from the matching timestamped root-owned configuration backup.
5. Recreate only `owncloud-server` when a database configuration switch is explicitly approved; do not restart unrelated containers.
6. Recheck Web UI, authenticated OCS, WebDAV, Redis, cron, persistence, listeners, existing applications, and failed services.

The archived MariaDB logical dump at `/var/backups/owncloud-pg-migration/20260830T035016Z` is rollback-only evidence. It is not a runtime dependency and may be used only through a separately reviewed recovery plan.

## Minimum-port loopback rollback

The accepted transition backup is:

```text
/var/backups/owncloud/loopback-access-20260825-234251-857763806
```

Run the retained rollback only from the `owncloud-minport-hardening` tmux session with a valid sudo cache:

```bash
sudo -n env "TMUX=$TMUX" "SSH_CONNECTION=$SSH_CONNECTION" \
  bash /opt/owncloud/scripts/minimum-port-hardening/rollback-loopback-access.sh \
  /var/backups/owncloud/loopback-access-20260825-234251-857763806
```

This restores the pre-loopback Compose/environment and ownCloud trusted settings, recreates only `owncloud-server`, removes the loopback vhost/certificate, validates Nginx, and leaves `8443` closed. It does not recreate the retired network-facing `10.8.12.10:8443` endpoint or any UFW rule.
