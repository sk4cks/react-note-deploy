# A. 운영 안정화 (EC2 + k3s)

HTTPS·nip.io 적용 후 **안 깨지게** 유지하는 체크리스트.

현재 기준 (서울 `ap-northeast-2`):
- **Elastic IP:** `52.78.20.70`
- **인스턴스:** `note-app-seoul` (Rocky Linux 9, t3.large)
- **SSH:** `ssh -i note_kube.pem rocky@52.78.20.70`
- **HTTPS:** `ingress-https.yaml` + `letsencrypt-prod`
- **ECR:** `019511184889.dkr.ecr.ap-northeast-2.amazonaws.com`
- **IAM instance profile:** `ec2-k3s-ecr-read` (IMDS hop limit 2)
- **GitOps:** Argo CD `note-app` + Jenkins CI (앱 repo → ECR → deploy 태그 bump)

---

## 1. ECR `registries.yaml` 자동 갱신 (cron)

ECR 토큰은 **12시간** 만료 → `ImagePullBackOff` 방지.

### EC2에서 설치 (1회)

```bash
# 맥에서 scripts 복사
scp -i /Users/sk4cks/code/react-note-deploy/note_kube.pem -r \
  /Users/sk4cks/code/react-note-deploy/scripts rocky@52.78.20.70:~

# EC2
cd ~/scripts
chmod +x ecr-registries-renew.sh install-ecr-cron.sh
sudo bash install-ecr-cron.sh
```

즉시 테스트:

```bash
sudo /usr/local/bin/ecr-registries-renew.sh
tail -20 /var/log/k3s-ecr-renew.log
sudo k3s kubectl get pods -n note
```

### 설정 변경

`/etc/default/k3s-ecr-renew`:

```bash
AWS_REGION=ap-northeast-2
ECR_REGISTRY=019511184889.dkr.ecr.ap-northeast-2.amazonaws.com
RESTART_K3S=true   # false면 yaml만 갱신 (k3s는 재시작 안 함)
```

### 부팅 시 자동 갱신 (Stop→Start 후)

cron은 **인스턴스가 꺼져 있으면 실행 안 됨**. 재시작 직후 `ErrImagePull` 방지:

```bash
cd ~/scripts
sudo bash install-k3s-boot-recovery.sh
sudo bash install-ecr-boot-service.sh
systemctl status note-boot-k3s-cleanup note-boot-ecr-renew note-boot-k3s-start k3s
tail -10 /var/log/note-boot-ecr-renew.log
```

부팅 순서: `network` → cleanup → **ECR 토큰 갱신** → `k3s start` (`RESTART_K3S=false`)

구 unit(`k3s-boot-cleanup`, `k3s-ecr-renew-onboot`)·옛 로그 정리:

```bash
sudo bash ~/scripts/cleanup-legacy-boot.sh
```

### cron 확인/제거

```bash
crontab -l
sudo crontab -l   # root cron이면

# 제거 시 install 스크립트가 넣은 줄 삭제
crontab -e
```

> `RESTART_K3S=true`면 6시간마다 **k3s 재시작** (~10–30초 끊김). 학습용 단일 노드면 보통 허용.

---

## 2. Elastic IP 확인

콘솔: **EC2 → 탄력적 IP** → 인스턴스 `note-app-seoul`에 연결됐는지.

```bash
# 퍼블릭 IP (EIP와 동일해야 함)
curl -sf ifconfig.me && echo

# IAM role
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

Ingress host / 프론트 build-arg가 **이 IP**인지:

- `app.52.78.20.70.nip.io`
- `api.52.78.20.70.nip.io`
- `auth.52.78.20.70.nip.io`

---

## 3. HTTPS 인증서 (자동 갱신)

```bash
sudo k3s kubectl get certificate -n note
sudo k3s kubectl describe certificate note-tls -n note
```

- **READY True**, **Renewal Time** 확인
- EC2 **장기 중지** 시 갱신 실패 → 80 포트 열린 상태로 재기동

관련 UI:

- Argo CD: https://argocd.52.78.20.70.nip.io
- Jenkins: https://jenkins.52.78.20.70.nip.io

---

## 4. Postgres 외부 접속 (선택)

클러스터 안: `postgres.note.svc.cluster.local:5432`  
로컬 DBeaver: `52.78.20.70:30432` (`postgres-external` NodePort)

보안 그룹에 **30432 → 내 IP만** 허용 (전체 공개 금지).

---

## 5. `react-note-deploy` Git 관리

맥에서 (민감 정보 제외):

```bash
cd /Users/sk4cks/code/react-note-deploy
git status
git add k8s/ scripts/ docs/
git commit -m "docs: Seoul ops baseline"
git push
```

**커밋하지 말 것:** `.env`, Access Key, `.pem`, `*.secret.yaml`

---

## 6. EC2 Stop/Start 후 k3s 자동 복구

**증상:** `systemctl status k3s` → inactive, `containerd-shim remains running after unit stopped`

**수동 복구:**
```bash
sudo systemctl stop k3s
sudo /usr/local/bin/k3s-killall.sh
sudo systemctl start k3s
```

**자동화 (1회 설치):**
```bash
cd ~/scripts
sudo bash install-k3s-boot-recovery.sh
sudo bash install-ecr-boot-service.sh
```

부팅 순서: `network` → `note-boot-k3s-cleanup` → `note-boot-ecr-renew` → `note-boot-k3s-start` → `k3s`

> **주의:** `k3s-killall.sh`는 `systemctl stop k3s*.service` 호출 — 부팅 cleanup 에서 쓰면 k3s start job 취소됨. unit 이름은 `k3s-` 접두사 금지.

```bash
systemctl status note-boot-k3s-cleanup note-boot-ecr-renew note-boot-k3s-start k3s
tail -20 /var/log/note-boot-k3s-cleanup.log
```

## 7. EC2 중지/시작 후 빠른 점검

1. Elastic IP still attached?
2. `systemctl is-active k3s` (자동 복구 설치 시 cleanup 로그 확인)
3. `sudo k3s kubectl get pods -n note`
4. `sudo k3s kubectl get certificate -n note`
5. https://app.52.78.20.70.nip.io

---

## 다음 단계

- **Mailcow 전용 EC2** — `3.39.19.226` / private `172.31.0.203` (상세: `docs/MAILCOW-EC2.md`). Auth `MAILCOW_ENABLED=true`
- **Cloudflare + 도메인** — nip.io 대체
- (완료) Argo CD / Jenkins / 서울 ECR / SNS OAuth redirect
