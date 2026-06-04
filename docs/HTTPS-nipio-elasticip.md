# Elastic IP + nip.io + HTTPS (Let's Encrypt)

도메인 구매 없이 연습하는 경로입니다.

## 사전 조건

- EC2 실행 중, k3s + 앱 Pod Running
- 보안 그룹 **80, 443** 인바운드 열림
- **탄력적 IP** 할당 후 인스턴스에 연결 (중지/시작해도 IP 유지)

## 1. Elastic IP

EC2 → 탄력적 IP → 할당 → `mini_kube`에 연결 → **퍼블릭 IP 메모** (`EIP`)

## 2. manifest IP 맞추기

`k8s/ingress-https.yaml`, `k8s/auth-server.yaml` 등에서 `YOUR_ELASTIC_IP` → 실제 EIP

auth-server issuer:

```yaml
SPRING_SECURITY_OAUTH2_AUTHORIZATIONSERVER_ISSUER: "https://auth.{EIP}.nip.io"
```

## 3. cert-manager 설치 (EC2)

```bash
sudo k3s kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
sudo k3s kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
sudo k3s kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s
```

## 4. ClusterIssuer (이메일 수정 필수)

```bash
# k8s/cluster-issuer-staging.yaml, cluster-issuer-prod.yaml 에서 email 변경 후
sudo k3s kubectl apply -f ~/k8s/cluster-issuer-staging.yaml
```

## 5. HTTPS Ingress

```bash
# ingress-https.yaml IP 치환 후
sudo k3s kubectl apply -f ~/k8s/ingress-https.yaml
sudo k3s kubectl get certificate -n note
sudo k3s kubectl describe certificate note-tls -n note
```

`READY=True` 될 때까지 1~3분.

## 6. 접속 테스트

- https://app.{EIP}.nip.io
- https://api.{EIP}.nip.io

staging 인증서는 브라우저가 "신뢰하지 않음" 경고 — **정상** (연습용).

## 7. Production 인증서 (staging 성공 후)

`cluster-issuer-prod.yaml` email 수정 → apply → staging secret 삭제 → 재발급.

`ingress-https.yaml` 은 `letsencrypt-prod` 사용 (repo 기본값).

## 8. 프론트 재빌드 (HTTPS)

```bash
docker build --platform linux/amd64 \
  --build-arg VITE_BASE_API_URL=https://api.{EIP}.nip.io \
  -t $ECR/react-note:latest .
docker push $ECR/react-note:latest
```

EC2:

```bash
sudo k3s kubectl rollout restart deployment react-note -n note
```

## 트러블슈팅

| 증상 | 확인 |
|------|------|
| Certificate Pending | `kubectl describe challenge -n note` — 80 포트, host nip.io 일치 |
| 404 on acme challenge | Ingress host = `app.{EIP}.nip.io` 정확한지 |
| 사설 IP in host | `172.31.x.x` 사용 금지, **EIP**만 |
