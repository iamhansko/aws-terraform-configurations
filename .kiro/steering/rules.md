---
inclusion: always
---

# Terraform Configuration Rules

`999_ec2_userdata_wait`처럼 하나의 상위 폴더 아래 여러 변형(`cloud_init_status`, `marker_files` 등)이 **동일한 인프라(VPC, 키페어, EC2)를 공유하되 대기/완료 감지 방식만 다른** 경우, 아래 구조를 따릅니다.

_monolithic/ 디렉토리(폴더)에 위치한 파일은 조회/분석만 가능하고, 절대로 수정/삭제할 수 없습니다.

## 1. 디렉토리 구조

```
NNN_<주제>/
├── <variant_a>/                 # 변형별 루트 구성 (독립적으로 init/plan/apply 가능)
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf                  # source = "./modules/<name>" 로 이 변형 전용 모듈 참조
│   ├── outputs.tf
│   └── modules/                 # 이 변형 전용 모듈 (변형 폴더 하위에 위치)
│       ├── network/
│       ├── key_pair/
│       └── <app>_ec2/
├── <variant_b>/
│   └── ... (동일 구조, 자체 modules/ 보유 — <variant_a>의 modules/를 참조하지 않음)
└── README.md
```

- 변형 간에 리소스 정의가 동일하더라도 **모듈을 상위 폴더로 승격해서 공유하지 않습니다.** 각 변형은 자신의 폴더 하위에 `modules/`를 독립적으로 소유합니다.
- 이유: 각 변형 폴더가 독립적인 Terraform 루트 모듈(자체 상태, 자체 `.terraform.lock.hcl`)로 완전히 자기완결적이어야 하며, 다른 변형 폴더의 존재나 상대 경로(`../modules`)에 의존하면 한 변형만 따로 복사/이동/삭제할 때 깨집니다.
- 모듈 코드가 변형 간에 동일한 경우, 처음 작성한 모듈을 복사해서 시작하되 이후 각 변형의 모듈은 독립적으로 진화시킵니다 (한쪽 모듈 변경이 다른 변형에 영향을 주지 않음).

## 2. 루트 구성과 모듈 모두 4파일 분리

루트 구성(`main.tf`가 있던 폴더)과 각 모듈 모두 아래 4개 파일로 분리합니다:

- `providers.tf` — `terraform` 블록(`required_version`, `required_providers`)과 `provider "aws"` (루트만 해당; 모듈에는 `provider` 블록 없이 `required_providers`만).
- `variables.tf` — 모든 `variable` 선언.
- `main.tf` — `data` 소스, `resource`, `module` 블록만 (변수/출력 선언 없음).
- `outputs.tf` — 모든 `output` 선언.

## 3. 변수에는 `validation` 블록을 기본으로 추가

모든 변수(특히 리소스 ID, CIDR, 이름 문자열)에 형식 검증을 넣어 `terraform plan` 단계에서 오타를 즉시 잡아냅니다.

```hcl
variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group is created"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
```

- 리소스 ID(`vpc-*`, `subnet-*`, `ami-*`)는 접두사 정규식으로 검증.
- CIDR은 `can(cidrhost(var.x, 0))`으로 검증.
- 이름/문자열 변수는 최소 `length(var.x) > 0`으로 빈 값을 방지.
- Optional 변수(선택적 기능 스위치)는 `null` 허용을 조건에 포함: `var.x == null || can(regex(...))`.

## 4. 선택적 기능은 nullable 변수 + 템플릿 디렉티브로 구현

여러 변형이 공유하는 모듈에서 일부 변형에만 필요한 기능(예: 완료 마커 파일 생성)은 필수 변수로 강제하지 않고, 기본값 `null`인 선택적 변수로 노출한 뒤 heredoc 안에서 `%{ if ... }` 템플릿 디렉티브로 조건부 렌더링합니다.

```hcl
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory ... When null, no marker file is created."

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
```

```hcl
user_data = <<-EOT
  ...
  %{ if var.marker_file_path != null ~}
  mkdir -p ${var.marker_file_path}
  touch ${var.marker_file_path}/userdata
  %{ endif ~}
  ${var.additional_user_data}
  EOT
```

이렇게 하면 이 기능이 필요 없는 변형(`cloud_init_status`)은 `marker_file_path`를 아예 넘기지 않아도 되고, 모듈은 특정 변형의 존재를 몰라도 됩니다 (낮은 결합도). 이 패턴은 모듈이 변형 간에 공유되든(예전 구조) 변형별로 독립 소유되든(현재 구조, 1번 항목 참고) 동일하게 적용됩니다.

## 5. 모듈 입력을 그대로 모듈 출력으로 되돌려주는 패턴 (단일 진실 공급원)

모듈 내부에서 생성한 경로/이름을 호출자(루트)의 다른 리소스(예: 완료를 폴링하는 `aws_ssm_association`)가 다시 참조해야 할 때, 루트의 `local`/하드코딩 값을 양쪽에서 각자 들고 있지 않고 **모듈이 입력받은 값을 그대로 output으로 재노출**해서 호출자가 그 output만 참조하게 합니다.

```hcl
# 모듈 outputs.tf
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set"
}
```

```hcl
# 루트 main.tf
module "vscode_ec2" {
  marker_file_path = var.marker_file_path
  ...
}

resource "aws_ssm_association" "vscode_association_1" {
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      ...
      EOT
  }
}
```

값이 한 곳(`var.marker_file_path`)에서만 정의되고 모듈의 input/output을 거쳐 전파되므로, 값이 두 군데서 독립적으로 관리되어 어긋나는 문제(단일 진실 공급원 위반)를 구조적으로 방지합니다.

## 6. SSM Association 순차 대기 체인 패턴

EC2 인스턴스의 userdata/설정 완료를 `aws_ssm_association`으로 순차 검증해야 할 때:

- 각 association은 `depends_on`으로 이전 association을 가리키되, **`depends_on`만으로 완료 순서를 신뢰하지 않습니다** (`wait_for_success_timeout_seconds`가 실제 원격 명령 완료를 안정적으로 기다리지 못하는 프로바이더 이슈가 있음).
- 대신 각 단계가 "이전 단계의 마커 파일이 생길 때까지 `until` 루프로 대기 → 자기 작업 수행 → 자신의 마커 파일 생성" 순서로 셸 스크립트 자체가 순서를 강제하게 만듭니다.

```hcl
resource "aws_ssm_association" "vscode_association_2" {
  depends_on = [aws_ssm_association.vscode_association_1]
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_association_1 ]; do sleep 10; done
      ...
      touch ${module.vscode_ec2.marker_file_path}/vscode_association_2
      EOT
  }
}
```

