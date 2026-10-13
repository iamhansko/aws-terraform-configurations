---
inclusion: always
---

# EC2 Workbench and Output Delivery Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-aws-load-balancer-controller.md`](rules-aws-load-balancer-controller.md) · **Next:** [`rules-multi-account-and-region.md`](rules-multi-account-and-region.md)
> 논리 인용 `rules.md H-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| H-1 | 한 루트에 EKS 클러스터와 `module "vscode_ec2"`가 함께 있음 | code-server, kubectl, eksctl, helm, docker를 모두 설치; runner는 API에 못 닿지만 VPC 작업대는 도달하는 E-9 분기에서만 SSM으로 클러스터 리소스를 생성 | B-4·C-1·E-1·E-9 |
| H-2 | 루트에 `module "vscode_ec2"`가 있음 | README-safe output 표현을 `local.outputs`와 인스턴스 README에 함께 투영; 실제 민감값 output은 명시적 allowlist 예외 | B-5·D-5·I-4 |

## H. EC2 작업대와 산출물 전달

H-1은 EKS 클러스터와 `vscode_ec2`가 함께 있는 루트에, H-2는 EKS 유무와 관계없이 `vscode_ec2`가 있는 모든 루트에 적용됩니다.

### H-1. EKS 클러스터와 `vscode_ec2`가 같은 루트 모듈에 함께 선언되면 code-server, kubectl, eksctl, helm, docker를 **모두** 설치한다

한 디렉토리(루트 모듈)에 EKS 클러스터(`module "eks_cluster"` 또는 `aws_eks_cluster`)와 `module "vscode_ec2"`가 함께 있으면, 그 인스턴스는 클러스터를 다루는 작업대입니다. 다섯 가지가 하나도 빠짐없이 설치되어 있어야 합니다.

| 도구 | 설치 주체 | 왜 필요한가 |
| --- | --- | --- |
| code-server | `vscode_ec2` 모듈 | 이 인스턴스의 존재 이유. 브라우저에서 `/home/ec2-user`를 연다 |
| kubectl | 루트의 `additional_user_data` | 클러스터 상태 조사 (`get`/`describe`/`logs`) |
| eksctl | 루트의 `additional_user_data` | 클러스터·노드그룹·IRSA를 CLI로 조회/임시 조작 |
| helm | 루트의 `additional_user_data` | 릴리스 진단 (`helm list`, `helm history` — E-7번 패턴의 원인 규명이 이 명령으로 이뤄진다) |
| docker | 루트의 `additional_user_data` | 이미지 빌드/ECR 푸시처럼 **데몬이 반드시 필요해서** 프로바이더 리소스로 대체할 수 없는 작업 |

- code-server만 모듈이 책임지고 나머지 네 개는 루트가 `additional_user_data`로 주입합니다. 모듈은 자기 루트에 EKS 클러스터가 있는지 몰라도 되어야 하고(B-4번 패턴), 클러스터가 없는 프로젝트에서는 이 네 개를 설치하지 않아 부팅이 빨라집니다.
- **기본 경계(E-1·E-2)**: Terraform runner가 public 또는 reachable-private EKS API에 닿는 루트에서 이 도구들은 사람이 데모·조사·진단할 때 씁니다. 설치되어 있다는 이유만으로 userdata나 `aws_ssm_association`에서 `kubectl apply`/`helm install`로 Terraform 수명주기의 리소스를 만들지 않으며, 그 리소스는 `kubectl_manifest`/`helm_release`가 소유합니다.
- **runner 비도달·작업대 도달 예외(E-9)**: Terraform runner에는 API의 DNS·네트워크 경로가 없지만 VPC 안의 작업대에는 경로가 있는 변형은, 그 작업대에서 SSM Association이 `kubectl apply`와 `helm upgrade --install`을 실행해 **클러스터 내부 리소스를 실제로 프로비저닝**합니다. 현재 저장소 사례는 private endpoint이지만 endpoint의 public/private 값 자체가 판정 기준은 아닙니다. 이때 SSM 단계는 대화형 편의가 아니라 Terraform이 관리하는 설치 절차이며, E-9의 마커 사슬·재실행 가능성·진단 규칙을 따라야 합니다. 이 예외를 API에 도달 가능한 provider 분기로 확장하지 않습니다.
- 클러스터가 같은 루트에 있으면 `aws eks update-kubeconfig`까지 userdata에서 끝내고, 그 인스턴스 역할에 클러스터 접근 권한을 주는 `aws_eks_access_entry`를 루트에 선언합니다(C-1번 패턴). 이것이 없으면 kubectl이 설치돼도 `error: You must be logged in to the server`로 아무것도 못 합니다.

```hcl
# 루트 main.tf
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  marker_file_path = var.marker_file_path
  # ec2-user로 실행합니다. root로 설치하면 도구와 kubeconfig가 /root에 들어가고,
  # code-server 세션(ec2-user)에서는 보이지 않습니다.
  #
  # HOME을 명시하는 이유: userdata는 root로 실행되고 sudo -E는 환경을 보존하므로
  # "~"가 /root를 가리킬 수 있습니다. 그러면 ec2-user 권한으로 /root에 쓰려다
  # Permission denied로 실패합니다. sudoers 설정에 의존하지 않게 못박습니다.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server는 usermod 이전에 이미 떠 있어서 docker 그룹을 갖고 있지 않습니다.
    # 재시작해야 IDE 터미널에서 docker 소켓에 접근할 수 있습니다.
    # (/var/run/docker.sock을 666으로 여는 방식은 쓰지 않습니다.)
    systemctl restart code-server

    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl && mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # 순서 주의: completion을 먼저 source해야 __start_kubectl이 정의됩니다.
    # complete를 먼저 쓰면 로그인마다 "function not found" 오류가 납니다.
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
```

- kubectl 버전은 리터럴로 박지 않고 `var.kubectl_download_version`(예: `1.33.3/2025-08-03`)로 받아 클러스터의 `kubernetes_version`과 함께 올립니다(B-3번 패턴). 서버와 ±1 마이너를 벗어나면 지원 스큐를 벗어납니다.
- eksctl은 `eksctl-io/eksctl`을 씁니다. 예전 `weaveworks/eksctl` URL도 리다이렉트로 동작하지만 정식 이름을 씁니다.
- `set -x`가 켜진 userdata에서는 모든 명령이 `/var/log/cloud-init-output.log`에 남습니다. 설치가 안 됐을 때 가장 먼저 볼 곳이며, 여기에 비밀값을 흘리는 명령을 넣지 않습니다.

### H-2. 루트의 README-safe output 표현은 SSM Association으로 `vscode_ec2`의 `README.md`에도 기록한다 (실제 민감값은 allowlist 예외)

**적용 조건: 루트에 `module "vscode_ec2"`가 있는 프로젝트.** 없으면 렌더링할 대상이 없으므로 이 규칙은 적용되지 않고, `local.outputs` 맵 없이 `outputs.tf`에 값 표현식을 직접 쓰는 평범한 output이 맞습니다. 그때는 **왜 맵을 쓰지 않았는지를 `outputs.tf` 상단 주석에 남깁니다**(`014_basic_ec2`, `015_basic_vpc_and_subnets`가 그 형태). 이유를 적지 않으면 다음 사람이 이 규칙 위반으로 읽습니다.

#### 작업대 README의 역할

code-server 세션은 apply 뒤의 **대화형 데모·조사·진단 작업**을 위한 곳이고 그 안에는 보통 Terraform 구성과 state가 없습니다. 그래서 사람이 그 자리에서 필요한 URL, 확인 명령, 데모 절차를 `/home/ec2-user/README.md`로 전달합니다. 반면 `plan`/`apply`/`destroy`, 계정 간 순서, state 밖 리소스의 철거처럼 **Terraform 수명주기를 통제하는 절차**는 작업대 README만을 권위 있는 기록으로 삼지 않습니다. I-4번이 적용되면 저장소의 README와 모든 참여 루트의 output에 먼저 남기고, H-2가 적용되는 루트에서만 같은 표현을 작업대 README에 추가로 미러링합니다.

E-9번 변형에서는 SSM Association이 클러스터 리소스를 프로비저닝할 수 있지만, 그것도 Terraform이 선언한 자동화 단계입니다. 사람이 README를 보고 수동으로 같은 리소스를 다시 만드는 것과 구분합니다.

#### output의 두 범주

- **비민감 표현 output**: README에 기록해도 되는 값 또는 명령입니다. 보통 실제 URL·ARN·이름이고, apply 시점에 Terraform이 모르는 컨트롤러 생성값은 조회 명령입니다. 각 output 이름과 같은 키를 `local.outputs`에 두고 `outputs.tf`와 README가 그 항목을 함께 투영합니다.
- **실제 민감값 output**: 비밀번호·토큰처럼 값 자체가 꼭 Terraform output이어야 하는 드문 예외입니다. 루트의 `local.sensitive_output_allowlist`에 실제 output 이름과 대응하는 안전한 조회 표현 키를 명시하고, output 블록에 `sensitive = true`를 설정하며, 실제 값은 `local.outputs`와 README에 넣지 않습니다. `sensitive = true`는 일반 CLI 표시만 가릴 뿐 state의 평문 값을 제거하거나 암호화하지 않으므로, 실제 output이 불필요하면 만들지 않고 조회 명령만 제공합니다.

따라서 "모든 output을 README에 넣는다"는 일대일 규칙은 **비민감 표현 output**에 적용됩니다. allowlist에 든 실제 민감값 output은 README에서 빠지는 대신, 대응하는 README-safe 조회 표현이 반드시 `local.outputs`에 있어야 합니다.

이 패턴은 누락을 문법적으로 불가능하게 만들지는 않습니다. 작성자가 direct expression output을 선언할 수 있으므로, **한 곳에서 정의한다는 convention과 아래의 집합 감사가 함께 규칙**입니다.

작성은 `aws_ssm_association`(`AWS-RunShellScript`)으로 하고, 순서는 마커 파일로 강제합니다(D-5번 패턴).

```hcl
# 루트 main.tf
locals {
  # 비민감 output 표현의 단일 정의입니다. outputs.tf와 README가 같은 맵을
  # 투영합니다. 새 output을 직접 선언해 이 맵을 우회할 수는 있으므로 리뷰와
  # 집합 감사로 누락을 잡습니다 (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "URL of the code-server web UI on the VS Code EC2 instance"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    update_kubeconfig_command = {
      order       = 4
      title       = "Update kubeconfig"
      description = "Command that points kubectl on this instance at the cluster"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # 맵을 그대로 순회하면 섹션이 키의 사전순으로 나옵니다. 결정적이긴 하지만
  # 읽는 순서와는 무관해서, "1. 스케일 업"보다 "2. 노드 확인"이 위에 올 수
  # 있습니다. order 필드로 다시 키를 만들고 values()를 취하면(values는 맵의 값을
  # 키 순서로 돌려줍니다) 의도한 순서가 되고, 순서는 여전히 설정만으로 결정됩니다.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
```

```hcl
# 루트 outputs.tf - 비민감 표현의 값은 local.outputs에서만 투영합니다.
# description은 표현식을 허용하지 않으므로 리터럴 설명만 두 곳에 존재합니다.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on this instance at the cluster"
}
```

실제 민감값 output이 꼭 필요하면 예외를 이름으로 드러냅니다.

```hcl
# main.tf
locals {
  outputs = {
    bootstrap_password_lookup = {
      order       = 90
      title       = "Read the bootstrap password"
      description = "Retrieve the secret only when it is needed"
      value       = "aws secretsmanager get-secret-value --secret-id ${module.app.secret_arn} --query SecretString --output text"
    }
  }

  # key = 실제 민감값 output, value = README-safe 표현 output
  sensitive_output_allowlist = {
    bootstrap_password = "bootstrap_password_lookup"
  }
}

