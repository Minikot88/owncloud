#!/usr/bin/env bash
set -euo pipefail
umask 077

source_ip=10.128.162.172
listen_ip=10.8.12.10
listen_port=8443
install_root=/opt/owncloud
backup_root=/var/backups/owncloud
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S-%N)"
backup_dir="$backup_root/ip-access-$timestamp"
vhost=/etc/nginx/sites-available/owncloud-ip-8443
enabled_vhost=/etc/nginx/sites-enabled/owncloud-ip-8443
cert_dir=/etc/nginx/ssl/owncloud-ip-8443
key_file=$cert_dir/owncloud-ip-8443.key
cert_file=$cert_dir/owncloud-ip-8443.crt
mutated=0

fail() { echo "IP_ACCESS_FAILED: $*" >&2; exit 1; }

wait_healthy() {
  for _ in $(seq 1 90); do
    [[ "$(docker inspect owncloud-server --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')" == healthy ]] && return 0
    sleep 2
  done
  return 1
}

site_status() {
  local scheme="$1"
  if [[ "$scheme" == https ]]; then
    curl --insecure --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 -H 'Host: itservice.research.psu.ac.th' https://127.0.0.1/ || true
  else
    curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 -H 'Host: itservice.research.psu.ac.th' http://127.0.0.1/ || true
  fi
}

site_body_sha256() {
  local scheme="$1"
  curl --insecure --silent --show-error --max-time 15 -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" | sha256sum | awk '{print $1}'
}

existing_tls_fingerprint() {
  openssl s_client -connect 127.0.0.1:443 -servername itservice.research.psu.ac.th </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null
}

capture_listeners() {
  ss -H -ltn | awk '{print "tcp\t" $4}' | sort
}

ufw_exact_rule_present() { sudo ufw status verbose | awk -v d="$listen_ip" -v p="$listen_port/tcp" -v s="$source_ip" '{sub(/^\[[^]]+\][[:space:]]*/, "")} $1==d && $2==p && $3=="ALLOW" && $4=="IN" && ($5==s || $5==s"/32") {n++} END {exit n==1 ? 0 : 1}'; }

ufw_active() {
  sudo ufw status | head -n 1 | grep -qx 'Status: active'
}

ufw_default_deny_incoming() {
  sudo ufw status verbose | grep -Eq '^Default: deny \(incoming\)'
}

ufw_8443_count() {
  sudo ufw status | awk '/8443/ {count++} END {print count+0}'
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if (( mutated )); then
    bash "$script_dir/rollback-ip-access.sh" --as-root "$backup_dir" >/dev/null 2>&1 || status=1
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "${TMUX:-}" == *","* ]] || fail "run only inside tmux session owncloud-ip-access"
[[ "$(tmux display-message -p '#S')" == owncloud-ip-access ]] || fail "unexpected tmux session"
read -r ssh_source _ <<< "${SSH_CONNECTION:-}"
[[ "$ssh_source" == "$source_ip" ]] || fail "SSH client source does not match the approved /32"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
[[ "$EUID" -eq 0 ]] || exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" --as-root
[[ "${1:-}" == --as-root ]] && shift
if [[ ! -e /proc/$$/fd/9 ]]; then exec 9>/run/lock/owncloud-ip-access.lock; fi
flock -n 9 || fail "another ownCloud IP access operation is running"

sudo nginx -t >/dev/null
ufw_active || fail "UFW is not active"
ufw_default_deny_incoming || fail "UFW incoming default is not deny"
ufw_8443_before="$(ufw_8443_count)"
if [[ "$ufw_8443_before" != 0 ]]; then
  [[ "$ufw_8443_before" == 1 ]] && ufw_exact_rule_present || fail "a broad or conflicting 8443 UFW rule exists"