## 7. 루트 구성의 하드코딩 값은 변수로 승격

`main.tf`의 `module` 블록에 리터럴 값(`name = "vscode"`, `instance_type = "t3.small"`, `key_name = "ec2-keypair"`)을 직접 쓰지 않고, 루트 `variables.tf`에 기본값을 가진 변수로 선언한 뒤 참조합니다. 변형마다 다른 값이 필요할 때 `.tfvars` 오버라이드만으로 대응할 수 있습니다.

```hcl
# variables.tf
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the VS Code EC2 instance"
}

# main.tf
module "vscode_ec2" {
  instance_type = var.vscode_instance_type
  ...
}
```

## 12. IAM 역할-정책 결합 리소스는 `depends_on`으로 생성 순서를 명시

`aws_eks_cluster`, `aws_eks_node_group`처럼 특정 관리형 IAM 정책이 반드시 부착되어 있어야 생성 요청이 성립하는 리소스는, IAM 역할과 정책 attachment를 명시적으로 기다리게 합니다. AWS API가 이 요구사항을 강제하지만 Terraform 그래프는 `role_arn`/`node_role_arn`만 보고는 정책 attachment까지의 의존성을 추론하지 못하는 경우가 있어 `depends_on`으로 직접 명시합니다.

```hcl
resource "aws_iam_role_policy_attachment" "eks_cluster_iam_role" {
  role       = aws_iam_role.eks_cluster_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "eks_cluster" {
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  ...
  # The cluster role must have AmazonEKSClusterPolicy attached before EKS will
  # accept it; without this the create call can race the attachment.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_iam_role]
}
```

같은 이유로 `aws_eks_node_group`도 `aws_iam_role_policy_attachment.eks_node_iam_role`(worker 정책들)을 `depends_on`으로 기다리고, `vscode_ec2`의 `aws_instance`도 자신의 `aws_iam_role_policy_attachment`를 `depends_on`으로 기다립니다.

## 13. 여러 개의 IAM 관리형 정책은 `for_each`로 attach

역할 하나에 여러 관리형 정책을 붙일 때 `aws_iam_role_policy_attachment` 리소스를 정책 개수만큼 복제(`_0`, `_1`, `_2`...)하지 않고, 정책 ARN 목록을 변수로 받아 `for_each`로 단일 리소스 블록에서 반복 생성합니다.

```hcl
variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the node group's IAM role"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.eks_node_iam_role.name
  policy_arn = each.value
}
```

정책 목록을 호출자가 변수로 오버라이드할 수 있게 되므로, 모듈을 수정하지 않고도 추가 정책을 붙이거나 뗄 수 있습니다.

## 14. EKS 클러스터 접근 권한 부여는 루트에서 두 모듈의 output을 연결

특정 IAM 주체(예: 관리용 EC2 인스턴스)에게 EKS 클러스터 접근 권한을 부여하는 `aws_eks_access_entry`/`aws_eks_access_policy_association`은 클러스터 모듈이나 EC2 모듈 내부에 넣지 않고, **루트 `main.tf`에서 두 모듈의 output을 조합**해서 선언합니다.

```hcl
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
```

이렇게 하면 `eks_cluster` 모듈은 "어떤 주체에게 접근 권한을 줄지"를 몰라도 되고, `vscode_ec2` 모듈은 "EKS 클러스터가 존재하는지"를 몰라도 됩니다. 두 모듈 다 서로의 존재를 모른 채 독립적으로 재사용 가능하며, 두 모듈을 연결하는 책임은 오직 루트가 짊니다.

## 15. 모듈에 필요한 외부 리소스는 ID/이름 목록으로만 주입 (보안그룹 예시)

`vscode_ec2` 모듈처럼 다른 모듈이 소유한 리소스(EKS 클러스터 보안그룹 등)에 접근해야 하는 경우, 모듈이 그 리소스를 직접 조회하거나 참조하지 않고 **호출자가 ID 리스트를 변수로 전달**하게 합니다.

```hcl
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance (e.g. an EKS cluster security group, to allow API server access)"
}
```

```hcl
resource "aws_instance" "vscode_ec2" {
  vpc_security_group_ids = concat([aws_security_group.vscode_ec2_security_group.id], var.extra_security_group_ids)
}
```

```hcl
# 루트 main.tf
module "vscode_ec2" {
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
}
```

모듈 자신의 기본 보안그룹은 모듈이 직접 만들고, 외부에서 추가로 붙여야 하는 보안그룹은 `concat()`으로 병합합니다. 모듈은 "추가 보안그룹 ID 목록을 받는다"는 사실만 알고, 그게 EKS 클러스터의 것인지 다른 무엇인지는 몰라도 됩니다.

## 16. 3-AZ 네트워크가 필요하면 `network` 모듈의 서브넷을 3벌로 확장하고 `_ids` 배열 output도 추가

EKS 등 다중 AZ 고가용성이 필요한 리소스를 다루는 프로젝트에서는 `network` 모듈의 서브넷을 A/B 2개가 아니라 A/B/C 3개로 확장합니다(`cidrsubnet(..., 5)`까지 사용). 이때 개별 서브넷 output(`public_subnet_a_id` 등) 뿐 아니라, 호출자가 리스트로 바로 쓸 수 있는 배열 output도 함께 노출합니다.

```hcl
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id, aws_subnet.public_subnet_c.id]
  description = "IDs of all public subnets"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  description = "IDs of all private subnets"
}
```

```hcl
# 루트 main.tf — EKS 클러스터는 전체 서브넷, 노드그룹은 private 서브넷만 필요
module "eks_cluster" {
  subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
}

module "eks_node_group" {
  subnet_ids = module.network.private_subnet_ids
}
```

개별 output은 특정 AZ 하나만 필요한 호출자(예: `vscode_ec2`의 `subnet_id = module.network.public_subnet_a_id`)를 위해 유지하고, 배열 output은 "모든 서브넷"이 필요한 호출자를 위해 추가합니다.

## 17. AMI 타입 등 AWS가 정한 고정된 열거값은 `contains()`로 검증

`ami_type`, `capacity_type`처럼 AWS API가 허용하는 값이 고정된 열거형(enum)인 변수는 정규식이 아니라 `contains([...], var.x)`로 검증합니다.

