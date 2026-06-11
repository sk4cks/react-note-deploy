#!/usr/bin/env bash
# EC2 부팅 시 ECR 토큰 갱신 (인스턴스 Stop→Start 후 ErrImagePull 방지)
# k3s 시작 전에 registries.yaml 갱신 (RESTART_K3S=false)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/ecr-registries-renew.sh"
CONFIG_PATH="/etc/default/k3s-ecr-renew"
# k3s-killall은 k3s*.service 전부 stop — note- 접두사 사용
SERVICE_NAME="note-boot-ecr-renew"
LEGACY_SERVICE="k3s-ecr-renew-onboot"
LOG_PATH="/var/log/note-boot-ecr-renew.log"
LEGACY_LOG="/var/log/k3s-ecr-renew-onboot.log"

AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECR_REGISTRY="${ECR_REGISTRY:-019511184889.dkr.ecr.ap-southeast-2.amazonaws.com}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

install -m 755 "$SCRIPT_DIR/ecr-registries-renew.sh" "$INSTALL_PATH"

# cron과 공유 설정 (부팅 시에는 k3s restart 불필요)
if [[ ! -f "$CONFIG_PATH" ]]; then
  cat >"$CONFIG_PATH" <<EOF
AWS_REGION=${AWS_REGION}
ECR_REGISTRY=${ECR_REGISTRY}
RESTART_K3S=true
EOF
  chmod 644 "$CONFIG_PATH"
fi

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

if [[ -f "$LEGACY_LOG" && ! -f "$LOG_PATH" ]]; then
  cp -a "$LEGACY_LOG" "$LOG_PATH"
fi

systemctl disable --now "${LEGACY_SERVICE}.service" 2>/dev/null || true
rm -f "/etc/systemd/system/${LEGACY_SERVICE}.service"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Refresh ECR credentials for k3s (on boot)
After=network-online.target note-boot-k3s-cleanup.service
Before=k3s.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${CONFIG_PATH}
Environment=RESTART_K3S=false
ExecStart=${INSTALL_PATH}
StandardOutput=append:${LOG_PATH}
StandardError=append:${LOG_PATH}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

echo "설치 완료: ${SERVICE_NAME}.service"
echo "  부팅 순서: network → ECR 갱신 → k3s 시작"
echo "  로그: ${LOG_PATH}"
echo ""
echo "상태 확인:"
echo "  systemctl status ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -n 20"
echo ""
echo "수동 1회 (부팅과 동일, k3s restart 없음):"
echo "  sudo RESTART_K3S=false ${INSTALL_PATH}"
