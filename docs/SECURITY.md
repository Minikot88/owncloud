# ownCloud Security Baseline

- Images are pinned by explicit version and linux/amd64 digest.
- MariaDB and Redis publish no host port; ownCloud binds only to `127.0.0.1:9200`. Nginx exposes the temporary UI/API endpoint only at `127.0.0.1:8443` for SSH local forwarding.
- Containers are non-privileged and use no host network/PID namespace, Docker socket, devices, or broad host mounts.
- `/mnt/owncloud-data` is mounted only into `owncloud-server` and is never served directly by Nginx.
- Permanent `.env` is generated on Server-App, mode `600`, excludes bootstrap admin variables, and is never printed. Initial admin variables exist only in temporary `.bootstrap.env`; after bootstrap the server is recreated from base Compose and the temporary file is securely removed. The root-only `secrets/admin-password` recovery file remains and must never be deleted by deploy cleanup.
- MariaDB root, ownCloud DB runtime, and ownCloud admin passwords are independent.
- Redis authentication is not enabled initially because ownCloud does not support Redis ACLs and a password passed through Compose would remain inspectable. Isolation relies on the dedicated Docker network and no published port.
- JSON logs are size-limited; containers have PID, memory, and CPU limits (aggregate CPU limit is 5.0 and aggregate memory limit is 5.5 GiB).
- The internal deploy validates Nginx syntax but does not alter or reload Nginx. Its root-owned backup directory and Nginx archive remain root-owned, with the archive mode set to `0600`.
- Before and after deployment, the script compares pre-existing container state/health/restarts, failed service units, listener tuples, and loopback HTTP/HTTPS Host-header status for `itservice.research.psu.ac.th`; a mismatch stops only ownCloud resources.
- Trusted domains are exactly `localhost` and `127.0.0.1`. The trusted proxy is only the verified ownCloud Docker gateway `10.0.8.1`; no SSH client address or wildcard is trusted.
- UFW has no rule for `8443`. Network clients cannot directly reach `8443`, `9200`, `3306`, or `6379`; access to `8443` is through an authenticated SSH local tunnel only.
- The temporary certificate has only `IP:127.0.0.1` in its SAN. It is self-signed, is not a substitute for approved DNS/trusted TLS, and must not be reused by another application.
- Admin credentials must never be reused by projects. Future project integration uses separate revocable app passwords/tokens.
- Public access requires trusted TLS, proxy settings, compatible headers, upload limits/timeouts, WebDAV tests, and rate-limit validation.