```hcl
variable "ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64",
      "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64", "BOTTLEROCKET_ARM_64_NVIDIA", "BOTTLEROCKET_x86_64_NVIDIA",
      "WINDOWS_CORE_2019_x86_64", "WINDOWS_FULL_2019_x86_64", "WINDOWS_CORE_2022_x86_64", "WINDOWS_FULL_2022_x86_64",
      "CUSTOM"
    ], var.ami_type)
    error_message = "ami_type must be a valid EKS node group AMI type."
  }
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be either ON_DEMAND or SPOT."
  }
}
```

## 18. EC2 userdata/SSM Association으로 만들던 쿠버네티스 리소스는 kubernetes/helm 프로바이더로 대체

`kubectl apply`, `helm install`을 EC2 인스턴스 안에서 실행하는 셸 스크립트(user_data나 `aws_ssm_association`)로 만들지 않고, `hashicorp/kubernetes`/`hashicorp/helm` 프로바이더 리소스로 직접 선언합니다. 두 프로바이더 모두 `exec` 플러그인으로 `aws eks get-token`을 호출해 EKS 클러스터에 인증합니다 (kubeconfig 파일이나 별도 EC2 불필요).

```hcl
# 루트 providers.tf
provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}
```

- 이를 위해 `eks_cluster` 모듈은 `cluster_endpoint`뿐 아니라 `certificate_authority_data`(`aws_eks_cluster.eks_cluster.certificate_authority[0].data`)도 output으로 노출해야 합니다.
- Namespace/RBAC(ClusterRole, ClusterRoleBinding, Role, RoleBinding)는 `kubernetes_namespace`/`kubernetes_cluster_role`/`kubernetes_cluster_role_binding`/`kubernetes_role`/`kubernetes_role_binding` 리소스로 선언합니다. 여러 네임스페이스에 동일한 Role/RoleBinding이 필요하면 `for_each = kubernetes_namespace.xxx`로 반복합니다.
- Helm 차트 설치(예: Karpenter)는 `helm_release` 리소스로 선언합니다. 전용 모듈로 분리해서 `values`/IAM 역할 ARN 등을 변수로 받게 합니다.

```hcl
resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter/karpenter"
  chart            = "karpenter"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true

  set = [
    { name = "settings.clusterName", value = var.cluster_name },
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = var.controller_role_arn },
  ]
}
```

이 패턴으로 바뀌면 셸 스크립트에 `kubectl`/`helm` CLI를 설치하고, 그 명령이 EC2 안에서 성공했는지 SSM으로 확인하는 전체 인프라(마커 파일, `until` 대기 루프, `wait_for_success_timeout_seconds`)가 필요 없어집니다. 리소스 자체가 Terraform 상태로 추적되므로 `terraform plan`으로 변경 사항을 미리 확인할 수 있습니다.

## 19. Fargate profile 생성 후 기존 파드를 재스케줄해야 할 때는 `kubernetes_annotations`의 `template_annotations`로 rollout 트리거

`aws_eks_fargate_profile`은 생성 시점 이후의 신규 파드에만 매칭되므로, 프로파일보다 먼저 존재하던 파드(예: 클러스터 생성 시 기본으로 뜨는 CoreDNS)는 `kubectl rollout restart deployment coredns`로 강제 재생성해야 Fargate로 옮겨갑니다. `kubernetes_annotations` 리소스의 `template_annotations`는 Deployment의 pod 템플릿에 patch를 적용하므로, 동일한 rollout을 셸 명령 없이 트리거합니다.

```hcl
resource "kubernetes_annotations" "reschedule_deployment" {
  count = var.reschedule_deployment_name != null ? 1 : 0

  api_version = "apps/v1"
  kind        = "Deployment"
  metadata {
    name      = var.reschedule_deployment_name
    namespace = var.namespace
  }
  template_annotations = {
    "terraform.io/restartedAt" = timestamp()
  }
  force = true

  depends_on = [aws_eks_fargate_profile.fargate_profile]

  lifecycle {
    ignore_changes = [template_annotations]
  }
}
```

- `timestamp()`는 매 `apply`마다 값이 바뀌므로, `lifecycle.ignore_changes`로 최초 1회만 트리거되게 막아둡니다 (그렇지 않으면 매번 재시작을 유발합니다).
- 이 기능이 필요 없는 호출자는 `reschedule_deployment_name`을 `null`로 두면 되므로, 4번 패턴(nullable 변수 + 조건부 리소스)과 동일한 방식입니다.

## 20. AWS 서비스가 EKS에 접근해야 할 때는 principal이 서비스 연결 역할인지 먼저 확인한다 (Access Entry는 서비스 연결 역할을 지원하지 않음)

**`aws_eks_access_entry`는 서비스 연결 역할(service-linked role)을 principal로 지원하지 않습니다.** `AWSServiceRoleForBatch`처럼 AWS 관리형 서비스가 자동으로 만드는 서비스 연결 역할을 `principal_arn`으로 넘기면 다음 에러로 실패합니다 (AWS 공식 문서에도 명시: "The caller is not allowed to modify access entries with a principalArn value of a Service Linked Role").

```
Error: creating EKS Access Entry (...): InvalidParameterException: The specified principalArn is invalid: invalid principal.
```

서비스 연결 역할인지 아닌지는 ARN으로 구분합니다: `arn:aws:iam::<account>:role/aws-service-role/<service>/<role-name>` 형태(경로에 `aws-service-role/`가 포함)면 서비스 연결 역할입니다. 일반 IAM 역할(`vscode_ec2`의 인스턴스 역할, `karpenter`의 노드 역할 등)은 이 경로가 없으므로 Access Entry로 정상 매핑됩니다 — 이 구분 없이 "서비스가 접근해야 하면 무조건 Access Entry"로 일반화하지 않습니다.

- **일반 IAM 역할**(경로에 `aws-service-role/` 없음)은 그대로 `aws_eks_access_entry`의 `user_name`으로 매핑합니다:

```hcl
resource "aws_eks_access_entry" "vscode_ec2_access_entry" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.vscode_ec2_iam_role.arn # 일반 IAM 역할, 서비스 연결 역할 아님
  type          = "STANDARD"
}
```

- **서비스 연결 역할**(예: `AWSServiceRoleForBatch`)은 Access Entry 대신 `kubectl_manifest`로 `aws-auth` ConfigMap의 `mapRoles`를 패치합니다. `server_side_apply = true` + `force_conflicts = true`로 ConfigMap 전체를 덮어쓰지 않고 `mapRoles` 필드만 병합해서, EKS/관리형 노드그룹이 이미 넣어둔 다른 항목(예: 노드 인스턴스 역할 매핑)을 건드리지 않습니다.

