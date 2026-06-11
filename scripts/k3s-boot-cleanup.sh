#!/usr/bin/env bash
# EC2 Stop→Start 후 k3s 시작 전 containerd-shim / 잔여 프로세스 정리
# 수동 복구와 동일: k3s-killall → (다음 unit에서) k3s start
set -euo pipefail

LOG_PATH="${LOG_PATH:-/var/log/k3s-boot-cleanup.log}"
K3S_KILLALL="/usr/local/bin/k3s-killall.sh"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_PATH"; }

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

if [[ ! -x "$K3S_KILLALL" ]]; then
  log "SKIP: $K3S_KILLALL 없음 (k3s 미설치)"
  exit 0
fi

if systemctl is-active --quiet k3s 2>/dev/null; then
  log "k3s 이미 active — cleanup 생략"
  exit 0
fi

orphan_shim=false
if pgrep -f containerd-shim >/dev/null 2>&1; then
  orphan_shim=true
fi

orphan_k3s=false
if pgrep -x k3s >/dev/null 2>&1 || pgrep -f '/usr/local/bin/k3s' >/dev/null 2>&1; then
  orphan_k3s=true
fi

if [[ "$orphan_shim" == true || "$orphan_k3s" == true ]]; then
  log "잔여 프로세스 감지 (shim=$orphan_shim k3s=$orphan_k3s) — k3s-killall 실행"
else
  log "잔여 프로세스 없음 — 예방적 k3s-killall 실행 (Stop/Start 후 stale mount/iptables 정리)"
fi

if ! "$K3S_KILLALL" >>"$LOG_PATH" 2>&1; then
  log "WARN: k3s-killall non-zero exit (무시하고 k3s 시작 진행)"
fi

log "cleanup 완료"
