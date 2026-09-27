# EKS Pod ENI (Security Groups for Pods)

## Layout

이 프로젝트는 두 가지 구조로 제공됩니다.

### 1. 분리 구조 (`aws/` + `kubernetes/`)

EKS 쿠버네티스 API 서버와 통신이 필요한 리소스만 별도 레이어로 분리되어 있습니다 (rules.md #29). 이렇게 나누면 각 레이어의 `terraform apply`/`terraform destroy`가 단일 명령으로 안전하게 끝납니다 — 클러스터를 만들고 지우는 작업과, 그 클러스터의 API 서버에 접속해야 하는 작업이 같은 state 안에서 뒤섞이지 않기 때문입니다.

- `aws/` — VPC, EKS 클러스터, 관리형 노드그룹, vpc-cni/coredns/kube-proxy 애드온, pod 보안그룹(`aws_security_group`), VS Code/web EC2. **API 서버와 통신하는 리소스가 전혀 없습니다** (`kubectl`/`kubernetes`/`helm` 프로바이더를 쓰지 않음).
- `kubernetes/` — `aws`가 만든 EKS 클러스터의 API 서버에 `SecurityGroupPolicy` CRD와 데모 파드를 배포합니다 (`alekc/kubectl`의 `kubectl_manifest`). `aws`의 state를 `terraform_remote_state`로 읽어 클러스터 접속 정보와 보안그룹 ID를 가져옵니다.

```sh
# 1) 인프라(클러스터 포함) 생성
cd aws
terraform init
terraform apply

# 2) 클러스터 API 서버에 SecurityGroupPolicy/데모 파드 배포
cd ../kubernetes
terraform init
terraform apply
```

삭제는 반드시 반대 순서로 진행합니다 (클러스터가 아직 살아있는 상태에서 `kubernetes` 레이어를 먼저 지워야 kubectl provider가 정상적으로 접속할 수 있습니다):

```sh
cd kubernetes
terraform destroy

cd ../aws
terraform destroy
```

`aws`의 EKS API 서버 퍼블릭 엔드포인트는 `kubernetes` 레이어의 `kubectl` provider가 클러스터 밖(이 명령을 실행하는 머신)에서 접속해야 하므로 기본적으로 켜져 있습니다 (`endpoint_public_access = true`). `public_access_cidrs`를 현재 IP의 `/32`로 좁혀서 사용하세요.

### 2. 단일 루트 모듈 구조 (`single/`)

`aws/`와 `kubernetes/`를 레이어로 나누기 전의 원래 구조입니다. 하나의 root module에서 EKS 클러스터와 `SecurityGroupPolicy` CRD를 함께 `apply`합니다. `pod_security_group`(순수 AWS)과 CRD 매니페스트가 `pod_security_group_policy` 모듈 하나에 합쳐져 있고, `kubectl` provider는 `lazy_load = true`로 설정되어 있습니다.

```sh
cd single
terraform init
terraform apply
```

이 구조는 `terraform destroy` 시 클러스터와 CRD 매니페스트가 같은 작업에서 함께 파괴되므로, provider 설정값이 unknown/null이 되어 실패할 수 있습니다 (rules.md #29 참고). 안전한 apply/destroy가 필요하면 `aws/` + `kubernetes/` 분리 구조를 사용하세요.
