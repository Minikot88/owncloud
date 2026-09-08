#!/usr/bin/env bash
set -euo pipefail
umask 077

install_root=/opt/owncloud
data_root=/mnt/owncloud-data
password_file="$install_root/secrets/admin-password"
receipt_root="$install_root/backups"
receipt_path="$receipt_root/acceptance-20260818.tsv"
run_id="acceptance-$(date +%Y%m%d-%H%M%S)-$$"
test_folder="$run_id"
test_file="payload-$run_id.txt"
webdav_root="http://127.0.0.1:9200/remote.php/dav/files/ocadmin"
receipt_tmp="$(mktemp)"
curl_config="$(mktemp)"
invalid_curl_config="$(mktemp)"
payload_file="$(mktemp)"
download_file="$(mktemp)"
preexisting_before="$(mktemp)"
preexisting_after="$(mktemp)"
public_before="$(mktemp)"
public_after="$(mktemp)"
folder_created=0
admin_password=''

fail() {
  printf 'FAIL\t%s\n' "$1" >> "$receipt_tmp"
  exit 1
}

pass() {
  printf 'PASS\t%s\n' "$1" >> "$receipt_tmp"
}

curl_status() {
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@"
}

auth_curl_status() {
  curl --config "$curl_config" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@"
}

invalid_auth_curl_status() {
  curl --config "$invalid_curl_config" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 30 "$@"
}

require_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl_status "$@" || true)"
  [[ "$actual" == "$expected" ]] || fail "unexpected HTTP status for $expected check"
}

require_auth_status() {
  local expected="$1"
  shift
  local actual
  actual="$(auth_curl_status "$@" || true)"
  [[ "$actual" == "$expected" ]] || fail "unexpected authenticated HTTP status for $expected check"
}

require_auth_download_200() {
  local output="$1" url="$2" actual
  actual="$(curl --config "$curl_config" --silent --show-error --output "$output" --write-out '%{http_code}' --max-time 30 "$url" || true)"
  [[ "$actual" == 200 ]] || fail "authenticated WebDAV GET did not return HTTP 200"
}

verify_dav_absent() {
  local actual get_status
  actual="$(auth_curl_status -X PROPFIND -H 'Depth: 0' "$webdav_root/$test_folder" || true)"
  get_status="$(auth_curl_status "$webdav_root/$test_folder" || true)"
  [[ "$actual" == 404 && "$get_status" == 404 ]]
}

cleanup_webdav_folder() {
  local delete_status
  delete_status="$(auth_curl_status -X DELETE "$webdav_root/$test_folder" || true)"
  [[ "$delete_status" == 204 || "$delete_status" == 404 ]] || return 1
  verify_dav_absent
}

wait_healthy() {
  local container="$1" state
  for _ in $(seq 1 90); do
    state="$(docker inspect "$container" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')"
    [[ "$state" == healthy ]] && return 0
    sleep 2
  done
  return 1
}

capture_preexisting() {
  local output="$1" name
  : > "$output"
  while IFS= read -r name; do
    case "$name" in owncloud-server|owncloud-redis) continue ;; esac
    docker inspect "$name" --format '{{.Name}}\t{{.State.Running}}\t{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}\t{{.RestartCount}}' | sed 's#^/##' >> "$output"
  done < <(docker ps -a --format '{{.Names}}')
  sort -o "$output" "$output"
}

capture_public_listeners() {
  local output="$1"
  ss -H -ltn | awk '$4 !~ /^(127\.0\.0\.1|\[::1\]|::1):/ {print "tcp\t" $4}' | sort > "$output"
}

