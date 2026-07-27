# Mailcow — 전용 EC2 (서울)

## 목표
- Auth 가입 시 Mailcow에 `userId@note.local` 메일함 생성
- BFF `app.mail.provider=imap` → Auth mailbox 자격 → IMAP

## 현재 상태 (서울)
| 역할 | 인스턴스 | EIP | Private |
|------|----------|-----|---------|
| 앱 (k3s) | `note-app-seoul` | `52.78.20.70` | `172.31.5.171` |
| Mailcow | `note-mailcow` (EIP `note_mail_ip`) | `3.39.19.226` | `172.31.0.203` |

- SSH: `ssh -i note_kube.pem rocky@3.39.19.226`
- Compose: `~/apps/mailcow-dockerized` — `HTTP 8080` / `HTTPS 8443`
- 도메인: `note.local` (공개 MX 없음)
- Auth: `MAILCOW_ENABLED=true` → `https://172.31.0.203:8443`

## 아키텍처
```
SPA → BFF Pod → Auth Pod → Mailcow API (:8443)
                 BFF Pod → Mailcow IMAP (:993)
```

## SG (`note_mail`)
- SSH 22 → 내 IP
- 8443 / 993 (/ 587) → `note-app-sg`
- 공개 MX 전: **25 열지 않음**

## 호스트 설정 요약
- Rocky 9, Docker CE, swap 2G
- `SKIP_LETS_ENCRYPT=y`, `SKIP_CLAMD=y`, `SKIP_FTS=y`
- API key: 호스트 `~/mailcow-api-key.env` (클러스터 Secret `auth-server-mail`에도 반영)
- `API allow_from`: VPC `172.31.0.0/16`, k3s `10.42.0.0/16`, Docker `172.16.0.0/12`

## Auth / BFF
```bash
# Secret (gitignore) — MAILCOW_API_KEY 갱신 후
kubectl -n note create secret generic auth-server-mail \
  --from-literal=MAILBOX_PASSWORD_SECRET=... \
  --from-literal=MAILBOX_PASSWORD_SALT=... \
  --from-literal=MAILCOW_API_KEY=... \
  --dry-run=client -o yaml | kubectl apply -f -

# auth-server.yaml 이미 enable + private IP
# BFF ConfigMap: MAIL_PROVIDER=imap
```

## 검증
```bash
curl -sk -X POST https://api.52.78.20.70.nip.io/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"userId":"mailtest1","password":"Abcd1234!"}'
# login → Bearer → GET /api/mail/messages
```

강한 비밀번호 사용 (Mailcow는 약한 비번 거부 가능).

## 관리 UI
브라우저에서 보려면 SG에 **8443 → 내 IP** 추가 후:
`https://3.39.19.226:8443` (self-signed)  
기본 admin 비밀번호는 Mailcow 설치 직후 UI에서 변경.

## 비범위 (도메인 구매 후)
공개 MX / SPF / DKIM / DMARC / PTR / 포트 25·465.
