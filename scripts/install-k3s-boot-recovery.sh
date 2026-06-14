#!/usr/bin/env bash
# EC2 부팅 시 k3s 복구 체인 설치: cleanup → ECR → k3s start
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/k3s-boot-cleanup.sh"
CLEANUP_SERVICE="note-boot-k3s-cleanup"
START_SERVICE="note-boot-k3s-start"
LOG_PATH="/var/log/note-boot-k3s-cleanup.log"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

bash "$SCRIPT_DIR/cleanup-legacy-boot.sh"

install -m 755 "$SCRIPT_DIR/k3s-boot-cleanup.sh" "$INSTALL_PATH"

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

cat >/etc/systemd/system/${CLEANUP_SERVICE}.service <<EOF
[Unit]
Description=Clean orphaned k3s/containerd processes before k3s start (EC2 Stop/Start recovery)
After=network-online.target
Before=note-boot-ecr-renew.service ${START_SERVICE}.service
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

cat >/etc/systemd/system/${START_SERVICE}.service <<EOF
[Unit]
Description=Start k3s after boot cleanup and ECR renew
After=network-online.target ${CLEANUP_SERVICE}.service note-boot-ecr-renew.service
Wants=network-online.target note-boot-ecr-renew.service
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl start k3s.service
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl disable k3s.service 2>/dev/null || true

systemctl daemon-reload
systemctl enable "${CLEANUP_SERVICE}.service"
systemctl enable "${START_SERVICE}.service"

echo "설치 완료: ${CLEANUP_SERVICE}.service, ${START_SERVICE}.service"
echo "  부팅 순서: network → cleanup → ECR 갱신 → k3s start"
echo "  k3s.service 는 multi-user 자동 시작 비활성 (note-boot-k3s-start 가 start)"
echo "  로그: ${LOG_PATH}"
echo ""
echo "ECR 부팅 unit 미설치 시:"
echo "  sudo bash ${SCRIPT_DIR}/install-ecr-boot-service.sh"
echo ""
echo "상태 확인:"
echo "  systemctl status ${CLEANUP_SERVICE} note-boot-ecr-renew ${START_SERVICE} k3s"
echo "  tail -20 ${LOG_PATH}"
