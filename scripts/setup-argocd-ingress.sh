#!/usr/bin/env bash
# EC2: Argo CD Ingress (nip.io + letsencrypt-prod)
set -euo pipefail

if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  REAL_HOME="${HOME}"
fi

ARGOCD_DIR="${ARGOCD_DIR:-${REAL_HOME}/argocd}"
INGRESS_FILE="${ARGOCD_DIR}/argocd-ingress.yaml"

if [[ ! -f "${INGRESS_FILE}" ]]; then
  echo "Missing ${INGRESS_FILE}" >&2
  echo "Copy argocd/ to ${REAL_HOME}/argocd (or set ARGOCD_DIR=...)" >&2
  exit 1
fi

sudo k3s kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
  -p '{"data":{"server.insecure":"true"}}'

sudo k3s kubectl apply -f "${INGRESS_FILE}"
sudo k3s kubectl rollout restart deployment argocd-server -n argocd

echo "Waiting for argocd-server..."
sudo k3s kubectl rollout status deployment argocd-server -n argocd --timeout=120s

echo ""
echo "Certificate:"
sudo k3s kubectl get certificate -n argocd

echo ""
echo "Open: https://argocd.52.78.20.70.nip.io"
echo "(admin + initial password from argocd-initial-admin-secret)"