```hcl
locals {
  # AWS IAM Authenticator(aws-auth ConfigMap이 쓰는 인증기)는 rolearn에
  # 경로(path)가 포함된 ARN을 허용하지 않습니다 ("The AWS IAM Authenticator
  # doesn't permit a path in the role ARN used in the ConfigMap"). 실제
  # AWSServiceRoleForBatch의 전체 ARN은
  # role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch처럼
  # 경로를 포함하지만, ConfigMap에는 경로를 뗀 role/AWSServiceRoleForBatch
  # 형태로 넣어야 합니다. aws_eks_access_entry의 principal_arn(전체 ARN
  # 필요)과 정반대 요구사항이라는 점에 주의합니다 — 다만 서비스 연결 역할은
  # 애초에 Access Entry의 principal로 아예 쓸 수 없으므로 이 경로 문제는
  # ConfigMap 방식에서만 발생합니다.
  batch_service_linked_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSServiceRoleForBatch"
}

resource "kubectl_manifest" "batch_service_aws_auth_mapping" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata   = { name = "aws-auth", namespace = "kube-system" }
    data = {
      mapRoles = yamlencode([
        { rolearn = local.batch_service_linked_role_arn, username = var.batch_username, groups = [] },
      ])
    }
  })

  force_conflicts   = true
  server_side_apply = true
}
```

경로를 포함한 전체 ARN을 그대로 `rolearn`에 넣으면 인증기가 매칭시키지 못해, `aws_batch_compute_environment`가 `Unable to validate Kubernetes Namespace ... for computeEnvironment`로 실패합니다 (RBAC 서브젝트가 인증되지 않아 AWS Batch가 네임스페이스 접근 권한을 검증할 수 없음). 이 방식이 가능한 조건은 클러스터의 `authentication_mode`가 `CONFIG_MAP` 또는 `API_AND_CONFIG_MAP`이어야 합니다 (`access_config.authentication_mode`, 이미 이 저장소의 `eks_cluster` 모듈은 `API_AND_CONFIG_MAP`을 사용 중이라 Access Entry와 `aws-auth` ConfigMap을 함께 쓸 수 있습니다). RBAC `ClusterRoleBinding`/`RoleBinding`의 subject는 두 방식 모두 동일하게 `var.batch_username`(Access Entry의 `user_name` 또는 ConfigMap의 `username`)을 참조하므로, 어느 방식으로 매핑했는지와 무관하게 RBAC 쪽 코드는 그대로 유지됩니다.

## 21. IRSA(IAM Roles for Service Accounts)를 쓰는 컨트롤러는 IAM 역할과 Helm 릴리스를 같은 모듈에 둔다

Karpenter처럼 Helm으로 설치하는 Kubernetes 컨트롤러가 IRSA로 AWS API를 호출해야 할 때, "IAM 역할을 만드는 모듈"과 "Helm 차트를 설치하는 모듈"을 따로 두지 않고 하나의 모듈(`modules/karpenter`)에 통합합니다. IAM 역할(컨트롤러용 IRSA 역할, 노드용 인스턴스 역할)과 `helm_release`가 서로를 참조해야 하는 강한 결합 관계이기 때문입니다.

```hcl
# modules/karpenter/main.tf
resource "aws_iam_role" "karpenter_controller_iam_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
        }
      }
    }]
  })
}

resource "helm_release" "karpenter" {
  set = [
    { name = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn", value = aws_iam_role.karpenter_controller_iam_role.arn },
  ]
  depends_on = [aws_iam_role_policy_attachment.karpenter_controller_iam_role]
}
```

- `helm_release`는 역할 ARN을 변수로 받지 않고, 같은 모듈 안의 `aws_iam_role` 리소스를 직접 참조합니다. 14/15번 패턴(모듈 경계를 넘는 결합은 ID/ARN을 변수로 주입)은 **서로 다른 책임을 가진 모듈 사이**에 적용하는 규칙이며, 이 경우처럼 하나의 컴포넌트(Karpenter)를 구성하는 IAM+Helm은 애초에 분리할 이유가 없는 강결합이므로 한 모듈로 유지합니다.
- 이 모듈의 `providers.tf`는 `aws`와 `helm` 양쪽 `required_providers`를 모두 선언합니다.
- IAM 역할이 필요한 이유가 사라지면(예: IRSA 대신 Pod Identity로 전환) 모듈 하나만 교체하면 되므로, "이 컨트롤러를 설치하는 데 필요한 모든 것"이 한 곳에 모여 있어 유지보수가 쉬워집니다.

## 22. 모듈 간 생성 순서는 `module` 블록의 `depends_on` 메타 인수로 표현

한 모듈의 리소스가 다른 모듈이 실제로 준비된 뒤에 동작해야 하지만 두 모듈 사이에 값(output→input) 참조가 없는 경우, `module` 블록에 `depends_on` 메타 인수를 추가해 순서를 명시합니다.

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # CoreDNS must be schedulable (i.e. running on the Fargate profile) before
  # the Karpenter controller pod can resolve DNS and reach the EKS API.
  depends_on = [module.eks_fargate_profile]
}
```

`karpenter` 모듈은 `eks_fargate_profile` 모듈의 output을 전혀 쓰지 않으므로(값 참조로는 암묵적 의존관계가 생기지 않음), Terraform 그래프만 보면 두 모듈이 동시에 생성될 수 있습니다. 하지만 Karpenter 컨트롤러 파드가 뜨려면 CoreDNS가 (Fargate profile 생성 후 19번 패턴으로 재스케줄되어) 먼저 응답 가능한 상태여야 하므로, 이 실제 런타임 의존성을 `depends_on`으로 명시적으로 표현합니다. 12번 패턴(리소스 레벨 `depends_on`)과 동일한 이유이며, 적용 대상이 리소스가 아니라 모듈 블록이라는 점만 다릅니다.

## 23. Add-on DaemonSet의 환경변수는 `aws_eks_addon`의 `configuration_values`로 설정 (셸의 `kubectl set env` 대체)

`vpc-cni`, `coredns`처럼 EKS 관리형 Add-on으로 배포되는 DaemonSet/Deployment의 환경변수(`ENABLE_POD_ENI`, `POD_SECURITY_GROUP_ENFORCING_MODE` 등)를 EC2 userdata에서 `kubectl set env daemonset aws-node -n kube-system ...`으로 설정하지 않고, `aws_eks_addon` 리소스의 `configuration_values`(JSON 문자열)로 선언합니다. 이는 18번 패턴(userdata의 kubectl/helm 명령을 프로바이더 리소스로 대체)의 Add-on 전용 구체 사례입니다.

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  configuration_values = jsonencode({
    env = {
      ENABLE_POD_ENI                    = tostring(var.enable_pod_eni)
      POD_SECURITY_GROUP_ENFORCING_MODE = var.pod_security_group_enforcing_mode
    }
  })
}
```

