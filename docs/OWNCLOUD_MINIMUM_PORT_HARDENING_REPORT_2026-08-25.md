# OWNCLOUD MINIMUM-PORT HARDENING REPORT

Date: 2026-08-25 (Asia/Bangkok)  
Scope: Server-App only; Server-DB/PostgreSQL was not accessed or changed.

## Outcome

ownCloud administrative access is now available only through an SSH local tunnel. The former network-facing `10.8.12.10:8443` Nginx listener, its `/32` UFW allow rule, and its temporary IP certificate were retired. The replacement Nginx endpoint listens only on `127.0.0.1:8443` and proxies to the existing loopback backend at `127.0.0.1:9200`.

```text
Admin PC -- SSH :22 --> Server-App
                         127.0.0.1:8443 (Nginx, temporary TLS)
                                  |
                         127.0.0.1:9200 (ownCloud)
```

## Network and firewall

| Item | Final result |
|---|---|
| Network-facing TCP ports | `22`, `80`, `443` |
| `8443` network accessible | NO |
| `8443` server listener | `127.0.0.1:8443` only |
| UFW rule covering `8443` | NONE |
| `9200` public | NO; `127.0.0.1:9200` only |
| MariaDB `3306` public/host-published | NO |
| Redis `6379` public/host-published | NO |
| Unexpected network-facing ports | NONE |

TCP `53` observed on Docker bridge addresses is internal Docker DNS, not a wildcard or Server-App `ens3` listener, and is retained.

## ownCloud and Nginx configuration

- Trusted domains: exactly `localhost`, `127.0.0.1`.
- Trusted proxy: exactly the verified ownCloud Docker gateway `10.0.8.1`.
- Global `overwritehost` and `overwriteprotocol` were not introduced.
- Existing `overwrite.cli.url` remains `http://127.0.0.1:9200`.
- Temporary TLS certificate SAN: `IP:127.0.0.1`; self-signed and not represented as trusted Production TLS.
- Nginx exact Host policy accepts `127.0.0.1:8443`; unknown Host requests are closed with Nginx `444` behavior.
- Nginx has no `root` or `alias` serving `/mnt/owncloud-data`.
- `owncloud-server` was recreated once from the updated Compose environment; MariaDB and Redis were not recreated.

## Validation

- Windows SSH local-forward path: PASS.
- Tunnel status endpoint: HTTP `200`.
- Direct Windows TCP probes to `10.8.12.10:{8443,9200,3306,6379}`: BLOCKED.
- Tunnel process cleanup and local port release: PASS.
- Web UI login endpoint: PASS.
- Authenticated OCS API: PASS.
- WebDAV unauthenticated/wrong-credential rejection: PASS.
- Authenticated WebDAV `PROPFIND`, folder creation, upload, checksum download, rename, delete: PASS.
- ownCloud restart and file persistence: PASS.
- Test folder/file cleanup through WebDAV: PASS.
- MariaDB and Redis health probes: PASS.
- ownCloud/MariaDB/Redis container health: PASS.
- Existing Production HTTP: `301` unchanged.
- Existing Production HTTPS: `200` unchanged.
- Existing Production body hashes and TLS fingerprint: unchanged.
- Nginx syntax: PASS.
- Failed system services: `0`.
- Direct storage web access: BLOCKED.

## Backups and evidence

Primary pre-transition backup:

```text
/var/backups/owncloud/minport-pretransition-20260825-231414-700658581
```

Accepted loopback deployment backup/evidence:

```text
/var/backups/owncloud/loopback-access-20260825-234251-857763806
```

The accepted directory contains the pre-change Compose/environment, Nginx archive, trusted-domain/proxy state, UFW/listener baselines, Production HTTP/HTTPS/TLS baselines, functional receipt, client-tunnel receipt, documentation backup, and SHA-256 manifests:

```text
SHA256SUMS
FINAL_SHA256SUMS
FINAL_EVIDENCE_SHA256SUMS
```

Earlier failed candidate attempts were rolled back to the no-`8443` retired state before retrying; no failed attempt was accepted as the final deployment.

## Rollback

Run only inside the `owncloud-minport-hardening` tmux session while the accepted backup exists and sudo cache is valid:

```bash
sudo -n env "TMUX=$TMUX" "SSH_CONNECTION=$SSH_CONNECTION" \
  bash /opt/owncloud/scripts/minimum-port-hardening/rollback-loopback-access.sh \
  /var/backups/owncloud/loopback-access-20260825-234251-857763806
```

Rollback restores the pre-loopback Compose/environment and trusted settings, recreates only `owncloud-server`, removes the loopback vhost/certificate, validates/reloads Nginx, and leaves `8443` closed. It never re-enables the retired network-facing endpoint.

## Administrator access

On the authorized Windows workstation:

```powershell
D:\git\server\10.8.12.10\owncloud-production-setup\open-owncloud-tunnel.ps1
```

Then browse to:

```text
https://127.0.0.1:8443
```

Closing the SSH process removes access. A browser warning is expected because the loopback certificate is temporary/self-signed.

## Remaining warnings

1. SSH port `22` retains the current broad UFW policy because no stable PSU VPN/admin CIDR was authoritatively confirmed. A staged allowlist change was intentionally not attempted to avoid lockout.
2. The loopback certificate is self-signed. A dedicated approved hostname, DNS record, and trusted TLS certificate are still required before public ownCloud access.
3. While SSH tunneling is used, HTTP logs see the loopback client; administrator attribution is provided by SSH authentication logs.

```text
OWNCLOUD MINIMUM-PORT HARDENING REPORT

Network/Public Ports: 22, 80, 443
8443 Network Accessible: NO
9200 Public: NO
3306 Public: NO
6379 Public: NO
ownCloud Admin Access: SSH TUNNEL ONLY
Tunnel URL: https://127.0.0.1:8443
Web UI Through Tunnel: PASS
WebDAV/API: PASS
Direct Storage Web Access: BLOCKED
Nginx: PASS
Existing Production: PASS
SSH Policy: WARNING
Failed Services: 0
Unexpected Network Ports: NONE
Backups: PASS
FINAL STATUS: HARDENED WITH WARNINGS
```
