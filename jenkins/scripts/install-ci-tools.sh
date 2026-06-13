#!/usr/bin/env bash
# Jenkins Pod(root) — docker CLI + AWS CLI v2 (ECR push용)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq docker.io
fi

if ! command -v aws >/dev/null 2>&1; then
  apt-get install -y -qq curl unzip ca-certificates
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

echo "ci-tools: docker=$(command -v docker) aws=$(command -v aws)"
