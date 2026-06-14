#!/usr/bin/env bash
# ECR 로그인 토큰(12h) 갱신 → k3s registries.yaml
# EC2 IAM role(ec2-k3s-ecr-read) 필요. 맥 Access Key 불필요.
set -euo pipefail

CONFIG="${CONFIG:-/etc/default/k3s-ecr-renew}"
[[ -f "$CONFIG" ]] && source "$CONFIG"

: "${AWS_REGION:=ap-southeast-2}"
: "${ECR_REGISTRY:=019511184889.dkr.ecr.ap-southeast-2.amazonaws.com}"
# cron: RESTART_K3S=true 로 실행 / 부팅 systemd: Environment=RESTART_K3S=false
: "${RESTART_K3S:=true}"
: "${K3S_REGISTRIES_PATH:=/etc/rancher/k3s/registries.yaml}"

log() { echo "[$(date -Iseconds)] $*"; }

if ! command -v aws >/dev/null 2>&1; then
  log "ERROR: aws CLI 없음. AWS CLI v2 설치 후 재시도."
  exit 1
fi

log "ECR token 갱신 시작 (region=$AWS_REGION)"
TOKEN="$(aws ecr get-login-password --region "$AWS_REGION")"

sudo mkdir -p "$(dirname "$K3S_REGISTRIES_PATH")"
sudo tee "$K3S_REGISTRIES_PATH" >/dev/null <<EOF
configs:
  "${ECR_REGISTRY}":
    auth:
      username: AWS
      password: ${TOKEN}
EOF

log "registries.yaml 갱신 완료"

if [[ "$RESTART_K3S" == "true" ]]; then
  if systemctl is-active --quiet k3s 2>/dev/null; then
    log "k3s restart (10~30초 서비스 끊김 가능)"
    sudo systemctl restart k3s
    log "k3s restart 완료"
  else
    log "k3s inactive — restart 생략 (부팅 시 note-boot-k3s-start 가 start)"
  fi
else
  log "RESTART_K3S=false — 다음 pull 전까지는 예전 토큰일 수 있음"
fi

log "done"
