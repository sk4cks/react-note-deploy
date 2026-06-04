# HTTPS (Elastic IP + nip.io + cert-manager)

> Notion「승찬공부 > EC2 연습」하위에 붙여넣기용  
> EIP: `13.239.220.205` · 리전: `ap-southeast-2`

---

## 목표

- 도메인 구매 없이 **HTTPS** 연습
- **Elastic IP** 고정 + **nip.io**
- **cert-manager** + Let's Encrypt (staging → prod)

---

## 접속 URL

| 서비스 | URL |
|--------|-----|
| 프론트 | https://app.13.239.220.205.nip.io |
| API | https://api.13.239.220.205.nip.io |
| Auth | https://auth.13.239.220.205.nip.io/authorization-api |

- `http://` 입력해도 **자동 https** (Ingress TLS + Traefik)
- nip.io host = **퍼블릭 IP만** (`172.31.x.x` 사용 금지)

---

## 사용 파일 (react-note-deploy/k8s)

| 파일 | 역할 |
|------|------|
| `cluster-issuer-staging.yaml` | LE staging (먼저 테스트) |
| `cluster-issuer-prod.yaml` | LE production (브라우저 신뢰) |
| `ingress-https.yaml` | TLS + host 3개 |
| `auth-server.yaml` | issuer `https://auth.13.239.220.205.nip.io` |

**email** — `cluster-issuer-*.yaml`에 본인 메일 필수

---

## 1. cert-manager 설치

```bash
sudo k3s kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
sudo k3s kubectl get pods -n cert-manager
# 3개 Pod 1/1 Running
```

---

## 2. staging 인증서

```bash
sudo k3s kubectl apply -f ~/k8s/cluster-issuer-staging.yaml
sudo k3s kubectl apply -f ~/k8s/ingress-https.yaml
sudo k3s kubectl get certificate -n note -w
# note-tls READY True
```

---

## 3. prod 인증서 전환

```bash
# ingress-https.yaml → letsencrypt-prod
sudo k3s kubectl apply -f ~/k8s/cluster-issuer-prod.yaml
sudo k3s kubectl delete secret note-tls -n note
sudo k3s kubectl delete certificate note-tls -n note
sudo k3s kubectl apply -f ~/k8s/ingress-https.yaml
sudo k3s kubectl get certificate -n note -w
```

---

## 트러블슈팅

### Mixed Content

- `https://app` + 요청 `http://api` → 브라우저 차단
- **해결:** 프론트 재빌드 `VITE_BASE_API_URL=https://api.13.239.220.205.nip.io` + push + rollout restart

### staging — login 실패 (Provisional headers)

- **해결:** 새 탭에서 `https://api.13.239.220.205.nip.io` 열고 인증서 예외 허용 → 로그인 재시도

### 일반 창만「주의 요함」

- 시크릿 OK = prod 인증서 정상
- **해결:** 사이트 데이터 삭제 / 탭 닫고 재접속 (staging 캐시)

### API 확인

```bash
curl -vk -X POST https://api.13.239.220.205.nip.io/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"userId":"admin","password":"1234"}'
```

---

## 인증서 갱신

- Let's Encrypt **90일**, cert-manager **자동 갱신** (수동 불필요)
- EC2 장기 중지 + 80 막히면 갱신 실패 가능
- **ECR registries.yaml** (12h)는 별개 — ImagePullBackOff 시 수동

---

## 관련

- `docs/HTTPS-nipio-elasticip.md`
- Notion: [명령어] EC2·k3s·ECR 배포 치트시트
