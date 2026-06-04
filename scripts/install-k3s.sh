#!/usr/bin/env bash
set -euo pipefail

# Ubuntu EC2에서 k3s 설치 (single-node)
curl -sfL https://get.k3s.io | sh -

echo "Waiting for node Ready..."
sudo kubectl wait --for=condition=Ready node --all --timeout=120s

sudo kubectl get nodes
echo "kubeconfig: sudo cat /etc/rancher/k3s/k3s.yaml"