path_contains() {
  local parent="$1" child="$2"
  [[ "$parent" == / ]] && return 0
  [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

bind_source_touches_data_root() {
  local source="$1" canonical_source canonical_data_root
  [[ -e "$source" ]] || fail "a non-ownCloud bind mount source cannot be resolved"
  [[ -e "$data_root" ]] || fail "ownCloud data root cannot be resolved"
  canonical_source="$(readlink -f -- "$source")" || fail "a non-ownCloud bind mount source cannot be canonicalized"
  canonical_data_root="$(readlink -f -- "$data_root")" || fail "ownCloud data root cannot be canonicalized"
  path_contains "$canonical_source" "$canonical_data_root" || \
    path_contains "$canonical_data_root" "$canonical_source"
}

itservice_status() {
  local scheme="$1"
  curl --insecure --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
    -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" || true
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if (( folder_created )); then
    if ! cleanup_webdav_folder; then
      printf 'FAIL\tWebDAV cleanup failed or folder remains\n' >> "$receipt_tmp"
      status=1
    fi
  fi
  shred --remove=unlink --zero "$curl_config" "$invalid_curl_config" "$payload_file" "$download_file" \
    "$preexisting_before" "$preexisting_after" "$public_before" "$public_after" 2>/dev/null || true
  unset admin_password
  if (( status != 0 )); then
    printf 'FAIL\tacceptance terminated\n' >> "$receipt_tmp"
  fi
  sudo install -d -o root -g root -m 0700 "$receipt_root"
  sudo install -o root -g root -m 0600 "$receipt_tmp" "$receipt_path"
  rm -f "$receipt_tmp"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "${TMUX:-}" == *","* ]] || fail "run only inside tmux session owncloud-setup"
[[ "$(tmux display-message -p '#S')" == owncloud-setup ]] || fail "unexpected tmux session"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
sudo test -r "$password_file" || fail "admin recovery file is not readable through sudo"
admin_password="$(sudo cat "$password_file")"
[[ -n "$admin_password" ]] || fail "admin recovery file is empty"
printf 'user = "ocadmin:%s"\n' "$admin_password" > "$curl_config"
printf 'user = "ocadmin:invalid-acceptance-credential"\n' > "$invalid_curl_config"
unset admin_password

capture_preexisting "$preexisting_before"
capture_public_listeners "$public_before"
http_before="$(itservice_status http)"
https_before="$(itservice_status https)"
[[ "$http_before" == 200 && "$https_before" == 200 ]] || fail "itservice loopback HTTP/HTTPS must both be 200 before acceptance"

for container in owncloud-redis owncloud-server; do
  wait_healthy "$container" || fail "$container is not healthy"
done
pass "container health"
ssh -o BatchMode=yes -o ConnectTimeout=10 db-server "docker exec owncloud-postgres pg_isready -U owncloud_app -d owncloud" >/dev/null || fail "PostgreSQL readiness"
pass "PostgreSQL readiness"
[[ "$(docker exec owncloud-redis redis-cli ping)" == PONG ]] || fail "Redis ping"
pass "Redis ping"
require_status 200 http://127.0.0.1:9200/status.php
pass "ownCloud status"
docker exec --user www-data owncloud-server occ user:list ocadmin --output=json | grep -Fq ocadmin \
  || fail "occ user list does not contain ocadmin"
pass "occ user list contains ocadmin"
require_auth_status 200 -H 'OCS-APIRequest: true' 'http://127.0.0.1:9200/ocs/v1.php/cloud/capabilities?format=json'
pass "OCS capabilities"
require_status 401 -X PROPFIND -H 'Depth: 0' "$webdav_root/"
pass "WebDAV unauthorized PROPFIND"
[[ "$(invalid_auth_curl_status -X PROPFIND -H 'Depth: 0' "$webdav_root/" || true)" == 401 ]] || fail "WebDAV wrong-token PROPFIND"
pass "WebDAV wrong-token PROPFIND"
require_auth_status 207 -X PROPFIND -H 'Depth: 0' "$webdav_root/"
pass "WebDAV authenticated PROPFIND"

require_auth_status 201 -X MKCOL "$webdav_root/$test_folder"
folder_created=1
printf '%s\n' "$run_id" > "$payload_file"
source_sha="$(sha256sum "$payload_file" | awk '{print $1}')"
require_auth_status 201 -T "$payload_file" "$webdav_root/$test_folder/$test_file"
require_auth_download_200 "$download_file" "$webdav_root/$test_folder/$test_file"
[[ "$(sha256sum "$download_file" | awk '{print $1}')" == "$source_sha" ]] || fail "WebDAV GET checksum"
require_auth_status 201 -X MOVE -H "Destination: $webdav_root/$test_folder/renamed-$test_file" "$webdav_root/$test_folder/$test_file"
file_count="$(sudo find "$data_root" -type f -name "renamed-$test_file" -printf 1 | wc -c)"
(( file_count > 0 )) || fail "test file was not present in data mount"
pass "data mount file present count=$file_count"

docker restart owncloud-server >/dev/null
wait_healthy owncloud-server || fail "ownCloud did not become healthy after restart"
require_auth_download_200 "$download_file" "$webdav_root/$test_folder/renamed-$test_file"
[[ "$(sha256sum "$download_file" | awk '{print $1}')" == "$source_sha" ]] || fail "WebDAV checksum after restart"
require_auth_status 204 -X DELETE "$webdav_root/$test_folder"
verify_dav_absent || fail "test WebDAV folder is still present after normal DELETE"
folder_created=0
pass "WebDAV lifecycle and persistence"

if docker inspect owncloud-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q '^OWNCLOUD_ADMIN_'; then fail "admin environment remains"; fi
[[ "$(docker inspect owncloud-server --format '{{.HostConfig.Privileged}}')" == false ]] || fail "ownCloud is privileged"
if docker inspect owncloud-server --format '{{range .Mounts}}{{println .Source " " .Destination}}{{end}}' | grep -q '/var/run/docker.sock'; then fail "docker socket mounted"; fi
[[ "$(docker port owncloud-server 8080)" == '127.0.0.1:9200' ]] || fail "ownCloud bind is not exactly loopback 9200"
for container in owncloud-redis; do
  [[ -z "$(docker inspect "$container" --format '{{range $p, $v := .NetworkSettings.Ports}}{{if $v}}{{$p}}{{end}}{{end}}')" ]] || fail "$container has a host port"
done
while IFS= read -r name; do
  case "$name" in owncloud-server|owncloud-redis) continue ;; esac
  while IFS=$'\t' read -r mount_type source; do
    [[ "$mount_type" == bind ]] || continue
    if bind_source_touches_data_root "$source"; then
      fail "another container bind-mount touches ownCloud data"
    fi
  done < <(docker inspect "$name" --format '{{range .Mounts}}{{printf "%s\t%s\n" .Type .Source}}{{end}}')
