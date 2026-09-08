#!/usr/bin/env bash
set -euo pipefail
umask 077
fail(){ echo "LOOPBACK_ACCEPT_FAILED: $*" >&2; exit 1; }
[[ "${TMUX:-}" == *","* ]] || fail "tmux required"
[[ "$(tmux display-message -p '#S')" == owncloud-minport-hardening ]] || fail "unexpected tmux session"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
[[ "$EUID" -eq 0 ]] || exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" "$@"
backup="${1:-}"
client_receipt="${2:-}"
[[ -d "$backup" && "$backup" == /var/backups/owncloud/loopback-access-* ]] || fail "invalid backup path"
[[ -f "$client_receipt" ]] || fail "client tunnel receipt missing"
exec 9>/run/lock/owncloud-minport-hardening.lock
flock -n 9 || fail "another minimum-port operation is running"
grep -qx 'TUNNEL_STATUS_CODE=200' "$client_receipt" || fail "tunnel status not proven"
grep -qx 'DIRECT_8443_BLOCKED=YES' "$client_receipt" || fail "direct 8443 not proven blocked"
grep -qx 'DIRECT_9200_BLOCKED=YES' "$client_receipt" || fail "direct 9200 not proven blocked"
grep -qx 'DIRECT_3306_BLOCKED=YES' "$client_receipt" || fail "direct 3306 not proven blocked"
grep -qx 'DIRECT_6379_BLOCKED=YES' "$client_receipt" || fail "direct 6379 not proven blocked"
grep -qx 'LOCAL_PORT_RELEASED=YES' "$client_receipt" || fail "tunnel cleanup not proven"
grep -qx "BACKUP_BASENAME=$(basename "$backup")" "$client_receipt" || fail "receipt deployment mismatch"
validated_at="$(sed -n 's/^VALIDATED_AT_UTC=//p' "$client_receipt")"
validated_epoch="$(date -u -d "$validated_at" +%s 2>/dev/null)" || fail "receipt timestamp invalid"
now_epoch="$(date -u +%s)"
(( now_epoch >= validated_epoch && now_epoch - validated_epoch <= 900 )) || fail "receipt is stale"
receipt_cert="$(sed -n 's/^CERT_SHA256=//p' "$client_receipt")"
[[ "$receipt_cert" =~ ^[0-9a-f]{64}$ ]] || fail "receipt certificate hash invalid"
server_cert="$(openssl x509 -in /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt -outform DER | sha256sum | awk '{print $1}')"
[[ "$receipt_cert" == "$server_cert" ]] || fail "receipt certificate mismatch"
nginx -t >/dev/null
systemctl is-active --quiet nginx
[[ "$(ss -lntH | awk '$4 ~ /:8443$/ {print $4}')" == 127.0.0.1:8443 ]] || fail "8443 listener mismatch"
! ufw show raw | python3 -c 'import re,sys
s=sys.stdin.read()
for spec in re.findall(r"--dports?\s+([0-9,:]+)",s):
  for item in spec.split(","):
    p=item.split(":",1); lo=int(p[0]); hi=int(p[-1])
    if lo <= 8443 <= hi: raise SystemExit(0)
raise SystemExit(1)' || fail "8443 UFW rule exists"
for port in 3306 6379; do ! ss -lntH | awk '{print $4}' | grep -Eq "(^|:)$port$" || fail "$port host listener exists"; done
[[ "$(ss -lntH | awk '$4 ~ /:9200$/ {print $4}')" == 127.0.0.1:9200 ]] || fail "9200 listener mismatch"
domains="$(docker exec owncloud-server occ config:system:get trusted_domains --output=json)"
proxies="$(docker exec owncloud-server occ config:system:get trusted_proxies --output=json)"
[[ "$domains" == '["localhost","127.0.0.1"]' ]] || fail "trusted domains mismatch"
[[ "$proxies" == '["10.0.8.1"]' ]] || fail "trusted proxies mismatch"
openssl x509 -in /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt -noout -checkend 86400 >/dev/null
openssl x509 -in /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt -noout -ext subjectAltName | grep -q 'IP Address:127.0.0.1'
curl -kfsS --max-time 15 https://127.0.0.1:8443/status.php >/dev/null
for c in owncloud-server owncloud-redis; do [[ "$(docker inspect -f '{{.State.Health.Status}}' "$c")" == healthy ]] || fail "$c not healthy"; done
tmpdir="$(mktemp -d /run/owncloud-minport-accept.XXXXXX)"
cleanup_tmpdir(){ rm -f "$tmpdir/http.body" "$tmpdir/http.meta" "$tmpdir/https.body" "$tmpdir/https.meta" "$tmpdir/tls.txt"; rmdir "$tmpdir" 2>/dev/null || true; }
trap cleanup_tmpdir EXIT
curl -sS --max-time 15 -H 'Host: itservice.research.psu.ac.th' http://127.0.0.1/ \
  -o "$tmpdir/http.body" -w '%{http_code} %{redirect_url}\n' > "$tmpdir/http.meta"
curl -ksS --max-time 15 -H 'Host: itservice.research.psu.ac.th' https://127.0.0.1/ \
  -o "$tmpdir/https.body" -w '%{http_code} %{redirect_url}\n' > "$tmpdir/https.meta"
openssl s_client -connect 127.0.0.1:443 -servername itservice.research.psu.ac.th </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 > "$tmpdir/tls.txt"
cmp -s "$tmpdir/http.meta" "$backup/production-http-before.meta" || fail "production HTTP status/redirect changed"
cmp -s "$tmpdir/https.meta" "$backup/production-https-before.meta" || fail "production HTTPS status changed"
cmp -s "$tmpdir/tls.txt" "$backup/production-tls-before.txt" || fail "production TLS certificate changed"
[[ "$(sha256sum "$tmpdir/http.body" | awk '{print $1}')" == "$(sha256sum "$backup/production-http-before.body" | awk '{print $1}')" ]] || fail "production HTTP body changed"
[[ "$(sha256sum "$tmpdir/https.body" | awk '{print $1}')" == "$(sha256sum "$backup/production-https-before.body" | awk '{print $1}')" ]] || fail "production HTTPS body changed"
[[ -z "$(systemctl --failed --no-legend --plain)" ]] || fail "failed services present"
install -m 0600 -o root -g root "$client_receipt" "$backup/client-tunnel-validation.txt"
cleanup_tmpdir
trap - EXIT
echo "LOOPBACK_ACCEPT_PASS backup=$backup"