- `configuration_values`가 받는 JSON 스키마는 Add-on마다 다르며(`vpc-cni`는 `env` 맵으로 DaemonSet 환경변수를 받음), Add-on의 `aws eks describe-addon-configuration` 출력이나 공식 문서로 확인해야 합니다.
- `aws_eks_addon`은 `status`라는 output 속성을 노출하지 않습니다 (`arn`, `id`, `configuration_values`, `created_at`, `modified_at` 등은 노출). Add-on 상태를 output으로 참조하려는 경우 `terraform validate` 단계에서 "Unsupported attribute" 에러가 나므로, 실제로 필요한 output만(`arn` 등) 선언합니다.

## 24. Kubernetes CRD(커스텀 리소스)는 `kubernetes_manifest`로 선언

`SecurityGroupPolicy`(vpc-resource-controller), 기타 오퍼레이터가 정의한 CRD처럼 `hashicorp/kubernetes` 프로바이더에 전용 리소스 타입이 없는 커스텀 리소스는, EC2에서 매니페스트 YAML을 렌더링해 `kubectl apply`하는 대신 `kubernetes_manifest` 리소스에 `manifest` 블록(HCL 객체)으로 그대로 선언합니다.

```hcl
resource "kubernetes_manifest" "default_sgp" {
  manifest = {
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"
    metadata = {
      name      = var.policy_name
      namespace = var.namespace
    }
    spec = {
      podSelector = {}
      securityGroups = {
        groupIds = [aws_security_group.default_pod_security_group.id]
      }
    }
  }
}
```

- `apiVersion`/`kind`는 원본 매니페스트(YAML)의 값을 그대로 옮기고, `spec` 내부 필드도 YAML 키를 그대로 HCL 객체 키로 변환합니다 (camelCase 유지, YAML을 HCL로 재작성하지 않음).
- CRD가 참조하는 리소스(예: 보안그룹 ID)는 `aws_security_group` 등 같은 모듈의 리소스 참조로 채워서, 원본이 셸 스크립트에서 `${aws_security_group.xxx.id}` 문자열 치환으로 하던 일을 Terraform 참조로 대체합니다.
- CRD가 먼저 존재해야 스케줄링에 영향을 주는 데모 리소스(예: 데모 Pod)는 `depends_on = [kubernetes_manifest.xxx]`로 순서를 명시합니다 (12번 패턴과 동일한 이유).

## 25. `aws_iam_instance_profile`의 `role`은 역할 이름 문자열 하나만 받는다 (CloudFormation 변환 시 흔한 버그)

CloudFormation의 `AWS::IAM::InstanceProfile`은 `Roles`가 리스트지만, Terraform의 `aws_iam_instance_profile.role`은 **역할 이름 문자열 하나**만 받습니다 (인스턴스 프로필에는 역할이 최대 1개만 연결 가능). CloudFormation을 Terraform으로 변환한 코드에서 `role = jsonencode([aws_iam_role.xxx.name])`처럼 리스트를 JSON 인코딩해서 넘기는 경우가 있는데, 이는 `role`이 문자열 타입인데 JSON 배열 문자열을 넘기는 것이므로 `apply` 시 IAM API 에러로 실패합니다.

```hcl
# 잘못됨 (CloudFormation Roles 리스트를 그대로 옮긴 흔적)
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = jsonencode([aws_iam_role.vscode_ec2_iam_role.name])
}

# 올바름
resource "aws_iam_instance_profile" "vscode_ec2_instance_profile" {
  role = aws_iam_role.vscode_ec2_iam_role.name
}
```

CloudFormation 변환 결과물(`_monolithic/*.tf`)을 참고 자료로 모듈화할 때는 이런 리스트→단일 값 축소가 필요한 속성(`role`, `key_name` 등 1:1 관계인 필드)을 눈여겨보고, 원본을 그대로 베끼지 않습니다.

## 26. 단일 `terraform apply`가 필요하면 Kubernetes 리소스는 `hashicorp/kubernetes` 대신 `alekc/kubectl`의 `kubectl_manifest`로 선언

`hashicorp/kubernetes` 프로바이더(타입드 리소스인 `kubernetes_namespace`/`kubernetes_cluster_role`/`kubernetes_role_binding`/`kubernetes_annotations`뿐 아니라 24번 패턴의 `kubernetes_manifest`도 포함)는 신규 EKS 클러스터를 만드는 것과 같은 루트 모듈, 같은 `apply`에서 클러스터에 리소스를 배포하려고 하면 `Error: Failed to construct REST client ... cannot create REST client: no client config` 에러로 실패합니다. 원인은 Terraform이 `plan` 단계에서 프로바이더를 미리 구성하는데, `module.eks_cluster.cluster_endpoint`/`certificate_authority_data`처럼 아직 존재하지 않는 리소스의 output은 그 시점에 값이 알려지지 않은(unknown) 상태이기 때문입니다. HashiCorp도 공식적으로 "클러스터와 그 클러스터의 Kubernetes 리소스는 별도의 root module/state로 분리하라"고 권장합니다.

단일 `terraform apply`로 클러스터와 Kubernetes 리소스를 함께 만들어야 하는 이 저장소의 워크플로우에서는, `hashicorp/kubernetes`의 타입드 리소스와 `kubernetes_manifest` 전부를 `alekc/kubectl` 프로바이더의 `kubectl_manifest` 리소스로 대체합니다. 이 프로바이더는 `lazy_load = true`를 지원해서, provider 블록 설정 시점에 `host`/`cluster_ca_certificate` 등이 아직 unknown이어도 그 에러를 삼키고 실제 클라이언트 생성을 리소스가 처음 쓰이는 시점(즉 `apply` 중, 클러스터가 이미 만들어진 뒤)으로 미룹니다.

```hcl
# 루트 providers.tf
terraform {
  required_providers {
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
  }
}

provider "kubectl" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}
```

타입드 리소스는 `yamlencode()`로 감싼 HCL 객체를 `yaml_body`에 넣어 원본 Kubernetes API 필드명(camelCase: `apiGroups`, `roleRef`, `apiGroup`, `subjects`)을 그대로 씁니다. HCL 블록 문법(`rule { ... }`, `role_ref { ... }`)이 아니라는 점에 주의합니다.

