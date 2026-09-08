#!/usr/bin/env bash
set -euo pipefail
umask 077
fail(){ echo "LOOPBACK_APPLY_FAILED: $*" >&2; exit 1; }
[[ "${TMUX:-}" == *","* ]] || fail "tmux required"
[[ "$(tmux display-message -p '#S')" == owncloud-minport-hardening ]] || fail "unexpected tmux session"
read -r ssh_source _ <<< "${SSH_CONNECTION:-}"
[[ "$ssh_source" == 10.128.162.172 ]] || fail "unexpected SSH source"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
[[ "$EUID" -eq 0 ]] || exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" "$@"

nginx_template="${1:-}"
rollback_script="${2:-}"
[[ -f "$nginx_template" && -f "$rollback_script" ]] || fail "required input missing"
exec 9>/run/lock/owncloud-minport-hardening.lock
flock -n 9 || fail "another minimum-port operation is running"
nginx -t >/dev/null
[[ ! -e /etc/nginx/sites-available/owncloud-loopback-8443 && ! -e /etc/nginx/sites-enabled/owncloud-loopback-8443 ]] || fail "loopback site already exists"
! ss -lntH | awk '{print $4}' | grep -Eq '(^|:)8443$' || fail "8443 already listening"
! ufw show raw | python3 -c 'import re,sys
s=sys.stdin.read()
for spec in re.findall(r"--dports?\s+([0-9,:]+)",s):
  for item in spec.split(","):
    p=item.split(":",1); lo=int(p[0]); hi=int(p[-1])
    if lo <= 8443 <= hi: raise SystemExit(0)
raise SystemExit(1)' || fail "8443 UFW rule exists"

stamp="$(date +%Y%m%d-%H%M%S-%N)"
backup="/var/backups/owncloud/loopback-access-$stamp"
install -d -o root -g root -m 0700 "$backup"
tar --acls --xattrs --numeric-owner -C / -czf "$backup/etc-nginx-before.tar.gz" etc/nginx
install -m 0600 -o root -g root /opt/owncloud/compose.yml "$backup/compose.yml.before"
install -m 0600 -o root -g root /opt/owncloud/.env "$backup/env.before"
docker exec owncloud-server occ config:system:get trusted_domains --output=json > "$backup/trusted-domains-before.json"
if ! docker exec owncloud-server occ config:system:get trusted_proxies --output=json > "$backup/trusted-proxies-before.json"; then
  printf '[]\n' > "$backup/trusted-proxies-before.json"
fi
ufw status numbered > "$backup/ufw-numbered-before.txt"
ss -lntup > "$backup/listeners-before.txt"
curl -sS --max-time 10 -H 'Host: itservice.research.psu.ac.th' http://127.0.0.1/ \
  -o "$backup/production-http-before.body" -w '%{http_code} %{redirect_url}\n' > "$backup/production-http-before.meta"
curl -ksS --max-time 10 -H 'Host: itservice.research.psu.ac.th' https://127.0.0.1/ \
  -o "$backup/production-https-before.body" -w '%{http_code} %{redirect_url}\n' > "$backup/production-https-before.meta"
