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
docker info --format 'server={{.ServerVersion}} driver={{.Driver}} root={{.DockerRootDir}} cgroup={{.CgroupDriver}}' 2>&1 || true

section DOCKER_CONTAINERS
docker ps -a
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker ps -a --format '{{.Names}}|project={{.Label "com.docker.compose.project"}}|service={{.Label "com.docker.compose.service"}}|status={{.Status}}'
docker inspect --format '{{.Name}}|image={{.Config.Image}}|restart={{.HostConfig.RestartPolicy.Name}}|privileged={{.HostConfig.Privileged}}|networkmode={{.HostConfig.NetworkMode}}|ports={{json .HostConfig.PortBindings}}|mounts={{json .Mounts}}' $(docker ps -aq) 2>&1 || true

section DOCKER_RESOURCES
docker compose ls
docker network ls
docker volume ls
docker images
docker system df

section NAME_CONFLICTS
for resource in owncloud owncloud-server owncloud-redis owncloud-network owncloud-config owncloud-redis-data; do
  printf '%s|' "$resource"
  docker ps -a --format '{{.Names}}' | grep -Fx "$resource" >/dev/null && printf 'container ' || true
  docker network ls --format '{{.Name}}' | grep -Fx "$resource" >/dev/null && printf 'network ' || true
  docker volume ls --format '{{.Name}}' | grep -Fx "$resource" >/dev/null && printf 'volume ' || true
  docker compose ls --format json | grep -Fq "\"Name\":\"$resource\"" && printf 'compose-project ' || true
  printf '\n'
done

section PRIVILEGED_BASELINE
if sudo -n true >/dev/null 2>&1; then
  printf 'sudo_cache=READY\n'
  sudo -n ss -lntup
  sudo -n ufw status verbose
  sudo -n nginx -t
  sudo -n nginx -T 2>/dev/null |
    grep -E '^[[:space:]]*(listen|server_name|proxy_pass|ssl_certificate|ssl_protocols|client_max_body_size|root|alias)[[:space:]]' || true
else
  printf 'sudo_cache=UNAVAILABLE\n'
  ss -lntup 2>&1 || true
fi

section OWN_CLOUD_PATHS
stat -c '%A %U:%G %s %y %n' /opt/owncloud /mnt/owncloud-data 2>&1 || true
find /opt/owncloud -maxdepth 2 -mindepth 1 -printf '%M %u:%g %s %TY-%Tm-%TdT%TH:%TM:%TS %p\n' 2>/dev/null | sort

section SERVICES
systemctl --failed --no-pager
systemctl is-active nginx docker ssh 2>&1 || true

section EXISTING_HTTP
curl -sS -o /dev/null -w 'host_http=%{http_code}\n' -H 'Host: itservice.research.psu.ac.th' http://127.0.0.1/ || true
curl -k -sS -o /dev/null -w 'host_https=%{http_code}\n' -H 'Host: itservice.research.psu.ac.th' https://127.0.0.1/ || true