```hcl
resource "kubectl_manifest" "aws_batch_cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata   = { name = "aws-batch-cluster-role-binding" }
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "aws-batch-cluster-role" }
    subjects   = [{ kind = "User", name = var.batch_username, apiGroup = "rbac.authorization.k8s.io" }]
  })

  # roleRef.name is a literal string, not an attribute reference, so
  # Terraform's graph doesn't otherwise know the ClusterRole must exist first.
  depends_on = [kubectl_manifest.aws_batch_cluster_role]
}
```

- 리소스 간 참조(예: Role이 특정 Namespace 안에 있어야 함)는 `for_each = kubectl_manifest.batch_namespace`로 네임스페이스 **리소스 맵**을 순회해서 `each.value.name`(매니페스트에서 추출된 attribute)을 쓰고, `toset(local.all_namespaces)`처럼 문자열 리스트를 그대로 순회하지 않습니다. 문자열을 그대로 쓰면 Terraform 그래프상 두 리소스 사이에 아무 의존관계가 생기지 않습니다.
- `roleRef`/`subjects`처럼 이름을 리터럴 문자열로만 주고받는 관계(속성 참조가 아님)는 12번 패턴과 같은 이유로 `depends_on`을 명시합니다.
- 19번 패턴(`kubernetes_annotations`의 `template_annotations`로 rollout 트리거)은 `kubectl_manifest`로는 `spec.template.metadata.annotations`만 채운 부분 매니페스트를 apply해서 동일하게 구현합니다. `timestamp()`가 매 apply마다 값이 바뀌므로 `lifecycle.ignore_changes = [yaml_body]`로 최초 1회만 반영되게 막습니다 (`kubernetes_annotations`의 `ignore_changes = [template_annotations]`와 동일한 목적, 대상 속성만 다름).
- `helm_release`(21번 패턴)는 이 문제의 영향을 받지 않습니다. `helm` 프로바이더는 `plan` 단계에서 클러스터 접속이 필요 없고 `apply` 시점에만 접속하므로, `hashicorp/helm`을 그대로 유지합니다. 이 워크어라운드가 필요한 대상은 오직 Kubernetes 리소스(구 `hashicorp/kubernetes`, `kubernetes_manifest`)뿐입니다.
- `alekc/kubectl`은 `gavinbunney/kubectl`의 유지보수 포크입니다. 신규 프로바이더 도입 시에는 `gavinbunney`가 아니라 `alekc`를 사용합니다 (2024년 이후 `gavinbunney/kubectl`은 유지보수가 중단됨).

## 27. `network` 모듈의 VPC/서브넷을 사용하는 모든 모듈은 `depends_on = [module.network]`를 명시

루트 `main.tf`에서 `module.network.vpc_id`, `module.network.*_subnet_id`, `module.network.*_subnet_ids` 중 하나라도 입력으로 받는 모든 `module` 블록은, 그 값을 실제로 참조하고 있어도 별도로 `depends_on = [module.network]`를 추가합니다.

```hcl
module "eks_cluster" {
  source = "./modules/eks_cluster"

  subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)

  # module.network.public_subnet_ids/private_subnet_ids만으로는 그 값을
  # 만든 특정 aws_subnet 리소스 이후로만 순서가 잡히고, NAT 게이트웨이·
  # 라우트 테이블 연결 등 network 모듈의 나머지 리소스와는 아무 의존관계가
  # 없습니다. depends_on으로 "network 전체가 끝난 뒤"를 명시합니다.
  depends_on = [module.network]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

  depends_on = [module.network]
}
```

이유: `module.network.vpc_id`/`*_subnet_id` 같은 값 참조는 Terraform 그래프에서 그 값을 생성한 **특정 리소스**(`aws_vpc.vpc`, 특정 `aws_subnet`)까지만 의존관계를 만듭니다. NAT 게이트웨이, 인터넷 게이트웨이, 라우트 테이블, 라우트 테이블 연결처럼 output으로 노출되지 않는 `network` 모듈의 나머지 리소스는 이 값 참조로는 순서가 전혀 보장되지 않으므로, 이론적으로 다른 모듈의 리소스(EKS 클러스터, EC2 인스턴스 등)가 NAT 게이트웨이보다 먼저 생성 요청될 수 있습니다. 대부분의 경우 실제로 문제가 되지 않지만(AWS API가 병렬 생성을 허용), 프라이빗 서브넷에서 아웃바운드 인터넷이 필요한 리소스(예: NAT 경유 패키지 설치)가 NAT 준비 전에 부팅을 시작하는 등의 타이밍 이슈를 원천적으로 차단하기 위해 `network`는 항상 통째로 먼저 완성되게 만듭니다.

- 이는 22번 패턴(모듈 간 `depends_on`)의 특수 사례이며, `network` 모듈에 대해서는 선택이 아니라 **필수**로 적용합니다.
- `network`의 output을 전혀 쓰지 않는 모듈(예: `key_pair`)에도 동일하게 `depends_on = [module.network]`를 추가해서, 루트의 모든 리소스/모듈이 `network` 완성 이후에만 시작되도록 통일합니다.
- 값 참조가 있는 모듈이든 없는 모듈이든 규칙은 동일합니다: **루트에 `module "network"` 블록이 있는 프로젝트라면, 다른 모든 `module` 블록에 `depends_on = [module.network]`를 추가합니다.**

## 28. 모든 EKS Add-on(`aws_eks_addon`)은 각자 독립된 모듈을 가진다 (`vpc-cni`/`coredns`/`kube-proxy` 포함, 클러스터의 자동 셀프매니지드 설치는 끈다)

EKS는 클러스터를 만들 때 기본적으로 `vpc-cni`, `coredns`, `kube-proxy`를 **셀프매니지드(self-managed)** 애드온으로 자동 설치합니다. 이 상태에서 같은 이름의 `aws_eks_addon` 리소스를 추가로 만들면 "이미 존재하는 리소스와 충돌"이 발생하거나, Terraform이 이 세 애드온의 존재/버전/설정을 전혀 추적하지 못하는 상태(클러스터 콘솔에는 보이지만 상태 파일에는 없음)가 됩니다. 이 셋을 오직 Amazon EKS 애드온(관리형)으로만 존재하게 하려면, `aws_eks_cluster`에 `bootstrap_self_managed_addons = false`를 설정하고 세 개 모두를 `aws_eks_addon`으로 명시적으로 선언합니다.

