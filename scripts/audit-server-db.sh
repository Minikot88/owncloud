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

section DOCKER_POSTGRES
docker --version
docker compose version
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker network ls
docker volume ls
docker exec prod-postgres postgres --version

section DATABASE_METADATA
docker exec prod-postgres sh -lc \
  'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;"'
docker exec prod-postgres sh -lc \
  'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT rolname || chr(124) || rolsuper || chr(124) || rolcreatedb || chr(124) || rolcreaterole || chr(124) || rolreplication FROM pg_roles ORDER BY 1;"'

section NETWORK_PRIVILEGE
if sudo -n true >/dev/null 2>&1; then
  printf 'sudo_cache=READY\n'
  sudo -n ss -lntup
  sudo -n ufw status verbose
  sudo -n iptables -S DOCKER-USER 2>&1 || true
  sudo -n systemctl status postgres-firewall.service --no-pager 2>&1 || true
else
  printf 'sudo_cache=UNAVAILABLE\n'
  ss -lntup 2>&1 || true
fi

section SERVICES
systemctl --failed --no-pager
systemctl is-active docker ssh 2>&1 || true

