#!/usr/bin/env bash
set -euo pipefail
umask 077

source_ip=10.128.162.172
listen_ip=10.8.12.10
listen_port=8443
backup_root=/var/backups/owncloud
vhost=/etc/nginx/sites-available/owncloud-ip-8443
enabled_vhost=/etc/nginx/sites-enabled/owncloud-ip-8443
cert_dir=/etc/nginx/ssl/owncloud-ip-8443
key_file=$cert_dir/owncloud-ip-8443.key
cert_file=$cert_dir/owncloud-ip-8443.crt

ufw_exact_rule_present() { sudo ufw status verbose | awk -v d="$listen_ip" -v p="$listen_port/tcp" -v s="$source_ip" '{sub(/^\[[^]]+\][[:space:]]*/, "")} $1==d && $2==p && $3=="ALLOW" && $4=="IN" && ($5==s || $5==s"/32") {n++} END {exit n==1 ? 0 : 1}'; }
ufw_8443_count() { sudo ufw status | awk '/8443/ {count++} END {print count+0}'; }
ufw_active() { sudo ufw status | head -n 1 | grep -qx 'Status: active'; }
ufw_default_deny_incoming() { sudo ufw status verbose | grep -Eq '^Default: deny \(incoming\)'; }
site_status() { local scheme="$1"; curl --insecure --silent --output /dev/null --write-out '%{http_code}' --max-time 15 -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" || true; }
site_body_sha256() { local scheme="$1"; curl --insecure --silent --max-time 15 -H 'Host: itservice.research.psu.ac.th' "$scheme://127.0.0.1/" | sha256sum | awk '{print $1}'; }
existing_tls_fingerprint() { openssl s_client -connect 127.0.0.1:443 -servername itservice.research.psu.ac.th </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null; }
listeners() { ss -H -ltn | awk '{print "tcp\t" $4}' | sort; }
wait_healthy() { for _ in $(seq 1 90); do [[ "$(docker inspect owncloud-server --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}')" == healthy ]] && return 0; sleep 2; done; return 1; }

fail() { echo "IP_ACCESS_ROLLBACK_FAILED: $*" >&2; exit 1; }

[[ "${TMUX:-}" == *","* ]] || fail "run only inside tmux session owncloud-ip-access"
[[ "$(tmux display-message -p '#S')" == owncloud-ip-access ]] || fail "unexpected tmux session"
read -r ssh_source _ <<< "${SSH_CONNECTION:-}"
[[ "$ssh_source" == "$source_ip" ]] || fail "SSH client source does not match the approved /32"
sudo -n true >/dev/null 2>&1 || fail "sudo cache unavailable"
[[ "$EUID" -eq 0 ]] || exec sudo -n env "TMUX=${TMUX:-}" "SSH_CONNECTION=${SSH_CONNECTION:-}" bash "$0" --as-root "$@"
[[ "${1:-}" == --as-root ]] && shift
if [[ ! -e /proc/$$/fd/9 ]]; then exec 9>/run/lock/owncloud-ip-access.lock; fi
flock -n 9 || fail "another ownCloud IP access operation is running"
[[ "$#" -eq 1 ]] || fail "usage: rollback-ip-access.sh /var/backups/owncloud/ip-access-<timestamp>"
backup_dir="$1"
[[ "$backup_dir" == "$backup_root"/ip-access-* && -d "$backup_dir" ]] || fail "invalid backup directory"
[[ -f "$backup_dir/trusted-proxies-before.json" && -f "$backup_dir/ufw-8443-before" && -f "$backup_dir/BASE_SHA256SUMS" ]] || fail "backup is incomplete"
sudo bash -c 'cd "$1" && sha256sum -c BASE_SHA256SUMS >/dev/null' _ "$backup_dir" || fail "base backup manifest verification failed"
if [[ -f "$backup_dir/SHA256SUMS" ]]; then
  sudo bash -c 'cd "$1" && sha256sum -c SHA256SUMS >/dev/null' _ "$backup_dir" || fail "final backup manifest verification failed"
fi

ufw_before="$(cat "$backup_dir/ufw-8443-before")"
ufw_intent=''
[[ -f "$backup_dir/ufw-rule-intent" ]] && ufw_intent="$(cat "$backup_dir/ufw-rule-intent")"
case "$ufw_intent" in
  added)
    if ufw_exact_rule_present; then
      sudo ufw --force delete allow from "$source_ip" to "$listen_ip" port "$listen_port" proto tcp >/dev/null || fail "could not remove temporary UFW rule"
    elif [[ "$(ufw_8443_count)" != 0 ]]; then
      fail "conflicting 8443 UFW rule remains"
    fi
    [[ "$(ufw_8443_count)" == 0 ]] || fail "8443 UFW rule remains after temporary-rule rollback"
    ;;
  preexisting)
    [[ "$(ufw_8443_count)" == 1 ]] && ufw_exact_rule_present || fail "pre-existing approved 8443 UFW rule changed"
    ;;
  '')
    if [[ "$ufw_before" == 0 ]]; then
      [[ "$(ufw_8443_count)" == 0 ]] || fail "8443 UFW state changed before intent marker"
    elif [[ "$ufw_before" == 1 ]]; then
      [[ "$(ufw_8443_count)" == 1 ]] && ufw_exact_rule_present || fail "pre-existing approved 8443 UFW rule changed before intent marker"
    else
      fail "invalid preflight 8443 UFW count"
    fi
    ;;
  *) fail "invalid UFW intent marker" ;;
