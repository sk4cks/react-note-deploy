# react-note-deploy (GitOps / EC2·k3s)

**배포 전용 repo** — 애플리케이션 소스는 아래 repo에 있습니다.


| Repo                        | 경로                                               | 역할                                             |
| --------------------------- | ------------------------------------------------ | ---------------------------------------------- |
| react-note                  | `/Users/sk4cks/code/react-note`                  | 프론트 (+ `Dockerfile`)                           |
| react-note-api              | `/Users/sk4cks/code/react-note-api`              | API (+ `Dockerfile`)                           |
| spring-authorization-server | `/Users/sk4cks/code/spring-authorization-server` | Auth Server (+ `Dockerfile`)                   |
| **react-note-deploy**       | 이 repo                                           | k8s manifest, Argo CD, Jenkins 예시, EC2/k3s 가이드 |


## 디렉터리

```
react-note-deploy/
├── k8s/              # kubectl / Argo CD가 apply
├── argocd/
├── jenkins/          # Jenkinsfile 예시
├── scripts/          # install-k3s.sh, ecr-registries-renew.sh, install-ecr-cron.sh
├── docs/             # HTTPS, OPS 가이드
└── README.md
```

## EC2 1대 + k3s 학습 로드맵

### 목표 아키텍처

```
Route53 (app / api / auth)
    → Ingress (k3s, HTTPS)
        → react-note / react-note-api / auth-server
Jenkins → ECR → 이 repo(k8s) 갱신 → Argo CD sync
```

### EC2 스펙 (권장)

- **t3.large** (8GB), Ubuntu 22.04
- 보안그룹: 22, 80, 443

### Phase 0 — AWS 준비

- EC2, ECR 3개, 도메인
- 이 repo를 GitHub에 push (`react-note-deploy`)

### Phase 1 — Docker (각 **소스 repo**에서 빌드)

```bash
export ECR=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com

cd /Users/sk4cks/code/react-note
docker build --build-arg VITE_BASE_API_URL=https://api.YOUR_DOMAIN -t $ECR/react-note:latest .

cd /Users/sk4cks/code/react-note-api
docker build -t $ECR/react-note-api:latest .

cd /Users/sk4cks/code/spring-authorization-server
docker build -t $ECR/auth-server:latest .

docker push ...
```

### Phase 2 — k3s

`scripts/install-k3s.sh`

### Phase 3 — 배포

- `k8s/` 내 `YOUR_DOMAIN`, `YOUR_ECR` 교체
- `kubectl apply -f k8s/`

### Phase 4 — Argo CD

`argocd/application.yaml` — `repoURL`을 이 repo로 설정

### Phase 5 — Jenkins

`jenkins/Jenkinsfile.api.example` 참고 (api repo에서 실행)

## OAuth (프로덕션 URL)


| 설정                                   | 예시                                                       |
| ------------------------------------ | -------------------------------------------------------- |
| 프론트 build-arg `VITE_BASE_API_URL`       | `https://api.YOUR_DOMAIN` |
| API ConfigMap `AUTH_SERVER_BASE_URL` | `http://auth-server.note.svc.cluster.local:9000/authorization-api` |
| API ConfigMap `AUTH_SERVER_PUBLIC_URL` | `https://auth.YOUR_DOMAIN/authorization-api` |
| Auth issuer                             | `https://auth.YOUR_DOMAIN` |
| redirect                             | `https://app.YOUR_DOMAIN/oauth/callback`                 |


## HTTPS + 운영 (적용 완료 시)

- HTTPS: `docs/HTTPS-nipio-elasticip.md`, `k8s/ingress-https.yaml`
- 운영 안정화: `docs/OPS-운영-안정화.md` (ECR cron, Elastic IP, git)

## 로컬 개발

localhost:8080 / 8082 / 9000 — 소스 repo README·`.env` 참고. **이 repo는 EC2/k3s 때만 사용.**