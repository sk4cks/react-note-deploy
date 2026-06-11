#!/usr/bin/env bash
# EC2에서 Argo CD port-forward를 systemd로 상시 실행 (터미널 불필요)
# 기본: 0.0.0.0:8300 → argocd-server:443
set -euo pipefail

PORT="${PORT:-8300}"
SERVICE_NAME="argocd-k3s-portforward"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "sudo 로 실행: sudo bash $0"
  exit 1
fi

K3S_BIN="$(command -v k3s || echo /usr/local/bin/k3s)"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Argo CD port-forward (k3s) on port ${PORT}
After=network.target k3s.service
Wants=k3s.service

[Service]
Type=simple
ExecStart=${K3S_BIN} kubectl port-forward svc/argocd-server -n argocd ${PORT}:443 --address 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"
systemctl status "${SERVICE_NAME}" --no-pager

echo ""
echo "접속 (보안그룹에 TCP ${PORT} 인바운드 추가):"
echo "  https://$(curl -sf ifconfig.me 2>/dev/null || echo YOUR_EIP):${PORT}"
echo "  (Argo 자체 인증서 경고 → 계속 진행)"
