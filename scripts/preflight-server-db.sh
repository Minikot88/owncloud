#!/usr/bin/env bash
set -u

section() { printf '\n===%s===\n' "$1"; }

section IDENTITY_NETWORK
hostname
hostname -I
ip -br addr
ip route

section OS_RESOURCES
cat /etc/os-release
free -h
df -h

section DOCKER_ENGINE
systemctl is-active docker
systemctl is-enabled docker
docker --version
docker compose version
docker ps -a
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker compose ls
docker network ls
docker volume ls
docker images
docker system df
docker inspect --format '{{.Name}}|image={{.Config.Image}}|restart={{.HostConfig.RestartPolicy.Name}}|privileged={{.HostConfig.Privileged}}|networkmode={{.HostConfig.NetworkMode}}|ports={{json .HostConfig.PortBindings}}|mounts={{json .Mounts}}' $(docker ps -aq) 2>&1 || true

section POSTGRES_VERSION_METADATA
docker exec prod-postgres postgres --version
docker exec prod-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SHOW server_version; SHOW listen_addresses; SHOW port; SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;"'
docker exec prod-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT rolname || chr(124) || rolsuper || chr(124) || rolcreatedb || chr(124) || rolcreaterole || chr(124) || rolbypassrls || chr(124) || rolreplication FROM pg_roles ORDER BY 1;"'

section NETWORK_SECURITY
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

