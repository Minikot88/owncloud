#!/usr/bin/env bash
set -euo pipefail
umask 077
fail(){ echo "LOOPBACK_ROLLBACK_FAILED: $*" >&2; exit 1; }
[[ "${TMUX:-}" == *","* ]] || fail "tmux required"
[[ "$(tmux display-message -p '#S')" == owncloud-minport-hardening ]] || fail "unexpected tmux session"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
[[ "$EUID" -eq 0 ]] || exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" "$@"
backup="${1:-}"
[[ -d "$backup" && "$backup" == /var/backups/owncloud/loopback-access-* ]] || fail "invalid backup path"
[[ -f "$backup/compose.yml.before" && -f "$backup/env.before" ]] || fail "backup incomplete"
if [[ "${2:-}" != --lock-held ]]; then
  exec 9>/run/lock/owncloud-minport-hardening.lock
  flock -n 9 || fail "another minimum-port operation is running"
fi
(cd "$backup" && sha256sum -c SHA256SUMS >/dev/null) || fail "backup manifest invalid"
domains_file="$(mktemp /run/owncloud-domains.XXXXXX)"
proxies_file="$(mktemp /run/owncloud-proxies.XXXXXX)"
trap 'rm -f "$domains_file" "$proxies_file"' EXIT
python3 -c 'import json,sys
v=json.load(open(sys.argv[1])); assert isinstance(v,list) and len(v)>=2
assert all(isinstance(x,str) and x for x in v)
sys.stdout.write("\n".join(v)+("\n" if v else ""))' "$backup/trusted-domains-before.json" > "$domains_file" || fail "trusted domains backup invalid"
python3 -c 'import json,sys
v=json.load(open(sys.argv[1])); assert isinstance(v,list)
assert all(isinstance(x,str) and x for x in v)
sys.stdout.write("\n".join(v)+("\n" if v else ""))' "$backup/trusted-proxies-before.json" > "$proxies_file" || fail "trusted proxies backup invalid"
mapfile -t domains < "$domains_file"
mapfile -t proxies < "$proxies_file"

install -m 0600 -o root -g root "$backup/compose.yml.before" /opt/owncloud/compose.yml
install -m 0600 -o root -g root "$backup/env.before" /opt/owncloud/.env
rm -f /etc/nginx/sites-enabled/owncloud-loopback-8443
rm -f /etc/nginx/sites-available/owncloud-loopback-8443
rm -f /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt
rm -f /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.key
rmdir /etc/nginx/ssl/owncloud-loopback-8443 2>/dev/null || true

cd /opt/owncloud
docker compose config --quiet
docker compose up -d --no-deps owncloud-server >/dev/null
container_healthy=false
for _ in {1..120}; do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' owncloud-server 2>/dev/null || true)" == healthy ]] && { container_healthy=true; break; }
  sleep 1
done
[[ "$container_healthy" == true ]] || fail "owncloud-server did not become healthy after rollback recreate"

docker exec owncloud-server occ config:system:delete trusted_domains >/dev/null 2>&1 || true
for i in "${!domains[@]}"; do docker exec owncloud-server occ config:system:set trusted_domains "$i" --value="${domains[$i]}" >/dev/null; done
docker exec owncloud-server occ config:system:delete trusted_proxies >/dev/null 2>&1 || true
for i in "${!proxies[@]}"; do docker exec owncloud-server occ config:system:set trusted_proxies "$i" --value="${proxies[$i]}" >/dev/null; done

nginx -t
systemctl reload nginx
listener_gone=false
for _ in {1..20}; do
  if ! ss -lntH | awk '{print $4}' | grep -Eq '(^|:)8443$'; then listener_gone=true; break; fi
  sleep 0.25
done
[[ "$listener_gone" == true ]] || fail "8443 still listening"
! ufw show raw | python3 -c 'import re,sys
s=sys.stdin.read()
for spec in re.findall(r"--dports?\s+([0-9,:]+)",s):
  for item in spec.split(","):
    p=item.split(":",1); lo=int(p[0]); hi=int(p[-1])
    if lo <= 8443 <= hi: raise SystemExit(0)
raise SystemExit(1)' || fail "8443 UFW rule remains"
curl -fsS --max-time 10 http://127.0.0.1:9200/status.php >/dev/null || fail "ownCloud backend unavailable"
rm -f "$domains_file" "$proxies_file"
trap - EXIT
echo "LOOPBACK_ROLLBACK_PASS backup=$backup"
