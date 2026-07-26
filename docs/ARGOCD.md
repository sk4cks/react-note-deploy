# Argo CD (GitOps) — EC2 k3s

`react-note-deploy` Git push → Argo CD가 `k8s/` 자동 반영.

**전제:** GitHub `https://github.com/sk4cks/react-note-deploy` (public 또는 Argo에 repo 권한)

---

## 1. Argo CD 설치 (EC2)

```bash
sudo k3s kubectl create namespace argocd
sudo k3s kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

sudo k3s kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
sudo k3s kubectl get pods -n argocd
```

---

## 2. 초기 admin 비밀번호

```bash
# 임시 비밀번호 (pod Ready 후)
sudo k3s kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

사용자: **admin**

---

## 3. UI 접속

**운영 (Ingress, 권장)**

```bash
sudo bash ~/scripts/setup-argocd-ingress.sh
```

- `https://argocd.52.78.20.70.nip.io`
- 보안 그룹 **80/443**만 열면 됨
- `server.insecure=true` + Ingress TLS 종료 (backend **port 80**)

인증서: `kubectl get certificate -n argocd` → `argocd-tls` READY

**로컬 디버그 (SSH 터널, 일시적)**

```bash
ssh -i /Users/sk4cks/code/react-note-deploy/note_kube.pem -L 8300:localhost:8300 rocky@52.78.20.70
# EC2 SSH 세션 안
sudo k3s kubectl port-forward svc/argocd-server -n argocd 8300:443 --address 127.0.0.1
```

맥 브라우저: **https://localhost:8300**

---

## 4. Application 등록

`argocd/application.yaml` 의 `repoURL` 이 본인 GitHub와 일치하는지 확인 후:

```bash
# repo와 동일하게 EC2에 ~/argocd/ 로 복사 (application + ingress manifest)
scp -i /Users/sk4cks/code/react-note-deploy/note_kube.pem -r \
  /Users/sk4cks/code/react-note-deploy/argocd \
  rocky@52.78.20.70:~

sudo k3s kubectl apply -f /home/rocky/argocd/application.yaml
```

Argo UI에서 **note-app** → Sync → Healthy 확인.

UI (운영): **https://argocd.52.78.20.70.nip.io**

---

## 5. 동작 확인

1. 맥에서 `k8s/` 아무 yaml 주석 한 줄 수정 → commit → push
2. Argo UI **Refresh** 또는 자동 sync (`automated` 설정됨)
3. EC2 `kubectl get pods -n note` 변경 반영 확인

---

## 주의

| 항목 | 설명 |
|------|------|
| **private repo** | Argo CD에 deploy key / token Secret 필요 |
| **기존 kubectl apply** | Argo가 같은 리소스 관리 → 충돌 시 Argo 기준으로 sync |
| **ingress-https.yaml** | Git의 `k8s/` 가 source of truth |

---

## 다음

- Jenkins → ECR push → (선택) image tag bump in git
- Cloudflare 도메인