fi
ss -H -ltn "( sport = :$listen_port )" | grep -q . && fail "port $listen_port is already in use"
[[ ! -e "$vhost" && ! -e "$enabled_vhost" && ! -e "$cert_dir" ]] || fail "temporary vhost or certificate paths already exist"
docker inspect owncloud-server >/dev/null 2>&1 || fail "ownCloud server is missing"
wait_healthy || fail "ownCloud server is not healthy"
[[ "$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 http://127.0.0.1:9200/status.php || true)" == 200 ]] || fail "loopback ownCloud status is unavailable"
gateway="$(docker network inspect owncloud-network --format '{{(index .IPAM.Config 0).Gateway}}')"
server_ip="$(docker inspect owncloud-server --format '{{with index .NetworkSettings.Networks "owncloud-network"}}{{.IPAddress}}{{end}}')"
[[ "$gateway" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && "$server_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && "$gateway" != "$server_ip" ]] || fail "owncloud-network gateway or attachment is invalid"
docker network inspect owncloud-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -Fxq owncloud-server || fail "ownCloud server is not attached to owncloud-network"
docker exec --user www-data owncloud-server occ config:system:get trusted_domains --output=json | docker exec -i owncloud-server php -r '$v=json_decode(stream_get_contents(STDIN), true); if (is_array($v)) foreach ($v as $d) echo $d, "\n";' | grep -Fxq "$listen_ip" || fail "trusted_domains does not contain the exact temporary IP"

sudo install -d -o root -g root -m 0700 "$backup_root"
sudo install -d -o root -g root -m 0700 "$backup_dir"
sudo tar --acls --xattrs --numeric-owner -C / -czf "$backup_dir/etc-nginx-before.tar.gz" etc/nginx
sudo tar --acls --xattrs --numeric-owner -C / -czf "$backup_dir/opt-owncloud-full-root-only-before.tar.gz" opt/owncloud
docker exec --user www-data owncloud-server occ config:system:get trusted_proxies --output=json > "$backup_dir/trusted-proxies-before.json" 2>/dev/null || printf 'null\n' > "$backup_dir/trusted-proxies-before.json"
sudo nginx -T > "$backup_dir/nginx-effective-before.txt" 2>&1
sudo find /etc/nginx -type f ! -path "$vhost" ! -path "$key_file" ! -path "$cert_file" -print0 | sort -z | xargs -0 sha256sum > "$backup_dir/nginx-existing-before.sha256"
capture_listeners > "$backup_dir/listeners-before.tsv"
http_before="$(site_status http)"
https_before="$(site_status https)"
[[ "$http_before" =~ ^[1-9][0-9][0-9]$ && "$https_before" =~ ^[1-9][0-9][0-9]$ ]] || fail "existing HTTP/HTTPS status baseline is unavailable"
printf '%s\n%s\n' "$http_before" "$https_before" > "$backup_dir/site-status-before.tsv"
http_body_before="$(site_body_sha256 http)"
https_body_before="$(site_body_sha256 https)"
tls_fingerprint_before="$(existing_tls_fingerprint)"
[[ -n "$http_body_before" && -n "$https_body_before" && -n "$tls_fingerprint_before" ]] || fail "existing-site body or TLS baseline is unavailable"
printf '%s\n%s\n%s\n' "$http_body_before" "$https_body_before" "$tls_fingerprint_before" > "$backup_dir/site-content-tls-before.tsv"
printf '%s\n' "$ufw_8443_before" > "$backup_dir/ufw-8443-before"
sudo chown -R root:root "$backup_dir"
sudo chmod 0600 "$backup_dir"/*
sudo bash -c 'cd "$1" && find . -maxdepth 1 -type f ! -name BASE_SHA256SUMS ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > BASE_SHA256SUMS && chmod 0600 BASE_SHA256SUMS && sha256sum -c BASE_SHA256SUMS >/dev/null' _ "$backup_dir"

mutated=1
sudo install -d -o root -g root -m 0700 "$cert_dir"
sudo openssl req -x509 -newkey rsa:4096 -nodes -keyout "$key_file" -out "$cert_file" -days 30 \
  -subj "/CN=$listen_ip" -addext "subjectAltName=IP:$listen_ip" >/dev/null 2>&1
sudo chown root:root "$key_file" "$cert_file"
sudo chmod 0600 "$key_file"
sudo chmod 0644 "$cert_file"
sudo tee "$vhost" >/dev/null <<EOF
server {
    listen $listen_ip:$listen_port ssl;
    server_name $listen_ip;
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    # HSTS intentionally omitted for temporary IP access.
    client_max_body_size 2g;
    proxy_request_buffering off;
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    if (\$http_host != "10.8.12.10:8443") { return 444; }
    location / {
        proxy_pass http://127.0.0.1:9200;
        proxy_http_version 1.1;
        proxy_set_header Host 10.8.12.10:8443;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host 10.8.12.10:8443;
        proxy_set_header X-Forwarded-Port 8443;
    }
}
EOF
sudo ln -s "$vhost" "$enabled_vhost"
sudo nginx -t >/dev/null

mapfile -t trusted_proxies < <(docker exec -i owncloud-server php -r '$v=json_decode(stream_get_contents(STDIN), true); if (is_array($v)) foreach ($v as $proxy) echo $proxy, "\n";' < "$backup_dir/trusted-proxies-before.json")
if (( ${#trusted_proxies[@]} == 0 )); then
  printf '0\t%s\n' "$gateway" > "$backup_dir/trusted-proxy-added-index"
  sudo chown root:root "$backup_dir/trusted-proxy-added-index"; sudo chmod 0600 "$backup_dir/trusted-proxy-added-index"
  docker exec --user www-data owncloud-server occ config:system:set trusted_proxies 0 --value="$gateway" >/dev/null
elif (( ${#trusted_proxies[@]} == 1 )) && [[ "${trusted_proxies[0]}" == "$gateway" ]]; then
  :
else
  fail "trusted_proxies must be empty or exactly the discovered gateway"
fi
trusted_proxy_json="$(docker exec --user www-data owncloud-server occ config:system:get trusted_proxies --output=json)"
[[ "$(tr -d '[:space:]' <<< "$trusted_proxy_json")" == "[\"$gateway\"]" ]] || fail "trusted proxy is not the exact discovered-gateway singleton"
if ufw_exact_rule_present; then
  printf 'preexisting\n' > "$backup_dir/ufw-rule-intent"
  sudo chown root:root "$backup_dir/ufw-rule-intent"; sudo chmod 0600 "$backup_dir/ufw-rule-intent"
else
  printf 'added\n' > "$backup_dir/ufw-rule-intent"
  sudo chown root:root "$backup_dir/ufw-rule-intent"; sudo chmod 0600 "$backup_dir/ufw-rule-intent"
  sudo ufw allow from "$source_ip" to "$listen_ip" port "$listen_port" proto tcp comment 'owncloud temporary IP access' >/dev/null
fi
sudo nginx -t >/dev/null
sudo systemctl reload nginx
sudo nginx -t >/dev/null
sudo find /etc/nginx -type f ! -path "$vhost" ! -path "$key_file" ! -path "$cert_file" -print0 | sort -z | xargs -0 sha256sum > "$backup_dir/nginx-existing-after.sha256"
sudo cmp -s "$backup_dir/nginx-existing-before.sha256" "$backup_dir/nginx-existing-after.sha256" || fail "an existing Nginx file changed"
[[ "$(curl --cacert "$cert_file" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 20 -H "Host: $listen_ip:$listen_port" "https://$listen_ip:$listen_port/status.php" || true)" == 200 ]] || fail "temporary HTTPS status validation failed"
[[ "$(curl --cacert "$cert_file" --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 20 -X PROPFIND -H 'Depth: 0' -H "Host: $listen_ip:$listen_port" "https://$listen_ip:$listen_port/remote.php/dav/files/ocadmin/" || true)" == 401 ]] || fail "temporary HTTPS WebDAV unauthorized status validation failed"
ufw_exact_rule_present || fail "exact source-limited UFW rule is missing"
ufw_active || fail "UFW is not active after temporary rule application"
ufw_default_deny_incoming || fail "UFW incoming default changed"
[[ "$(ufw_8443_count)" == 1 ]] || fail "8443 UFW rule count is not exactly one"
sudo openssl x509 -in "$cert_file" -noout -ext subjectAltName | grep -Fq "IP Address:$listen_ip" || fail "certificate IP SAN is invalid"
[[ "$(sudo stat -c '%U:%G:%a' "$key_file")" == root:root:600 ]] || fail "certificate key permissions are invalid"
capture_listeners > "$backup_dir/listeners-after.tsv"
[[ -z "$(comm -23 "$backup_dir/listeners-before.tsv" "$backup_dir/listeners-after.tsv")" ]] || fail "an existing listener disappeared"
[[ "$(comm -13 "$backup_dir/listeners-before.tsv" "$backup_dir/listeners-after.tsv")" == $'tcp\t'"$listen_ip:$listen_port" ]] || fail "unexpected listener exposure"
if ss -H -ltn | awk '$4 !~ /^(127\.0\.0\.1|\[::1\]|::1):/ {print $4}' | grep -Eq ':(9200|3306|6379)$'; then fail "ownCloud, MariaDB, or Redis is publicly exposed"; fi
http_after="$(site_status http)"
https_after="$(site_status https)"
[[ "$http_after" == "$http_before" && "$https_after" == "$https_before" ]] || fail "existing HTTP/HTTPS status regression"
[[ "$(site_body_sha256 http)" == "$http_body_before" && "$(site_body_sha256 https)" == "$https_body_before" && "$(existing_tls_fingerprint)" == "$tls_fingerprint_before" ]] || fail "existing-site body or TLS regression"
wait_healthy || fail "ownCloud health regression"
[[ "$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 http://127.0.0.1:9200/status.php || true)" == 200 ]] || fail "loopback ownCloud regression"
final_manifest="$backup_dir/.SHA256SUMS.$$.tmp"
sudo bash -c 'cd "$1" && find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name ".SHA256SUMS.*.tmp" -print0 | sort -z | xargs -0 sha256sum > "$2" && chmod 0600 "$2" && sha256sum -c "$2" >/dev/null && mv -f "$2" SHA256SUMS' _ "$backup_dir" "$final_manifest"
mutated=0
echo "IP_ACCESS_APPLY_PASS backup=$backup_dir gateway=$gateway"
