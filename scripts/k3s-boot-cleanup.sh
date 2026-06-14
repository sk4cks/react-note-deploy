#!/usr/bin/env bash
# EC2 Stop→Start 후 k3s 시작 전 orphan 프로세스 정리
# k3s-killall.sh 는 systemctl stop k3s*.service 를 호출 → 부팅 시 예약된 k3s start job 이 취소됨
# 부팅 cleanup 은 systemd unit 을 건드리지 않고 orphan/shim/mount 만 정리
set -euo pipefail

LOG_PATH="${LOG_PATH:-/var/log/note-boot-k3s-cleanup.log}"
K3S_DATA_DIR="${K3S_DATA_DIR:-/var/lib/rancher/k3s}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_PATH"; }

run_logged() {
  log "+ $*"
  "$@" >>"$LOG_PATH" 2>&1 || true
}

touch "$LOG_PATH"
chmod 644 "$LOG_PATH"

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
  log "잔여 프로세스 감지 (shim=$orphan_shim k3s=$orphan_k3s) — orphan cleanup 실행"
else
  log "잔여 프로세스 없음 — 예방적 orphan cleanup (Stop/Start 후 stale mount/iptables 정리)"
fi

pschildren() {
  ps -e -o ppid= -o pid= | sed -e 's/^\s*//g; s/\s\s*/\t/g;' | grep -w "^$1" | cut -f2
}

pstree_pids() {
  for pid in "$@"; do
    echo "$pid"
    for child in $(pschildren "$pid"); do
      pstree_pids "$child"
    done
  done
}

killtree() {
  local pids
  pids="$(pstree_pids "$@")"
  [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
}

getshims() {
  ps -e -o pid= -o args= | sed -e 's/^ *//; s/\s\s*/\t/;' \
    | grep -w "${K3S_DATA_DIR}"'/data/[^/]*/bin/containerd-shim' | cut -f1
}

remove_interfaces() {
  ip link show 2>/dev/null | grep 'master cni0' | while read -r _ iface _; do
    iface="${iface%%@*}"
    [[ -n "$iface" ]] && ip link delete "$iface" 2>/dev/null || true
  done

  for iface in cni0 flannel.1 flannel-v6.1 kube-ipvs0 flannel-wg flannel-wg-v6; do
    ip link delete "$iface" 2>/dev/null || true
  done
}

do_unmount_and_remove() {
  local prefix="$1"
  while read -r _ path _; do
    case "$path" in "$prefix"*) echo "$path" ;; esac
  done < /proc/self/mounts | sort -r | xargs -r -n 1 sh -c 'umount -f "$0" 2>/dev/null && rm -rf "$0"' || true
}

shim_pids="$(getshims || true)"
if [[ -n "$shim_pids" ]]; then
  log "containerd-shim 정리: $(echo "$shim_pids" | tr '\n' ' ')"
  killtree $shim_pids
fi

for pid in $(pgrep -x k3s 2>/dev/null || true); do
  log "k3s orphan pid=$pid 종료"
  killtree "$pid"
done

run_logged do_unmount_and_remove '/run/k3s'
run_logged do_unmount_and_remove '/var/lib/kubelet/pods'
run_logged do_unmount_and_remove '/var/lib/kubelet/plugins'
run_logged do_unmount_and_remove '/run/netns/cni-'

if ip netns show 2>/dev/null | grep -q cni-; then
  run_logged sh -c 'ip netns show 2>/dev/null | grep cni- | xargs -r -n 1 ip netns delete'
fi

run_logged remove_interfaces
run_logged rm -rf /var/lib/cni/

if command -v iptables-save >/dev/null 2>&1 && command -v iptables-restore >/dev/null 2>&1; then
  run_logged sh -c 'iptables-save | grep -v KUBE- | grep -v CNI- | grep -iv flannel | iptables-restore'
fi
if command -v ip6tables-save >/dev/null 2>&1 && command -v ip6tables-restore >/dev/null 2>&1; then
  run_logged sh -c 'ip6tables-save | grep -v KUBE- | grep -v CNI- | grep -iv flannel | ip6tables-restore'
fi

log "cleanup 완료 (systemd k3s unit 미변경)"
