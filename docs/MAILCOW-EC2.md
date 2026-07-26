# Mailcow — 공개 MX 없음 (도메인 미보유)

## 목표
- Auth 가입 시 Mailcow에 `userId@note.local` 메일함 생성
- BFF `app.mail.provider=imap` → Auth mailbox 자격 → IMAP

## 현재 상태 (서울)
- **앱 EC2:** `52.78.20.70` / `note-app-seoul` (k3s만)
- Auth: **`MAILCOW_ENABLED=false`** (메일 서버 미기동)
- 시드니 동일 호스트 Mailcow는 **종료·삭제됨**

## 권장 아키텍처
앱과 Mailcow를 **같은 VPC의 다른 EC2**로 분리 (iptables/netfilter 충돌 회피).

```
SPA → BFF Pod → Auth Pod → Mailcow API (:8443)
                 BFF Pod → Mailcow IMAP (:993)
```

### Mailcow EC2 (예정)
- 리전: `ap-northeast-2`, 서브넷: 앱과 동일 AZ 권장 (`ap-northeast-2a`)
- Compose: `HTTPS 8443` / `HTTP 8080` (앱 Traefik `80`/`443`과 무관)
- SG: 앱 SG → `8443`, `993`, `587` (필요 시 SSH 내 IP만)
- `API_ALLOW_FROM`: VPC/앱 노드 CIDR
- 도메인: UI/API로 `note.local` 추가

### Auth / BFF (Mailcow 기동 후)
```bash
# Secret
kubectl apply -f k8s/auth-server-mail.secret.yaml

# auth-server.yaml
MAILCOW_ENABLED=true
MAILCOW_BASE_URL=https://<mailcow-private-ip>:8443
MAILCOW_IMAP_HOST=<mailcow-private-ip>
MAILCOW_SMTP_HOST=<mailcow-private-ip>
```

BFF ConfigMap: `MAIL_PROVIDER=imap`.

## 검증
```bash
curl -sk -X POST https://api.52.78.20.70.nip.io/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"userId":"mailtest1","password":"Abcd1234!"}'
# login → Bearer → GET /api/mail/messages
```

강한 비밀번호 사용 (Mailcow는 약한 비번 거부 가능).

## 비범위
공개 MX / SPF / DKIM / 외부 송수신.

## (참고) 동일 호스트에 둘 때
k3s + Mailcow를 한 대에 올리면 Mailcow netfilter가 pod→host를 DROP할 수 있음.
가능하면 **전용 EC2 분리**를 우선한다.
