#!/usr/bin/env bash
# EC2 부팅 시 k3s 시작 전 shim/잔여 프로세스 정리 (Stop→Start 복구 자동화)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/k3s-boot-cleanup.sh"
# k3s-killall은 /etc/systemd/system/k3s*.service 를 전부 stop → 이름을 k3s- 로 시작하면 안 됨
SERVICE_NAME="note-boot-k3s-cleanup"
LEGACY_SERVICE="k3s-boot-cleanup"
LOG_PATH="/var/log/note-boot-k3s-cleanup.log"
LEGACY_LOG="/var/log/k3s-boot-cleanup.log"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

install -m 755 "$SCRIPT_DIR/k3s-boot-cleanup.sh" "$INSTALL_PATH"

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

if [[ -f "$LEGACY_LOG" && ! -f "$LOG_PATH" ]]; then
  cp -a "$LEGACY_LOG" "$LOG_PATH"
fi

systemctl disable --now "${LEGACY_SERVICE}.service" 2>/dev/null || true
rm -f "/etc/systemd/system/${LEGACY_SERVICE}.service"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Clean orphaned k3s/containerd processes before k3s start (EC2 Stop/Start recovery)
After=network-online.target
Before=k3s.service note-boot-ecr-renew.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH}
StandardOutput=append:${LOG_PATH}
StandardError=append:${LOG_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"

# 구 ECR 부팅 unit 정리 (k3s-killall 대상이었음)
systemctl disable --now k3s-ecr-renew-onboot.service 2>/dev/null || true
rm -f /etc/systemd/system/k3s-ecr-renew-onboot.service

echo "설치 완료: ${SERVICE_NAME}.service"
echo "  부팅 순서: network → k3s cleanup → ECR 갱신 → k3s 시작"
echo "  로그: ${LOG_PATH}"
echo ""
echo "상태 확인:"
echo "  systemctl status ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -n 20"
echo ""
echo "수동 1회 (부팅과 동일):"
echo "  sudo ${INSTALL_PATH}"
