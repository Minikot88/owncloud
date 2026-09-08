#!/usr/bin/env bash
set -u

section() { printf '\n===%s===\n' "$1"; }

section IDENTITY
hostname
hostname -I
ip -br addr
ip route

section OS_RESOURCES
cat /etc/os-release
free -h
df -h

section DOCKER
docker --version
docker compose version
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker network ls
docker volume ls

section PRIVILEGE
if sudo -n true >/dev/null 2>&1; then
  printf 'sudo_cache=READY\n'
  sudo -n ss -lntup
  sudo -n ufw status verbose
  sudo -n nginx -t
  sudo -n nginx -T 2>/dev/null |
    grep -E '^[[:space:]]*(listen|server_name|proxy_pass|ssl_protocols|client_max_body_size|root)[[:space:]]' || true
else
  printf 'sudo_cache=UNAVAILABLE\n'
  ss -lntup 2>&1 || true
fi

section SERVICES
systemctl --failed --no-pager
systemctl is-active nginx docker ssh 2>&1 || true

section OWNCLOUD_PATHS
stat -c '%A %U:%G %s %y %n' /opt/owncloud /mnt/owncloud-data 2>&1 || true
find /opt/owncloud -maxdepth 2 -mindepth 1 \
  -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n' 2>/dev/null | sort
find /mnt/owncloud-data -maxdepth 1 -mindepth 1 \
  -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n' 2>/dev/null | sort

section EXISTING_PRODUCTION
curl -sS -o /dev/null -w 'itservice_http=%{http_code}\n' \
  -H 'Host: itservice.research.psu.ac.th' http://127.0.0.1/ || true
curl -sS -o /dev/null -w 'frontend_loopback=%{http_code}\n' http://127.0.0.1:8080/ || true
curl -sS -o /dev/null -w 'backend_readiness=%{http_code}\n' http://127.0.0.1:4001/readiness || true

