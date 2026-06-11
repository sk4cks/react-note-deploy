#!/usr/bin/env bash
# GitOps manifest image 태그 갱신 (Jenkins Update GitOps 단계)
# Usage: bump-gitops-image.sh <manifest-base-name> <ecr-repo-uri> <tag>
# Example: bump-gitops-image.sh react-note-api 019511184889.dkr.ecr.../react-note-api 42
set -euo pipefail

MANIFEST_NAME="${1:?manifest name e.g. react-note-api}"
ECR_URI="${2:?full ecr image repo without tag}"
TAG="${3:?tag e.g. BUILD_NUMBER}"

GITOPS_DIR="${GITOPS_DIR:-.}"
MANIFEST="${GITOPS_DIR}/k8s/${MANIFEST_NAME}.yaml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing $MANIFEST" >&2
  exit 1
fi

cp "$MANIFEST" "${MANIFEST}.bak"
sed -i "s|image: ${ECR_URI}:.*|image: ${ECR_URI}:${TAG}|" "$MANIFEST"
grep "image: ${ECR_URI}" "$MANIFEST"
echo "bumped ${MANIFEST} -> :${TAG}"