esac
sudo rm -f -- "$enabled_vhost" "$vhost" "$key_file" "$cert_file"
sudo rmdir "$cert_dir" 2>/dev/null || true
sudo nginx -t >/dev/null
sudo systemctl reload nginx
sudo nginx -t >/dev/null
if [[ -f "$backup_dir/trusted-proxy-added-index" ]]; then
  IFS=$'\t' read -r trusted_proxy_index trusted_proxy_gateway < "$backup_dir/trusted-proxy-added-index"
  saved_proxy_json="$(tr -d '[:space:]' < "$backup_dir/trusted-proxies-before.json")"
  [[ "$saved_proxy_json" == null || "$saved_proxy_json" == '[]' ]] || fail "trusted proxy baseline conflicts with temporary marker"
  current_proxy_json="$(docker exec --user www-data owncloud-server occ config:system:get trusted_proxies --output=json 2>/dev/null || printf null)"
  normalized_proxy_json="$(tr -d '[:space:]' <<< "$current_proxy_json")"
  if [[ "$normalized_proxy_json" == "[\"$trusted_proxy_gateway\"]" ]]; then
    docker exec --user www-data owncloud-server occ config:system:delete trusted_proxies "$trusted_proxy_index" >/dev/null || fail "could not remove temporary trusted proxy"
  elif [[ "$normalized_proxy_json" != null && "$normalized_proxy_json" != '[]' ]]; then
    fail "trusted proxy state conflicts with temporary marker"
  fi
  after_proxy_json="$(docker exec --user www-data owncloud-server occ config:system:get trusted_proxies --output=json 2>/dev/null || printf null)"
  normalized_after_proxy_json="$(tr -d '[:space:]' <<< "$after_proxy_json")"
  [[ "$normalized_after_proxy_json" == "$saved_proxy_json" || ( "$normalized_after_proxy_json" == null && "$saved_proxy_json" == '[]' ) || ( "$normalized_after_proxy_json" == '[]' && "$saved_proxy_json" == null ) ]] || fail "trusted proxy rollback did not restore empty baseline"
fi
ufw_active && ufw_default_deny_incoming || fail "UFW policy regression"
ss -H -ltn "( sport = :$listen_port )" | grep -q . && fail "8443 listener remains after rollback"
wait_healthy || fail "ownCloud health regression"
mapfile -t site_before < "$backup_dir/site-status-before.tsv"
mapfile -t content_tls_before < "$backup_dir/site-content-tls-before.tsv"
[[ "$(site_status http)" == "${site_before[0]}" && "$(site_status https)" == "${site_before[1]}" && "$(site_body_sha256 http)" == "${content_tls_before[0]}" && "$(site_body_sha256 https)" == "${content_tls_before[1]}" && "$(existing_tls_fingerprint)" == "${content_tls_before[2]}" ]] || fail "existing-site regression after rollback"
rollback_listeners="$(mktemp)"
listeners > "$rollback_listeners"
[[ -z "$(comm -23 "$backup_dir/listeners-before.tsv" "$rollback_listeners")" ]] || fail "a baseline listener disappeared after rollback"
rm -f "$rollback_listeners"
[[ "$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 http://127.0.0.1:9200/status.php || true)" == 200 ]] || fail "loopback ownCloud status regression"
echo "IP_ACCESS_ROLLBACK_PASS backup=$backup_dir"
