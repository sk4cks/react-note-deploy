# Jenkins CI (k3s Pod) — EC2

앱 repo push → Jenkins → ECR → `react-note-deploy` image 태그 → Argo CD sync

**전제:** Argo `note-app`, ECR, HTTPS Ingress, EC2 IAM role

---

## 1. 아키텍처

```
react-note / api / auth-server  (각 repo push)
    → Jenkins job ×3
    → ECR push
    → react-note-deploy k8s/*.yaml 태그 bump + git push
    → Argo note-app sync
```

Jenkins manifest는 **`jenkins/k8s/`** (Argo `path: k8s` 밖)

---

## 2. EC2 — Docker (호스트)

Jenkins Pod가 `docker.sock` 마운트 → **호스트에 Docker CE** 필요.

```bash
# 맥 → EC2 (jenkins → ~/jenkins, scripts → ~/scripts/)
ssh -i /Users/sk4cks/code/react-note-deploy/mini_kube.pem ubuntu@13.239.220.205 'mkdir -p ~/scripts'

scp -i /Users/sk4cks/code/react-note-deploy/mini_kube.pem -r \
  /Users/sk4cks/code/react-note-deploy/jenkins \
  ubuntu@13.239.220.205:~

scp -i /Users/sk4cks/code/react-note-deploy/mini_kube.pem \
  /Users/sk4cks/code/react-note-deploy/scripts/install-docker-ec2.sh \
  /Users/sk4cks/code/react-note-deploy/scripts/install-jenkins.sh \
  ubuntu@13.239.220.205:~/scripts/

sudo bash ~/scripts/install-docker-ec2.sh
docker --version
```

### EC2 IMDS (Jenkins에서 `aws ecr` 용)

Pod가 instance role 쓰려면 메타데이터 hop limit **2**:

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id $(ec2-metadata --instance-id | cut -d' ' -f2) \
  --http-put-response-hop-limit 2 \
  --http-endpoint enabled
```

(또는 Jenkins Credentials에 AWS Access Key 등록)

---

## 3. Jenkins Pod 설치

```bash
# 위에서 jenkins·scripts 복사했다면 EC2에서:
chmod +x ~/scripts/install-docker-ec2.sh ~/scripts/install-jenkins.sh
sudo bash ~/scripts/install-jenkins.sh
```

인증서:

```bash
sudo k3s kubectl get certificate -n jenkins
```

UI: **https://jenkins.13.239.220.205.nip.io**

초기 비밀번호:

```bash
sudo k3s kubectl exec -n jenkins deploy/jenkins -- \
  cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## 4. Jenkins 초기 설정

1. **Install suggested plugins**
2. **Credentials** → `github-gitops`
   - Kind: Username with password **또는** SSH key
   - GitHub PAT (`repo` scope) — `react-note-deploy` push용
3. **Manage Jenkins → Tools**
   - JDK 17 (이미 이미지에 포함)
4. **New Item ×3** — Pipeline, 이름 예: `react-note-ci`, `react-note-api-ci`, `auth-server-ci`
5. **Pipeline** → Definition: **Pipeline script from SCM**
   - 각 **앱 repo** Git URL, branch `main`, Script Path `Jenkinsfile`

각 앱 repo 루트에 Jenkinsfile 복사:

| repo | deploy repo의 파일 |
|------|-------------------|
| react-note | `jenkins/Jenkinsfile.react-note` → `Jenkinsfile` |
| react-note-api | `jenkins/Jenkinsfile.api` |
| spring-authorization-server | `jenkins/Jenkinsfile.auth-server` |

6. **Build Triggers** — GitHub hook (webhook) 또는 **Poll SCM** `H/5 * * * *`

---

## 5. 동작 확인

1. 앱 repo에 commit → push
2. Jenkins job **Success**
3. GitHub `react-note-deploy` — `k8s/*.yaml` image 태그 `:BUILD_NUMBER` 변경
4. Argo **note-app** Sync → Pod 재시작
5. `sudo k3s kubectl get pods -n note`

---

## 6. 트러블슈팅

