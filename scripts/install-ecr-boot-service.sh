#!/usr/bin/env bash
# EC2 부팅 시 ECR 토큰 갱신 (k3s 시작 전 registries.yaml 준비)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/ecr-registries-renew.sh"
CONFIG_PATH="/etc/default/k3s-ecr-renew"
SERVICE_NAME="note-boot-ecr-renew"
START_SERVICE="note-boot-k3s-start"
LOG_PATH="/var/log/note-boot-ecr-renew.log"

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ECR_REGISTRY="${ECR_REGISTRY:-019511184889.dkr.ecr.ap-northeast-2.amazonaws.com}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

bash "$SCRIPT_DIR/cleanup-legacy-boot.sh"

install -m 755 "$SCRIPT_DIR/ecr-registries-renew.sh" "$INSTALL_PATH"

if [[ ! -f "$CONFIG_PATH" ]]; then
  cat >"$CONFIG_PATH" <<EOF
AWS_REGION=${AWS_REGION}
ECR_REGISTRY=${ECR_REGISTRY}
EOF
  chmod 644 "$CONFIG_PATH"
fi

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Refresh ECR credentials for k3s (on boot)
After=network-online.target note-boot-k3s-cleanup.service
Before=${START_SERVICE}.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${CONFIG_PATH}
Environment=RESTART_K3S=false
TimeoutStartSec=120
ExecStart=${INSTALL_PATH}
StandardOutput=append:${LOG_PATH}
StandardError=append:${LOG_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

echo "설치 완료: ${SERVICE_NAME}.service"
echo "  부팅 순서: network → cleanup → ECR 갱신 → k3s start"
echo "  로그: ${LOG_PATH}"
echo ""
echo "k3s 부팅 체인 미설치 시:"
echo "  sudo bash ${SCRIPT_DIR}/install-k3s-boot-recovery.sh"
echo ""
echo "상태 확인:"
echo "  systemctl status note-boot-k3s-cleanup ${SERVICE_NAME} ${START_SERVICE} k3s"
echo "  journalctl -u ${SERVICE_NAME} -n 20"
