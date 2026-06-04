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
scp -i mini_kube.pem -r /Users/sk4cks/code/react-note-deploy/scripts ubuntu@13.239.220.205:~

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

## 5. EC2 중지/시작 후 빠른 점검

1. Elastic IP still attached?
2. `sudo /usr/local/bin/ecr-registries-renew.sh`
3. `sudo k3s kubectl get pods -n note`
4. `sudo k3s kubectl get certificate -n note`
5. https://app.13.239.220.205.nip.io

---

## 다음 단계 (이후)

- **Argo CD** — Git push → 자동 sync
- **Jenkins** — build → ECR push
- **Cloudflare + 도메인** — nip.io 대체
- **SNS OAuth**