**일반 원칙: 모든 EKS Add-on은 각자의 모듈을 가진다.** 이 규칙은 `vpc-cni`/`coredns`/`kube-proxy`에만 한정되지 않고, 이후 프로젝트에 추가하는 모든 `aws_eks_addon`(예: `aws-ebs-csi-driver`, `aws-efs-csi-driver`, `aws-mountpoint-s3-csi-driver`, `amazon-cloudwatch-observability`, `adot` 등)에 동일하게 적용합니다. 여러 Add-on을 하나의 모듈에 묶지 않고 `eks_<addon_name_snake_case>_addon`(예: `eks_vpc_cni_addon`, `eks_ebs_csi_driver_addon`) 이름의 모듈을 Add-on 하나당 하나씩 만듭니다. 이유는 세 가지입니다.

1. **생성/업그레이드 순서가 Add-on마다 다를 수 있습니다.** 아래에서 다루는 `coredns`(노드 용량 필요) vs `vpc-cni`/`kube-proxy`(불필요)의 상반된 순서 요구사항이 대표적인 예이지만, 다른 Add-on도 각자 다른 전제조건을 가질 수 있습니다(예: `aws-ebs-csi-driver`는 IRSA 역할이 먼저 있어야 함, `amazon-cloudwatch-observability`는 CloudWatch 네임스페이스/로그그룹이 먼저 있어야 함). 여러 Add-on이 한 모듈에 있으면 그 모듈 전체가 가장 엄격한 선행조건에 맞춰야 하므로, 다른 Add-on들이 불필요하게 늦게 생성됩니다.
2. **버전 관리와 blast radius가 Add-on별로 독립적입니다.** 각 Add-on은 AWS가 서로 다른 시점에 서로 다른 버전을 릴리스합니다(예: `vpc-cni`에만 보안 패치가 나와도 `coredns`/`kube-proxy`는 그대로 두어야 함). 하나의 모듈에 묶여 있으면 `terraform plan`에서 한 Add-on의 버전만 바꿔도 그 모듈의 다른 리소스까지 diff에 섞여 보이고, 실수로 `-target`을 잘못 지정하지 않는 한 항상 다른 Add-on들과 함께 apply/destroy 대상이 됩니다.
3. **`configuration_values`의 JSON 스키마가 Add-on마다 완전히 다릅니다**(23번 패턴). 모듈이 분리되어 있으면 각 모듈의 `variables.tf`가 그 Add-on 고유의 설정 변수만 선언하므로, 스키마가 섞여서 헷갈릴 일이 없습니다.

이 원칙에 따라 `vpc-cni`/`coredns`/`kube-proxy`도 하나의 `eks_addons` 모듈로 묶지 않고 `eks_vpc_cni_addon`/`eks_kube_proxy_addon`/`eks_coredns_addon` 세 모듈로 분리합니다.

```hcl
# modules/eks_cluster/main.tf
resource "aws_eks_cluster" "eks_cluster" {
  # ...
  # Prevents EKS from installing vpc-cni/coredns/kube-proxy as unmanaged
  # self-managed addons at cluster creation, so they are exclusively managed
  # by the aws_eks_addon resources in modules/eks_vpc_cni_addon,
  # modules/eks_kube_proxy_addon, and modules/eks_coredns_addon instead.
  # Changing this value forces cluster replacement.
  bootstrap_self_managed_addons = false
}
```

```hcl
# modules/eks_vpc_cni_addon/main.tf
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"
  # ...
}
```

```hcl
# modules/eks_kube_proxy_addon/main.tf
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"
}
```

```hcl
# modules/eks_coredns_addon/main.tf
resource "aws_eks_addon" "coredns" {
  cluster_name          = var.cluster_name
  addon_name            = "coredns"
  configuration_values  = jsonencode({ replicaCount = var.coredns_replica_count })
}
```

각 모듈은 자신의 애드온 ARN만 output으로 노출합니다(`vpc_cni_addon_arn`/`kube_proxy_addon_arn`/`coredns_addon_arn`). 아래 생성 순서 요구사항이 vpc-cni/kube-proxy와 coredns 사이에 정반대라는 점은, 위 1번 이유(생성/업그레이드 순서가 Add-on마다 다를 수 있음)가 실제로 발생하는 구체적인 사례입니다.

