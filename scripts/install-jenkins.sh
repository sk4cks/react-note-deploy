#!/usr/bin/env bash
# EC2: Jenkins namespace + Deployment + Ingress apply
set -euo pipefail

if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  REAL_HOME="${HOME}"
fi

JENKINS_K8S="${JENKINS_K8S:-${REAL_HOME}/jenkins/k8s}"

if [[ ! -f "${JENKINS_K8S}/jenkins.yaml" ]]; then
  echo "Missing ${JENKINS_K8S}/jenkins.yaml" >&2
  exit 1
fi

if [[ ! -S /var/run/docker.sock ]]; then
  echo "WARN: /var/run/docker.sock 없음. 먼저: sudo bash ~/scripts/install-docker-ec2.sh" >&2
fi

sudo k3s kubectl apply -f "${JENKINS_K8S}/namespace.yaml"
sudo k3s kubectl apply -f "${JENKINS_K8S}/jenkins.yaml"

echo "Waiting for jenkins pod..."
sudo k3s kubectl rollout status deployment/jenkins -n jenkins --timeout=300s

echo ""
sudo k3s kubectl get pods,svc,ingress -n jenkins
echo ""
echo "초기 admin 비밀번호:"
echo "  sudo k3s kubectl exec -n jenkins deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
echo "UI: https://jenkins.13.239.220.205.nip.io"
