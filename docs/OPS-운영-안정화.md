# A. 운영 안정화 (EC2 + k3s)

HTTPS·nip.io 적용 후 **안 깨지게** 유지하는 체크리스트.

현재 기준:
- **Elastic IP:** `13.239.220.205`
- **HTTPS:** `ingress-https.yaml` + `letsencrypt-prod`
- **ECR:** `019511184889.dkr.ecr.ap-southeast-2.amazonaws.com`

---

## 1. ECR `registries.yaml` 자동 갱신 (cron)

ECR 토큰은 **12시간** 만료 → `ImagePullBackOff` 방지.

### EC2에서 설치 (1회)

```bash
# 맥에서 scripts 복사
scp -i /Users/sk4cks/code/react-note-deploy/mini_kube.pem -r /Users/sk4cks/code/react-note-deploy/scripts ubuntu@13.239.220.205:~

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
AWS_REGION=ap-southeast-2
ECR_REGISTRY=019511184889.dkr.ecr.ap-southeast-2.amazonaws.com
RESTART_K3S=true   # false면 yaml만 갱신 (k3s는 재시작 안 함)
```

### 부팅 시 자동 갱신 (Stop→Start 후)

cron은 **인스턴스가 꺼져 있으면 실행 안 됨**. 재시작 직후 `ErrImagePull` 방지:

```bash
cd react-note-deploy/scripts
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

콘솔: **EC2 → 탄력적 IP** → 인스턴스 `mini_kube`에 연결됐는지.

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

- `app.13.239.220.205.nip.io`
- `api.13.239.220.205.nip.io`

---

## 3. HTTPS 인증서 (자동 갱신)

```bash
sudo k3s kubectl get certificate -n note
sudo k3s kubectl describe certificate note-tls -n note
```

- **READY True**, **Renewal Time** 확인
- EC2 **장기 중지** 시 갱신 실패 → 80 포트 열린 상태로 재기동

---

## 4. `react-note-deploy` Git 관리

맥에서 (민감 정보 제외):

```bash
cd /Users/sk4cks/code/react-note-deploy
git status
git add k8s/ scripts/ docs/
git commit -m "Add HTTPS manifests, ECR cron scripts, ops docs"
git push
```

**커밋하지 말 것:** `.env`, Access Key, `.pem`

원격 repo 없으면 GitHub에 `react-note-deploy` 생성 후:

```bash
git remote add origin https://github.com/YOUR_USER/react-note-deploy.git
git push -u origin main
```

---

## 5. EC2 Stop/Start 후 k3s 자동 복구

**증상:** `systemctl status k3s` → inactive, `containerd-shim remains running after unit stopped`

**수동 복구:**
```bash
sudo systemctl stop k3s
sudo /usr/local/bin/k3s-killall.sh
sudo systemctl start k3s
```

**자동화 (1회 설치):**
```bash
cd react-note-deploy/scripts
sudo bash install-k3s-boot-recovery.sh
sudo bash install-ecr-boot-service.sh
```

부팅 순서: `network` → `note-boot-k3s-cleanup` (orphan만, systemctl stop k3s 없음) → `note-boot-ecr-renew` → `note-boot-k3s-start` → `k3s`

> **주의:** `k3s-killall.sh`는 `systemctl stop k3s*.service` 호출 — 부팅 cleanup 에서 쓰면 k3s start job 취소됨. unit 이름은 `k3s-` 접두사 금지.

```bash
systemctl status note-boot-k3s-cleanup note-boot-ecr-renew note-boot-k3s-start k3s
tail -20 /var/log/note-boot-k3s-cleanup.log
```

## 6. EC2 중지/시작 후 빠른 점검

1. Elastic IP still attached?
2. `systemctl is-active k3s` (자동 복구 설치 시 cleanup 로그 확인)
3. `sudo k3s kubectl get pods -n note`
4. `sudo k3s kubectl get certificate -n note`
5. https://app.13.239.220.205.nip.io

---

## 다음 단계 (이후)

- **Argo CD** — Git push → 자동 sync
- **Jenkins** — build → ECR push
- **Cloudflare + 도메인** — nip.io 대체
- **SNS OAuth**