done < <(docker ps -a --format '{{.Names}}')
if sudo nginx -T 2>&1 | grep -Eq '^[[:space:]]*(root|alias)[[:space:]]+/mnt/owncloud-data'; then fail "Nginx exposes ownCloud data path"; fi
sudo nginx -t >/dev/null
sudo ufw status | head -n 1 | grep -qx 'Status: active' || fail "UFW is not active"
capture_public_listeners "$public_after"
cmp -s "$public_before" "$public_after" || fail "public listener tuples changed"
if grep -Eq ':(3306|6379|9200)$' "$public_after"; then fail "database, Redis, or ownCloud is publicly listening"; fi
http_after="$(itservice_status http)"
https_after="$(itservice_status https)"
[[ "$http_after" == 200 && "$https_after" == 200 && "$http_after" == "$http_before" && "$https_after" == "$https_before" ]] || fail "itservice HTTP/HTTPS changed"
capture_preexisting "$preexisting_after"
cmp -s "$preexisting_before" "$preexisting_after" || fail "non-ownCloud container changed"
[[ -z "$(systemctl --failed --no-legend --plain)" ]] || fail "failed system service exists"
root_available_kib="$(df -Pk / | awk 'NR == 2 {print $4}')"
mem_available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
inode_use_percent="$(df -Pi / | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')"
(( root_available_kib >= 50 * 1024 * 1024 )) || fail "root free space below 50 GiB"
(( mem_available_kib >= 8 * 1024 * 1024 )) || fail "available RAM below 8 GiB"
(( inode_use_percent < 90 )) || fail "inode use is 90% or higher"
pass "security, regression, and capacity checks"
printf 'BLOCKED\tBrowser UI form login requires approved public DNS/TLS; OCS and WebDAV passed.\n' >> "$receipt_tmp"
printf 'PASS\tacceptance complete\n' >> "$receipt_tmp"