grep -q '^301 ' "$backup/production-http-before.meta" || fail "production HTTP baseline unexpected"
grep -q '^200 ' "$backup/production-https-before.meta" || fail "production HTTPS baseline unexpected"
openssl s_client -connect 127.0.0.1:443 -servername itservice.research.psu.ac.th </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 > "$backup/production-tls-before.txt"
install -m 0700 -o root -g root "$rollback_script" "$backup/rollback-loopback-access.sh"
chmod 0600 "$backup"/*
(cd "$backup" && find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && chmod 0600 SHA256SUMS && sha256sum -c SHA256SUMS >/dev/null)

rollback_on_error(){
  rc=$?
  if (( rc != 0 )); then
    echo "LOOPBACK_APPLY_ROLLBACK backup=$backup" >&2
    env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$backup/rollback-loopback-access.sh" "$backup" --lock-held || true
  fi
  exit "$rc"
}
trap rollback_on_error EXIT

python3 -c 'from pathlib import Path
p=Path("/opt/owncloud/.env"); s=p.read_text();
lines=s.splitlines(); out=[]; seen_d=False; seen_p=False
for line in lines:
    if line.startswith("OWNCLOUD_TRUSTED_DOMAINS="):
        out.append("OWNCLOUD_TRUSTED_DOMAINS=localhost,127.0.0.1"); seen_d=True
    elif line.startswith("OWNCLOUD_TRUSTED_PROXIES="):
        out.append("OWNCLOUD_TRUSTED_PROXIES=10.0.8.1"); seen_p=True
    else: out.append(line)
if not seen_d: out.append("OWNCLOUD_TRUSTED_DOMAINS=localhost,127.0.0.1")
if not seen_p: out.append("OWNCLOUD_TRUSTED_PROXIES=10.0.8.1")
p.write_text("\n".join(out)+"\n")'
python3 -c 'from pathlib import Path
p=Path("/opt/owncloud/compose.yml"); s=p.read_text()
old="OWNCLOUD_TRUSTED_DOMAINS: ${OWNCLOUD_TRUSTED_DOMAINS:-localhost,127.0.0.1,10.8.12.10}"
new="OWNCLOUD_TRUSTED_DOMAINS: ${OWNCLOUD_TRUSTED_DOMAINS:-localhost,127.0.0.1}"
assert old in s, "trusted domains compose line not found"
s=s.replace(old,new,1)
anchor="      OWNCLOUD_OVERWRITE_CLI_URL: ${OWNCLOUD_OVERWRITE_CLI_URL:-http://127.0.0.1:9200}\n"
assert anchor in s, "compose anchor not found"
proxy="      OWNCLOUD_TRUSTED_PROXIES: ${OWNCLOUD_TRUSTED_PROXIES:-10.0.8.1}\n"
if proxy not in s: s=s.replace(anchor,anchor+proxy,1)
p.write_text(s)'
chmod 0600 /opt/owncloud/.env /opt/owncloud/compose.yml
cd /opt/owncloud && docker compose config --quiet
docker compose up -d --no-deps owncloud-server >/dev/null
container_healthy=false
for _ in {1..120}; do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' owncloud-server 2>/dev/null || true)" == healthy ]] && { container_healthy=true; break; }
  sleep 1
done
[[ "$container_healthy" == true ]] || fail "owncloud-server did not become healthy after recreate"

docker exec owncloud-server occ config:system:set trusted_domains 0 --value=localhost >/dev/null
docker exec owncloud-server occ config:system:set trusted_domains 1 --value=127.0.0.1 >/dev/null
docker exec owncloud-server occ config:system:delete trusted_domains 2 >/dev/null 2>&1 || true
docker exec owncloud-server occ config:system:delete trusted_proxies >/dev/null 2>&1 || true
docker exec owncloud-server occ config:system:set trusted_proxies 0 --value=10.0.8.1 >/dev/null
[[ "$(docker exec owncloud-server occ config:system:get trusted_domains --output=json)" == '["localhost","127.0.0.1"]' ]] || fail "trusted domains did not converge"
[[ "$(docker exec owncloud-server occ config:system:get trusted_proxies --output=json)" == '["10.0.8.1"]' ]] || fail "trusted proxies did not converge"

install -d -o root -g root -m 0700 /etc/nginx/ssl/owncloud-loopback-8443
openssl req -x509 -nodes -newkey rsa:3072 -sha256 -days 30 \
  -subj '/CN=127.0.0.1' -addext 'subjectAltName=IP:127.0.0.1' \
  -keyout /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.key \
  -out /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt >/dev/null 2>&1
chmod 0600 /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.key
chmod 0644 /etc/nginx/ssl/owncloud-loopback-8443/owncloud-loopback-8443.crt
install -m 0644 -o root -g root "$nginx_template" /etc/nginx/sites-available/owncloud-loopback-8443
ln -s /etc/nginx/sites-available/owncloud-loopback-8443 /etc/nginx/sites-enabled/owncloud-loopback-8443
nginx -t
systemctl reload nginx

listener_ok=false
for _ in {1..20}; do
  if [[ "$(ss -lntH | awk '$4 ~ /:8443$/ {print $4}')" == 127.0.0.1:8443 ]]; then listener_ok=true; break; fi
  sleep 0.25
done
[[ "$listener_ok" == true ]] || fail "listener is not loopback-only"
! ufw show raw | python3 -c 'import re,sys
s=sys.stdin.read()
for spec in re.findall(r"--dports?\s+([0-9,:]+)",s):
  for item in spec.split(","):
    p=item.split(":",1); lo=int(p[0]); hi=int(p[-1])
    if lo <= 8443 <= hi: raise SystemExit(0)
raise SystemExit(1)' || fail "8443 UFW rule exists"
curl -kfsS --max-time 15 https://127.0.0.1:8443/status.php >/dev/null || fail "loopback status unavailable"
[[ "$(curl -ksS --max-time 10 -o /dev/null -w '%{http_code}' -H 'Host: unknown.invalid:8443' https://127.0.0.1:8443/ 2>/dev/null)" == 000 ]] || fail "unknown Host was not closed"
(cd "$backup" && sha256sum -c SHA256SUMS >/dev/null)
trap - EXIT
echo "LOOPBACK_APPLY_PASS backup=$backup"
