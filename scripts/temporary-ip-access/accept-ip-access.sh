#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ "${1:-}" != --as-root && "$EUID" -ne 0 ]]; then
  read -r bootstrap_ssh_source _ <<< "${SSH_CONNECTION:-}"
  [[ "${TMUX:-}" == *","* && "$bootstrap_ssh_source" == 10.128.162.172 ]] || { echo "IP_ACCESS_ACCEPT_FAILED: tmux or SSH source preflight failed" >&2; exit 1; }
  sudo -n true >/dev/null 2>&1 || { echo "IP_ACCESS_ACCEPT_FAILED: sudo cache unavailable" >&2; exit 1; }
  exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" --as-root
fi
[[ "${1:-}" == --as-root ]] && shift

source_ip=10.128.162.172
listen_ip=10.8.12.10
listen_port=8443
password_file=/opt/owncloud/secrets/admin-password
backup_root=/var/backups/owncloud
receipt_tmp="$(mktemp)"
curl_config="$(mktemp)"
bad_curl_config="$(mktemp)"
payload="$(mktemp)"
download="$(mktemp)"
listeners_before="$(mktemp)"
listeners_after="$(mktemp)"
folder="ip-access-acceptance-$(date +%Y%m%d-%H%M%S)-$$"
webdav="https://$listen_ip:$listen_port/remote.php/dav/files/ocadmin"
folder_created=0

ufw_exact() { sudo ufw status verbose | awk -v d="$listen_ip" -v p="$listen_port/tcp" -v s="$source_ip" '{sub(/^\[[^]]+\][[:space:]]*/, "")} $1==d && $2==p && $3=="ALLOW" && $4=="IN" && ($5==s || $5==s"/32") {n++} END {exit n==1 ? 0 : 1}'; }
ufw_8443_count() { sudo ufw status | awk '/8443/ {count++} END {print count+0}'; }

