# ownCloud API and WebDAV

Status: **INTERNAL — SSH TUNNEL VALIDATED**

During the temporary loopback phase, establish the authorized SSH tunnel and use:

```text
https://127.0.0.1:8443/remote.php/dav/files/<username>/
```

Do not address `10.8.12.10:8443` directly. The Server-App endpoint is loopback-only and the certificate is temporary/self-signed.

Each Project receives a separate ownCloud user and a separate revocable app password/token. Credentials belong in backend secret storage only.

Typical WebDAV root after the dedicated hostname is approved:

```text
https://<owncloud-host>/remote.php/dav/files/<username>/
```

Required tests per Project:

1. Authenticated `PROPFIND` succeeds.
2. Create folder, upload, download, rename, and delete succeed.
3. Wrong token and unauthenticated requests fail.
4. A Project cannot enumerate or read another Project's files.
5. Token revocation stops access without changing the user's main password.

For initial platform acceptance, `scripts/acceptance-test.sh` performs unauthenticated, wrong-token, and authenticated WebDAV checks plus create, upload, HTTP-200 checksum download, rename, restart-persistence, delete, and DAV-404 cleanup verification. It uses the root-only recovery file without writing credentials to its receipt or command arguments; host filesystem cleanup is not used because ownCloud retention/trash behavior is valid.

The 2026-08-25 minimum-port validation repeated the authenticated OCS/WebDAV lifecycle through `127.0.0.1:8443`, including restart persistence, and separately proved the Windows SSH-forwarded status endpoint. The generated test folder and files were removed through WebDAV.

Applications store file references and metadata, not file binaries. They must not mount `/mnt/owncloud-data`.

Official WebDAV troubleshooting endpoint guidance: https://doc.owncloud.com/server/latest/admin_manual/troubleshooting/general_troubleshooting.html
