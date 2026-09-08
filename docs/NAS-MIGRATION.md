# Future NAS Migration

No NAS migration is authorized now. The stable host path is `/mnt/owncloud-data`, mounted in the container at `/mnt/data`.

## Required gates

- Validate NAS locking, atomic rename, latency, capacity, backup, UID/GID, ACLs, and failure behavior.
- Add a fail-closed mount assertion and service ordering so ownCloud cannot start and write to an empty local directory if the NAS is unavailable.

## Controlled migration

1. Enable maintenance mode and stop writes.
2. Perform initial and final metadata-preserving syncs.
3. Compare counts and checksums.
4. Preserve the local backing store for rollback; do not delete it.
5. Mount the NAS at `/mnt/owncloud-data` and verify mount type, ownership, ACLs, locking, and free space.
6. Start ownCloud, run only officially required scan/repair commands, then test UI/WebDAV and concurrent writes.
7. Roll back by stopping writes, unmounting NAS, restoring the original local path, and revalidating before reopening access.