# outputs.tf
output "bootstrap_password_lookup" {
  value       = local.outputs.bootstrap_password_lookup.value
  description = "Command that retrieves the bootstrap password on demand"
}
output "bootstrap_password" {
  value       = module.app.bootstrap_password
  description = "Bootstrap password for automation that explicitly consumes this sensitive output"
  sensitive   = true
}
```

#### 감사 기준

집합으로 판정합니다.

- `keys(local.outputs)` = 비민감 표현 output 이름 집합 = README 섹션 이름 집합.
- `keys(local.sensitive_output_allowlist)` = 실제 민감값 output 이름 집합.
- 모든 `output` 블록 이름 = 위 두 집합의 합집합이며 두 집합은 겹치지 않습니다.
- allowlist의 모든 값은 `keys(local.outputs)`에 존재하고, allowlist key에 해당하는 output은 `sensitive = true`입니다.
- 비민감 output의 `value`는 모두 `local.outputs.<같은_키>.value`입니다. allowlist에 든 output만 실제 값을 직접 참조할 수 있습니다.

민감값 예외가 없으면 기존의 단순 감사로 충분합니다: `outputs.tf`의 output 블록 수와 `local.outputs` 항목 수가 같아야 합니다. 예외가 있으면 **output 블록 수 = `local.outputs` 항목 수 + allowlist 항목 수**이고, 개수뿐 아니라 위 이름 집합을 대조합니다. 값이 unknown이어도 키는 plan 이전에 알 수 있으므로 `terraform console`에서 `keys(local.outputs)`와 `local.sensitive_output_allowlist`를 확인할 수 있습니다.

#### 렌더링과 순서 규칙

- 각 항목에 `order`를 붙이고 `values(...)`로 정렬합니다. README는 사람이 위에서 아래로 읽는 문서이고 데모 명령에는 실행 순서가 있는데, 맵을 그대로 순회하면 키의 사전순이 되어 순서가 깨집니다.
- **`aws_ssm_association`은 루트에 둡니다.** 여러 모듈의 output을 조합하는 책임은 루트의 것이고(C-1번 패턴), `vscode_ec2` 모듈은 자기 홈에 무엇이 적히는지 몰라도 됩니다.
- 마커 경로는 모듈 input을 그대로 output으로 되돌려받은 `module.vscode_ec2.marker_file_path`를 참조합니다(B-5번 패턴). 루트에서 `var.marker_file_path`를 직접 다시 쓰지 않습니다.
- 대기 조건은 `depends_on`이나 `wait_for_success_timeout_seconds`가 아니라 `until [ -f .../userdata ]` 루프입니다(D-5번 패턴). 이 association도 자신의 마커(`vscode_readme`)를 남겨 뒤 association이 이어서 기다릴 수 있게 합니다.
- **userdata의 마커는 스크립트 맨 마지막에 생성되어야 합니다.** `${var.additional_user_data}`보다 먼저 `touch`하면 도구 설치 도중에 README association이 출발합니다.
- SSM 명령은 root로 실행되므로 `chown ec2-user:ec2-user`가 필요합니다. 없으면 code-server에서 편집이 안 됩니다.
- 셸 heredoc 구분자는 `<< 'TFREADME'`처럼 인용하고 본문에 나올 수 없는 문자열로 정합니다. 값은 Terraform이 이미 채워 넣었으므로 셸이 `$`나 백틱을 확장할 이유가 없습니다.
- `parameters`가 바뀌면 association이 다시 실행되고 `cat >`가 파일을 덮어쓰므로, output 표현이 바뀌면 README도 따라 갱신됩니다.
- **apply 시점에 Terraform이 모르는 값**(예: 컨트롤러가 만드는 로드밸런서 DNS 이름)은 항목을 빼지 않고 조회 명령을 값으로 넣습니다. 이는 민감값 예외가 아니라 정상적인 비민감 표현입니다.
- 이 패턴은 인스턴스에 `AmazonSSMManagedInstanceCore`가 붙어 있어야 동작합니다(`vscode_ec2` 모듈의 `iam_policy_arns` 기본값에 포함).
