#!/usr/bin/env bash
# 구 k3s 부팅/ECR unit·로그·cron 정리 (note-boot-* 체인 도입 후 1회)
set -euo pipefail

INSTALL_PATH="/usr/local/bin/ecr-registries-renew.sh"
LOG_PATH="/var/log/k3s-ecr-renew.log"

LEGACY_UNITS=(
  k3s-boot-cleanup
  k3s-ecr-renew-onboot
  argocd-k3s-portforward
)

LEGACY_LOGS=(
  /var/log/k3s-boot-cleanup.log
  /var/log/k3s-ecr-renew-onboot.log
)

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

for unit in "${LEGACY_UNITS[@]}"; do
  if systemctl list-unit-files "${unit}.service" &>/dev/null; then
    systemctl disable --now "${unit}.service" 2>/dev/null || true
  fi
  rm -f "/etc/systemd/system/${unit}.service"
done

for logfile in "${LEGACY_LOGS[@]}"; do
  rm -f "$logfile"
done

if [[ -x "$INSTALL_PATH" ]]; then
  CRON_LINE="0 */6 * * * RESTART_K3S=true $INSTALL_PATH >> $LOG_PATH 2>&1"
  (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" || true; echo "$CRON_LINE") | crontab -
fi

systemctl daemon-reload

echo "legacy 정리 완료"
echo "  제거 unit: ${LEGACY_UNITS[*]}"
echo "  제거 log:  ${LEGACY_LOGS[*]}"
echo "  cron:      $(crontab -l 2>/dev/null | grep ecr-registries || echo '(없음)')"