fail() { printf 'FAIL\t%s\n' "$1" >> "$receipt_tmp"; exit 1; }
pass() { printf 'PASS\t%s\n' "$1" >> "$receipt_tmp"; }
status() { curl --insecure --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@"; }
auth_status() { curl --config "$curl_config" --insecure --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 60 "$@"; }
bad_status() { curl --config "$bad_curl_config" --insecure --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@"; }
expect() { local want="$1"; shift; [[ "$(status "$@" || true)" == "$want" ]] || fail "unexpected HTTP status"; }
expect_auth() { local want="$1"; shift; [[ "$(auth_status "$@" || true)" == "$want" ]] || fail "unexpected authenticated HTTP status"; }
wait_healthy() { for _ in $(seq 1 90); do [[ "$(docker inspect owncloud-server --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')" == healthy ]] && return 0; sleep 2; done; return 1; }
site_status() { local scheme="$1"; curl --insecure --silent --output /dev/null --write-out '%{http_code}' --max-time 20 -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" || true; }
site_hash() { local scheme="$1"; curl --insecure --silent --show-error --max-time 20 -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" | sha256sum | awk '{print $1}'; }
tls_fingerprint() { openssl s_client -connect 127.0.0.1:443 -servername itservice.research.psu.ac.th </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null; }
listeners() { ss -H -ltn | awk '{print "tcp\t" $4}' | sort; }
verify_absent() { [[ "$(auth_status -X PROPFIND -H 'Depth: 0' "$webdav/$folder" || true)" == 404 ]]; }

cleanup() {
  local result="$?"
  trap - EXIT INT TERM
  set +e
  if (( folder_created )); then
    deleted="$(auth_status -X DELETE "$webdav/$folder" || true)"
    if [[ "$deleted" != 204 && "$deleted" != 404 ]] || ! verify_absent; then printf 'FAIL\tWebDAV cleanup failed\n' >> "$receipt_tmp"; result=1; fi
  fi
  shred --remove=unlink --zero "$curl_config" "$bad_curl_config" "$payload" "$download" "$listeners_before" "$listeners_after" 2>/dev/null || true
  sudo install -d -o root -g root -m 0700 "$backup_root"
  sudo install -o root -g root -m 0600 "$receipt_tmp" "$backup_root/ip-access-acceptance-$(date +%Y%m%d-%H%M%S).tsv"
  rm -f "$receipt_tmp"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "${TMUX:-}" == *","* && "$(tmux display-message -p '#S')" == owncloud-ip-access ]] || fail "run only inside tmux session owncloud-ip-access"
read -r ssh_source _ <<< "${SSH_CONNECTION:-}"
[[ "$ssh_source" == "$source_ip" ]] || fail "SSH client source does not match approved /32"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
if [[ ! -e /proc/$$/fd/9 ]]; then exec 9>/run/lock/owncloud-ip-access.lock; fi
flock -n 9 || fail "another ownCloud IP access operation is running"
sudo nginx -t >/dev/null || fail "Nginx syntax validation failed"
[[ -z "$(systemctl --failed --no-legend --plain)" ]] || fail "failed system service exists"
pass "Nginx syntax and failed-services baseline"
sudo test -r "$password_file" || fail "admin recovery file unavailable"
admin_password="$(sudo cat "$password_file")"
[[ -n "$admin_password" ]] || fail "admin recovery file is empty"
printf 'user = "ocadmin:%s"\n' "$admin_password" > "$curl_config"
printf 'user = "ocadmin:invalid-ip-access-credential"\n' > "$bad_curl_config"
unset admin_password

http_before="$(site_status http)"; https_before="$(site_status https)"; http_hash_before="$(site_hash http)"; https_hash_before="$(site_hash https)"; tls_before="$(tls_fingerprint)"; listeners > "$listeners_before"
[[ "$http_before" =~ ^[1-9][0-9][0-9]$ && "$https_before" =~ ^[1-9][0-9][0-9]$ && -n "$tls_before" ]] || fail "existing-site baseline unavailable"
sudo ufw status | head -n1 | grep -qx 'Status: active' || fail "UFW inactive"
sudo ufw status verbose | grep -Eq '^Default: deny \(incoming\)' || fail "UFW incoming default is not deny"
[[ "$(ufw_8443_count)" == 1 ]] && ufw_exact || fail "sole exact UFW rule missing"
for c in owncloud-server owncloud-redis; do [[ "$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')" == healthy ]] || fail "container unhealthy"; done
sudo openssl x509 -in /etc/nginx/ssl/owncloud-ip-8443/owncloud-ip-8443.crt -noout -ext subjectAltName | grep -Fq "IP Address:$listen_ip" || fail "certificate SAN invalid"
sudo openssl x509 -in /etc/nginx/ssl/owncloud-ip-8443/owncloud-ip-8443.crt -checkend 1 -noout || fail "certificate expired"
[[ "$(sudo stat -c '%U:%G:%a' /etc/nginx/ssl/owncloud-ip-8443/owncloud-ip-8443.key)" == root:root:600 ]] || fail "key permissions invalid"
expect 200 "https://$listen_ip:$listen_port/index.php/login"; pass "UI login endpoint reachable"
expect_auth 200 -H 'OCS-APIRequest: true' "https://$listen_ip:$listen_port/ocs/v1.php/cloud/capabilities?format=json"
expect 401 -X PROPFIND -H 'Depth: 0' "$webdav/"
[[ "$(bad_status -X PROPFIND -H 'Depth: 0' "$webdav/" || true)" == 401 ]] || fail "wrong credential accepted"
expect_auth 207 -X PROPFIND -H 'Depth: 0' "$webdav/"
folder_created=1; expect_auth 201 -X MKCOL "$webdav/$folder"
dd if=/dev/zero of="$payload" bs=1M count=8 status=none
payload_sha="$(sha256sum "$payload" | awk '{print $1}')"
expect_auth 201 -T "$payload" "$webdav/$folder/payload.bin"
[[ "$(curl --config "$curl_config" --insecure --silent --show-error --output "$download" --write-out '%{http_code}' "$webdav/$folder/payload.bin" || true)" == 200 ]] || fail "WebDAV GET failed"
[[ "$(sha256sum "$download" | awk '{print $1}')" == "$payload_sha" ]] || fail "WebDAV checksum mismatch"
expect_auth 201 -X MOVE -H "Destination: $webdav/$folder/renamed.bin" "$webdav/$folder/payload.bin"
docker restart owncloud-server >/dev/null; wait_healthy || fail "ownCloud restart unhealthy"
[[ "$(curl --config "$curl_config" --insecure --silent --show-error --output "$download" --write-out '%{http_code}' "$webdav/$folder/renamed.bin" || true)" == 200 ]] || fail "WebDAV persistence GET failed"
[[ "$(sha256sum "$download" | awk '{print $1}')" == "$payload_sha" ]] || fail "WebDAV persistence checksum mismatch"
expect_auth 204 -X DELETE "$webdav/$folder"; verify_absent || fail "WebDAV folder remains"; folder_created=0; pass "authenticated OCS/WebDAV lifecycle and 8MiB persistence"
if ss -H -ltn | awk '$4 !~ /^(127\.0\.0\.1|\[::1\]|::1):/ {print $4}' | grep -Eq ':(9200|3306|6379)$'; then fail "internal service publicly exposed"; fi
listeners > "$listeners_after"; cmp -s "$listeners_before" "$listeners_after" || fail "listener regression"
[[ "$(site_status http)" == "$http_before" && "$(site_status https)" == "$https_before" && "$(site_hash http)" == "$http_hash_before" && "$(site_hash https)" == "$https_hash_before" && "$(tls_fingerprint)" == "$tls_before" ]] || fail "existing-site regression"
sudo nginx -t >/dev/null || fail "Nginx syntax regression"
[[ -z "$(systemctl --failed --no-legend --plain)" ]] || fail "failed system service regression"
pass "existing-site, listener, UFW, certificate, and container regression checks"
