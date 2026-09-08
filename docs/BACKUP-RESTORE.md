# ownCloud Backup and Restore

Status: **POSTGRESQL BACKUP AND ISOLATED RESTORE VERIFIED**

## Production backup

- Database: dedicated `owncloud-postgres` on Server-DB.
- Automation: `owncloud-postgres-backup.timer` runs the root-owned backup service.
- Method: PostgreSQL `pg_dump` custom format plus checksum and role metadata without passwords.
- Backup root: `/var/backups/owncloud-postgres` on Server-DB.
- Verified backup: `/var/backups/owncloud-postgres/20260830T044941Z`.
- Isolated restore evidence: `/var/backups/owncloud-pg-migration/20260830T035016Z/postgres-backup-restore/validation.txt` on Server-DB.

The consistent recovery set also includes `/mnt/owncloud-data`, `/opt/owncloud/compose.yml`, the root-only runtime `.env`, and ownCloud configuration. Redis is not authoritative file or database storage.

## Archived MariaDB rollback source

`/var/backups/owncloud-pg-migration/20260830T035016Z` is **ARCHIVED — ROLLBACK ONLY**. Its verified logical dump must not be used by Production runtime or deleted in routine cleanup. Restoring it requires a separately approved isolated recovery procedure.

Never use `docker compose down -v`, Docker volume prune, or image prune for ownCloud recovery.
