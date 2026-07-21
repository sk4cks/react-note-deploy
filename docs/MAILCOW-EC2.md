# EC2 호스트 Mailcow (Docker Compose) — 공개 MX 없음 (도메인 미보유)

## 목표
- Auth 가입 시 Mailcow에 `userId@note.local` 메일함 생성
- BFF `app.mail.provider=imap` → Auth mailbox 자격 → 호스트 IMAP

## 전제
- EC2 EIP: `13.239.220.205`
- Mailcow는 **k8s Pod가 아님** — 호스트 Compose
- Pod → 호스트: 노드 INTERNAL-IP `172.31.3.140` (k3s node)
- API allow: `10.42.0.0/16` (pod), `172.31.0.0/20` (VPC)

## 설치 (EC2)
```bash
cd ~/mailcow-dockerized
# mailcow.conf: MAILCOW_HOSTNAME=mail.13.239.220.205.nip.io
# HTTP_PORT=8080 HTTPS_PORT=8443  (k3s Traefik가 80/443 사용 — 충돌 금지)
# SKIP_CLAMD/OLEFY/SOGO/FTS=y (메모리)
# API_KEY + API_ALLOW_FROM=127.0.0.1,::1,10.42.0.0/16,172.31.0.0/20,172.17.0.0/16,172.22.0.0/16
docker compose up -d
```

도메인 추가 (API):
```bash
API_KEY=$(cat ~/mailcow-api-key.txt)
curl -sk -X POST "https://127.0.0.1:8443/api/v1/add/domain" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"domain":"note.local","description":"note app","aliases":"50","mailboxes":"50","defquota":"3072","maxquota":"10240","quota":"102400","active":"1"}'
```

## k8s
```bash
# Secret (gitignore: *.secret.yaml)
kubectl apply -f k8s/auth-server-mail.secret.yaml
kubectl apply -f k8s/auth-server.yaml
kubectl apply -f k8s/configmap-api.yaml
kubectl apply -f k8s/react-note-api.yaml
kubectl -n note rollout restart deploy/auth-server deploy/react-note-api
```

Auth env: `MAILCOW_ENABLED=true`, `MAILCOW_BASE_URL=https://172.31.3.140:8443`,
`MAILCOW_IMAP_HOST`/`SMTP_HOST=172.31.3.140`, mailbox secret from Secret.

BFF: ConfigMap `MAIL_PROVIDER=imap`.

## 검증
강한 비밀번호로 가입 후:
```bash
curl -sk -X POST https://api.13.239.220.205.nip.io/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"userId":"mailtest1","password":"Abcd1234!"}'
# login → Bearer → GET /api/mail/messages
```

## 비범위
공개 MX / SPF / DKIM / 외부 송수신.