| 증상 | 확인 |
|------|------|
| docker: not found | Pod privileged + docker.sock, 호스트 `install-docker-ec2.sh` |
| aws: Unable to locate credentials | IMDS hop limit 2 또는 Jenkins AWS credential |
| git push failed | `github-gitops` credential, PAT `repo` 권한 |
| ImagePullBackOff | ECR cron / boot service (기존 OPS 문서) |

---

## 7. GitHub Webhook (push 즉시 빌드)

Poll SCM(`H/5`) 대신 **push → 곧바로 빌드**.

### 7-1. Jenkins 플러그인

**Manage Jenkins → Plugins** 에서 설치·활성:

- **GitHub Integration** (또는 `github` / GitHub plugin)

Suggested plugins 설치했다면 보통 이미 있음.

### 7-2. Jenkins URL

**Manage Jenkins → System → Jenkins URL**

```text
https://jenkins.13.239.220.205.nip.io
```

Save.

### 7-3. Job 3개 — Trigger 설정

각 Job (`react-note-ci`, `react-note-api-ci`, `auth-server-ci`):

| 켜기 | 끄기 |
|------|------|
| ✅ **GitHub hook trigger for GITScm polling** | ❌ Poll SCM (스케줄 비우기) |

(선택) **GitHub project** 에 해당 repo URL 넣기 — 예: `https://github.com/sk4cks/react-note/`

### 7-4. GitHub — repo마다 Webhook 1개 (총 3개)

각 repo → **Settings → Webhooks → Add webhook**

| 항목 | 값 |
|------|-----|
| **Payload URL** | `https://jenkins.13.239.220.205.nip.io/github-webhook/` |
| **Content type** | `application/json` |
| **Which events** | **Just the push event** |
| **Active** | ✅ |

repo별로 동일 URL, **repo 3개 = webhook 3개** 등록:

- `sk4cks/react-note`
- `sk4cks/react-note-api`
- `sk4cks/spring-authorization-server`

`react-note-deploy` 는 Jenkins Job SCM이 아니므로 webhook **불필요**.

### 7-5. 동작 원리

```text
git push → GitHub가 Jenkins /github-webhook/ POST
       → Jenkins가 해당 repo를 쓰는 Job만 곧바로 SCM 체크 → 빌드 시작
```

Poll SCM과 달리 **5분 대기 없음** (네트워크·큐에 따라 수초~1분).

### 7-6. 테스트

1. Webhook 페이지 **Recent Deliveries** → **Redeliver** → Response **200**
2. 앱 repo에 빈 commit push
3. Jenkins **Build History** 에 새 빌드 바로 생기는지 확인

### 7-7. 트러블슈팅

| 증상 | 해결 |
|------|------|
| Webhook **403/302** | Jenkins URL이 `https://jenkins....nip.io` 인지, Ingress 443 열림 |
| **200인데 빌드 안 됨** | Job에 **GitHub hook trigger** 켰는지, SCM URL이 push한 repo와 일치하는지 |
| **SSL** | nip.io + Let's Encrypt 정상(브라우저로 Jenkins 접속 되면 OK) |
| 여전히 느림 | Poll SCM 스케줄이 남아 있으면 제거 |

---

## 8. 디스크 — 빌드 이력 최신 1개만

Job **Configure → 오래된 빌드 삭제(Discard old builds)**:

| 항목 | 값 |
|------|-----|
| Max # of builds to keep | **1** |
| Max # of builds to keep with artifacts | **1** (선택) |

또는 Jenkinsfile (3 repo에 반영됨):

```groovy
options {
  buildDiscarder(logRotator(numToKeepStr: '1', artifactNumToKeepStr: '1'))
}
```

**이미 쌓인 빌드**는 다음 빌드 성공 후 정리되거나, Job → **Workspace / 빌드 기록**에서 수동 삭제.

**호스트 Docker** 용량 (EC2):

```bash
docker system df
sudo docker system prune -af   # 사용 안 하는 이미지·캐시 삭제 (주의: 다른 이미지도 지워짐)
```

---

## 9. 다음

- 멀티브랜치 Pipeline
- Jenkins Configuration as Code
- Java 21 이미지
