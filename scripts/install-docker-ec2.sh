#!/usr/bin/env bash
# EC2 호스트에 Docker CE (Jenkins Pod가 /var/run/docker.sock 사용)
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행: sudo bash $0"
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  echo "docker 이미 설치됨: $(docker --version)"
  systemctl enable docker
  systemctl start docker
  exit 0
fi

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  >/etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu || true

echo "OK: $(docker --version)"
echo "Jenkins Pod는 hostPath 로 docker.sock 마운트 (학습용 privileged)"