**생성 순서 주의사항 (rules.md #22 적용):**

- `vpc-cni`/`kube-proxy`는 DaemonSet이라 노드가 0개여도 `desired == ready == 0`으로 즉시 `ACTIVE`가 됩니다. 오히려 노드 자체가 클러스터에 Ready로 조인하려면 이 둘이 먼저 존재해야 하므로, `eks_vpc_cni_addon`/`eks_kube_proxy_addon` 모듈은 **노드 생성 리소스(관리형 노드그룹/Fargate profile/Karpenter)보다 먼저** 생성되어야 합니다. `bootstrap_self_managed_addons = false`인 클러스터에서는 이 둘이 존재하기 전에는 워커 노드가 정상적으로 조인할 수 없습니다.
- `coredns`는 Deployment(파드)이므로 스케줄될 수 있는 노드 용량이 있어야 `DEGRADED` 상태를 벗어나 `ACTIVE`가 됩니다. 노드 용량 없이 `coredns` 애드온을 먼저 만들면 `Error: ... timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)`로 실패합니다 (`terraform-aws-modules/terraform-aws-eks`의 [#3062](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3062), [#2069](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2069)에 보고된 것과 동일한 증상). 따라서 `eks_coredns_addon` 모듈은 관리형 노드그룹을 쓰는 프로젝트라면 `depends_on = [module.eks_node_group]`을, Fargate profile을 쓰는 프로젝트(19번 패턴)라면 `depends_on = [module.eks_fargate_profile]`을 걸어서 **노드 생성 리소스보다 나중에** 생성되게 합니다.
- 정리하면 한 프로젝트 안에서의 순서는 `eks_cluster` → `eks_vpc_cni_addon`/`eks_kube_proxy_addon` → 노드 생성 리소스(`eks_node_group`/`eks_fargate_profile`/Karpenter) → `eks_coredns_addon`입니다. Karpenter처럼 노드를 만드는 컨트롤러 자체가 CoreDNS에 의존해 동작하는 경우(22번 패턴)는 `eks_coredns_addon` 뒤에 오도록 순서가 한 번 더 꼬일 수 있으니, 실제로 무엇이 무엇을 필요로 하는지 프로젝트별로 확인합니다.

```hcl
# 루트 main.tf
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # vpc-cni is a DaemonSet and becomes ACTIVE with zero nodes, so it's
  # created before any node capacity exists - nodes need it running to
  # join the cluster in a Ready state.
  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and
  # must exist before any node capacity exists.
  depends_on = [module.network, module.eks_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"
  # ...

  # Nodes need vpc-cni/kube-proxy running to join the cluster Ready.
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave
  # its DEGRADED state and become ACTIVE.
  depends_on = [module.eks_node_group]
}
```

- **기존에 이미 셀프매니지드 애드온이 설치된 클러스터**(예: `bootstrap_self_managed_addons`의 기본값 `true`로 만들어진 클러스터)에 이 패턴을 나중에 도입하는 경우, `resolve_conflicts_on_create = "OVERWRITE"`로 기존 셋업을 관리형 애드온으로 흡수(migrate)시킵니다. `NONE`으로 두면 기존 리소스와 충돌해 생성이 실패합니다.
- `bootstrap_self_managed_addons` 값을 변경하면 **클러스터 자체가 destroy 후 재생성**됩니다 (Terraform 문서에 `Changing this value will force a new cluster to be created`로 명시). 이미 apply된 클러스터에 이 패턴을 적용할 때는 반드시 먼저 `terraform plan`으로 클러스터 교체 여부를 확인하고, 되돌릴 수 없는 작업임을 사용자에게 알린 뒤 진행합니다. 신규 프로젝트라면 처음부터 `false`로 시작하는 것이 안전합니다.

## 29. `kubectl_manifest`는 EKS 클러스터가 아니라 그 매니페스트가 실제로 의존하는 노드 리소스에 `depends_on`을 걸어서, `terraform destroy`가 apply의 정확한 역순으로 진행되게 한다

26번 패턴처럼 EKS 클러스터와 `kubectl_manifest` 리소스를 같은 루트 모듈, 같은 `apply`에서 함께 만드는 경우, `provider "kubectl"`은 `module.eks_cluster.cluster_endpoint`/`certificate_authority_data`를 참조하지만 이는 **provider 설정값 참조**일 뿐이라 리소스 레벨 의존관계만큼 강하게 Terraform 그래프에 반영되지 않습니다. `kubectl_manifest` 리소스 자체에 `depends_on`이 없으면 `terraform destroy`가 EKS 클러스터(또는 그 노드 리소스)를 CRD/매니페스트보다 먼저 삭제하려고 시도할 수 있고, 그 순간부터 API 서버가 이미 사라졌거나(클러스터 삭제) 컨트롤러 파드가 이미 죽어서(노드 삭제) `kubectl_manifest`의 삭제 자체가 실패합니다.

```
Error: default/default-sgp failed to create kubernetes rest client for update of resource: Get "https://....eks.amazonaws.com/api?timeout=32s": dial tcp 10.0.0.101:443: i/o timeout
```

이 에러는 클러스터가 아직 있어도 그 클러스터에 파드를 실제로 실행하던 노드(관리형 노드그룹/Fargate profile/Karpenter)가 이미 사라졌을 때도 발생합니다. `SecurityGroupPolicy`처럼 컨트롤러가 관리하는 CRD는 그 컨트롤러가 이미 죽은 뒤에는 정상적으로 지워지지 않을 수 있고, finalizer가 걸린 리소스는 컨트롤러 없이 삭제 요청을 보내면 finalizer 제거를 영원히 기다리며 멈춥니다. 노드 리소스가 CRD보다 먼저 destroy되면 이 상황이 재현됩니다.

이 문제는 EKS 클러스터 자체를 향한 `depends_on`으로는 해결되지 않습니다. 클러스터가 있어도 노드가 없으면 여전히 실패하기 때문입니다. `kubectl_manifest` 리소스가 실제로 필요로 하는 런타임 리소스, 즉 **그 매니페스트를 실행/처리할 컨트롤러가 스케줄되는 노드 리소스**(`module.eks_node_group`, `aws_eks_fargate_profile`, Karpenter의 `helm_release` 등)를 `depends_on`에 명시해야, `terraform destroy`가 apply 때와 정확히 반대 순서로(노드 리소스보다 먼저 CRD/매니페스트를 삭제) 진행됩니다.

```hcl
# modules/pod_security_group_policy/main.tf
resource "kubectl_manifest" "default_sgp" {
  yaml_body = yamlencode({
    apiVersion = "vpcresources.k8s.aws/v1beta1"
    kind       = "SecurityGroupPolicy"
    # ...
  })

  # This CRD's SecurityGroupPolicy is enforced by the vpc-resource-controller
  # pod running on a worker node; without this, `terraform destroy` can try
  # to delete the node group before this manifest, leaving the delete stuck
  # waiting on a controller that no longer exists (rules.md #29).
  depends_on = [var.node_group_dependency]
}
```

- 모듈이 노드 리소스의 존재를 직접 알지 못하게 하려면(15번 패턴), 노드 리소스를 가리키는 값을 루트에서 `depends_on`용 변수로 주입하지 않고, **루트 `main.tf`의 `module` 블록 자체에 `depends_on`을 겁니다** (12/22번 패턴과 동일한 방식 - 모듈 내부 리소스 각각이 아니라 모듈 경계에서 순서를 표현).

```hcl
# 루트 main.tf
module "pod_security_group_policy" {
  source = "./modules/pod_security_group_policy"

  vpc_id          = module.network.vpc_id
  create_demo_pod = var.create_demo_pod

  # default_sgp/demo_pod (kubectl_manifest) need a live vpc-resource-
  # controller pod, which runs on the node group; ordering the module
  # itself after the node group makes `terraform destroy` remove these
  # manifests before the node group disappears (rules.md #29).
  depends_on = [module.network, module.eks_node_group]
}
```

- 노드 리소스가 여러 개(예: 004번 프로젝트처럼 Fargate profile과 Karpenter가 함께 있는 경우)라면, 그 매니페스트가 스케줄되는 **구체적인 노드 리소스**를 `depends_on`에 넣습니다. 막연히 "가장 마지막에 만들어지는 모듈"을 넣지 않고, 실제로 어떤 컨트롤러/파드가 이 매니페스트를 처리하는지부터 확인합니다.
- 이 규칙은 `eks_vpc_cni_addon`/`eks_kube_proxy_addon`/`eks_coredns_addon`을 포함한 모든 Add-on 모듈(28번 패턴)의 `aws_eks_addon` 리소스에는 적용되지 않습니다. `aws_eks_addon`은 AWS 프로바이더가 EKS API로 직접 삭제를 요청하는 리소스라 클러스터의 API 서버나 컨트롤러 파드에 별도로 접속할 필요가 없기 때문입니다. 이 규칙은 오직 **클러스터 내부의 Kubernetes API 서버로 직접 요청을 보내는** `kubectl_manifest`(및 26번 패턴이 대체하기 전의 `kubernetes_manifest`/`kubernetes_annotations` 등 `hashicorp/kubernetes` 타입드 리소스 전체)에만 적용됩니다.

