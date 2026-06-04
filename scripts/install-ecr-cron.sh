#!/usr/bin/env bash
# EC2에서 1회 실행: ECR 갱신 스크립트 + cron 등록
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/ecr-registries-renew.sh"
CONFIG_PATH="/etc/default/k3s-ecr-renew"
LOG_PATH="/var/log/k3s-ecr-renew.log"

# 기본값 (필요 시 여기 수정)
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECR_REGISTRY="${ECR_REGISTRY:-019511184889.dkr.ecr.ap-southeast-2.amazonaws.com}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행하세요: sudo bash $0"
  exit 1
fi

install -m 755 "$SCRIPT_DIR/ecr-registries-renew.sh" "$INSTALL_PATH"

cat >"$CONFIG_PATH" <<EOF
AWS_REGION=${AWS_REGION}
ECR_REGISTRY=${ECR_REGISTRY}
RESTART_K3S=true
EOF
chmod 644 "$CONFIG_PATH"

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

CRON_LINE="0 */6 * * * $INSTALL_PATH >> $LOG_PATH 2>&1"
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" || true; echo "$CRON_LINE") | crontab -

echo "설치 완료"
echo "  스크립트: $INSTALL_PATH"
echo "  설정:     $CONFIG_PATH"
echo "  로그:     $LOG_PATH"
echo "  cron:     6시간마다 (0 */6 * * *)"
echo ""
echo "즉시 1회 실행:"
echo "  $INSTALL_PATH"
echo ""
crontab -l | grep ecr-registries || true
