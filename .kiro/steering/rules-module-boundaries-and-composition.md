---
inclusion: always
---

# Module Boundaries and Composition Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-variables-and-interfaces.md`](rules-variables-and-interfaces.md) · **Next:** [`rules-resource-ordering-and-destruction.md`](rules-resource-ordering-and-destruction.md)
> 논리 인용 `rules.md C-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| C-1 | 클러스터와 principal을 서로 무관한 모듈이 소유할 때 | 루트가 두 output을 조합해 EKS 접근 권한을 만들고, 컴포넌트 고유 권한은 컴포넌트가 소유할 수 있다 | B-6, E-6 |
| C-2 | IRSA 컨트롤러를 설치할 때 | runner가 API 서버에 도달하면 IAM 역할과 Helm 릴리스를 함께 두고, runner는 못 닿지만 VPC 관리 인스턴스가 도달하면 AWS 전용 모듈과 SSM 설치로 나눈다 | E-1, E-9 |
| C-3 | `network` 모듈이 서브넷을 노출할 때 | EKS는 최소 2 AZ를 쓰고, 고정형은 개별+배열, 동적형은 zone map+배열 output을 제공한다 | B-6, D-3 |
| C-4 | `aws_eks_addon`을 선언할 때 | Add-on마다 독립 모듈을 만들고 bootstrap·노드 준비 순서를 명시한다 | C-2, D-2, E-5 |

## C. 모듈 경계와 조립

무엇을 한 모듈에 넣고 무엇을 루트에서 잇는지에 관한 규칙입니다.

### C-1. 서로 무관한 모듈이 소유한 principal의 EKS 접근 권한은 루트에서 조립

**EKS 클러스터와 IAM principal을 서로 무관한 모듈이 각각 소유하면 루트가 두 output을 조합해 접근 권한을 선언합니다.** 관리용 EC2 역할처럼 클러스터 컴포넌트와 독립적인 principal을 `eks_cluster`나 `vscode_ec2` 모듈 안에 억지로 넣지 않습니다.

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

이렇게 하면 `eks_cluster`는 어떤 외부 주체에게 접근을 줄지 모르고, `vscode_ec2`는 EKS 클러스터의 존재를 모릅니다. 두 책임을 연결하는 루트만 양쪽 output을 압니다.

이 규칙은 모든 `aws_eks_access_entry`를 무조건 루트에 두라는 뜻이 아닙니다. 컨트롤러·노드 프로비저너처럼 **한 컴포넌트가 principal을 만들고 그 컴포넌트의 동작 자체에 EKS 접근이 필수**라면, 접근 엔트리도 같은 컴포넌트 모듈이 소유할 수 있습니다. 이 경우 모듈은 외부 클러스터의 이름을 입력으로 받고 자신이 소유한 역할 ARN을 직접 참조합니다. 컴포넌트를 제거할 때 역할과 접근 엔트리가 함께 사라지는 것이 올바른 수명주기입니다.

판정 기준은 리소스 타입이 아니라 소유권입니다. **서로 무관한 두 소유자를 잇는 권한은 루트 조립, 하나의 컴포넌트에 고유한 권한은 컴포넌트 소유**입니다. principal이 서비스 연결 역할이면 Access Entry 자체를 지원하지 않을 수 있으므로 E-6번의 별도 경로도 확인합니다.

### C-2. IRSA 컨트롤러는 IAM 역할과 Helm 릴리스를 같은 모듈에 둔다

**Terraform의 Helm provider가 클러스터 API에 접근할 수 있는 구성에서는 IRSA 역할과 그 역할을 사용하는 Helm 릴리스를 같은 컴포넌트 모듈에 둡니다.** Karpenter처럼 역할 ARN이 차트 값에 직접 들어가고 릴리스가 정책 attachment를 기다리는 관계는 분리할수록 입력과 순서만 늘어나는 강결합입니다.

endpoint의 public/private 값만으로 모듈 경계를 정하지 않습니다. Terraform이 관리할 내부 객체의 유무와 runner의 실제 API 도달성이 설치 위치를 결정합니다(E-9).

| Terraform이 관리할 내부 객체 | runner의 API 도달성 | VPC 관리 인스턴스의 API 도달성 | Kubernetes 설치 위치 | 모듈 경계 |
| --- | --- | --- | --- | --- |
| 있음 | 도달 | 관계없음 | Terraform runner의 `helm_release` | IRSA 역할·정책·Helm 릴리스를 같은 컴포넌트 모듈에 둔다 |
| 있음 | 도달하지 못함 | 도달 | 관리 인스턴스의 SSM Association | AWS 전용 모듈은 IAM 역할·정책만 소유하고, 차트 설치는 SSM 단계가 맡는다 |
| 있음 | 도달하지 못함 | 도달하지 못함 | 유효한 설치 위치 없음 | 모듈을 선택하기 전에 DNS·네트워크 경로를 확보한다 |
| 없음 | 관계없음 | 관계없음 | provider와 SSM 설치 단계 모두 없음 | 필요한 AWS 리소스만 그 소유권에 맞는 모듈에 둔다 |

private endpoint도 runner가 VPC, VPN, Direct Connect, 피어링과 올바른 DNS·라우팅 경로를 통해 도달하면 첫 번째 행입니다. public endpoint라도 runner에서 차단되고 지정한 VPC 관리 인스턴스만 도달하면 두 번째 행입니다. 두 번째 행에서만 AWS 전용 모듈의 `required_providers`에 `aws`만 남기고 차트 전용 변수와 `helm_release`를 제거합니다. `install_chart = false` 토글은 릴리스를 만들지 않아도 `helm` provider 요구사항을 남기므로 SSM 예외를 해결하지 못합니다.

provider가 접근 가능한 기본 형태는 다음과 같습니다.

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

- `helm_release`는 같은 모듈이 소유한 역할 ARN을 변수로 되받지 않고 `aws_iam_role`을 직접 참조합니다.
- B-6번의 외부 식별자 주입과 C-1번의 루트 조립은 **서로 다른 소유자의 경계**에 적용합니다. 여기서는 IAM과 Helm이 하나의 컨트롤러를 이루므로 같은 모듈이 맞습니다.
- provider 접근이 가능한 이 모듈의 `providers.tf`는 `aws`와 `helm`의 `required_providers`를 모두 선언하되 provider 구성 블록은 두지 않습니다(A-2).
- IRSA 대신 Pod Identity로 전환하는 등 역할이 필요한 이유가 사라지면 컴포넌트 모듈 하나를 교체하면 됩니다. "컨트롤러 설치에 필요한 것"을 한 경계에 모으는 목적입니다.

### C-3. `network` 모듈은 토폴로지에 맞는 zone별 output과 전체 ID 배열을 함께 노출한다

**먼저 필요한 AZ 수와 NAT 토폴로지를 정하고, 그 다음 서브넷 선언 방식에 맞는 상세 output과 공통 배열 output을 제공합니다.** 두 결정은 독립적입니다.

#### AZ 수와 NAT 토폴로지는 별도 결정입니다

Amazon EKS 클러스터에 넘기는 서브넷은 **최소 두 개의 서로 다른 Availability Zone**에 있어야 합니다. 세 AZ는 EKS의 최소 요구사항이 아니라 더 높은 장애 격리와 용량 선택지를 위한 프로젝트 결정입니다. 기본 VPC·EC2 데모(`014_basic_ec2`, `015_basic_vpc_and_subnets`)처럼 두 AZ면 충분한 프로젝트에 기계적으로 세 번째 AZ를 추가하지 않습니다.

AZ 수가 NAT Gateway 수를 자동으로 정하지도 않습니다.

- AZ별 NAT Gateway는 한 AZ 장애가 다른 private subnet의 egress를 함께 끊지 않게 하지만, AZ마다 고정 비용이 듭니다.
- 공유 NAT Gateway 하나는 데모 비용을 줄이지만 단일 장애 지점과 cross-AZ 데이터 경로를 만듭니다.
- 2-AZ/3-AZ 선택과 single-NAT/per-AZ-NAT 선택을 각각 명시하고, 가용성과 비용의 이유를 모듈 주석에 남깁니다.

#### output 모양은 서브넷 선언 방식에 맞춥니다

| 서브넷 선언 | 상세 output | 공통 output |
| --- | --- | --- |
| `public_subnet_a`처럼 고정 리소스 | `public_subnet_a_id` 같은 개별 ID | `public_subnet_ids`, `private_subnet_ids` 배열 |
| zone 키의 `for_each`로 동적 생성 | `public_subnet_ids_by_zone` 같은 zone map | `public_subnet_ids`, `private_subnet_ids` 배열 |

고정형은 특정 AZ 하나를 고르는 호출자를 위해 개별 output을 유지하면서 전체 배열도 제공합니다.

```hcl
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet in availability zone A"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id, aws_subnet.public_subnet_c.id]
  description = "IDs of all public subnets"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  description = "IDs of all private subnets"
}
```

동적형은 존재하지 않을 수 있는 A/B/C 이름을 억지로 만들지 않고 zone map과 배열을 함께 제공합니다. zone map은 특정 AZ 선택을, 배열은 모든 서브넷 전달을 담당합니다.

```hcl
output "public_subnet_ids_by_zone" {
  value       = { for zone, subnet in aws_subnet.public : zone => subnet.id }
  description = "Public subnet IDs keyed by availability zone"
}

output "public_subnet_ids" {
  value       = values({ for zone, subnet in aws_subnet.public : zone => subnet.id })
  description = "IDs of all public subnets"
}
```

호출자는 선언 방식과 무관하게 전체 배열 이름을 사용합니다.

```hcl
# 루트 main.tf — EKS 클러스터는 전체 서브넷, 노드그룹은 private 서브넷만 필요
module "eks_cluster" {
  subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
}

module "eks_node_group" {
  subnet_ids = module.network.private_subnet_ids
}
```

이 배열에 다른 모듈의 unknown subnet ID가 들어 있어도 일반 인수로 전달하는 것은 유효합니다. B-8번의 map 요구사항은 그 ID 자체를 `for_each` 인스턴스 키로 쓸 때만 적용됩니다.

### C-4. 모든 EKS Add-on은 각자 독립된 모듈을 가진다 (`vpc-cni`/`coredns`/`kube-proxy` 포함)

**`aws_eks_addon` 하나당 모듈 하나를 만들고, 기본 self-managed Add-on은 신규 클러스터에서 처음부터 끕니다.**

EKS는 클러스터를 만들 때 기본적으로 `vpc-cni`, `coredns`, `kube-proxy`를 self-managed Add-on으로 설치합니다. 같은 이름의 `aws_eks_addon`을 나중에 선언하면 기존 Kubernetes 리소스와 충돌하거나, 콘솔에는 있지만 Terraform state가 추적하지 않는 상태가 됩니다. 이 셋을 Amazon EKS Add-on으로만 관리하려면 신규 `aws_eks_cluster`에 `bootstrap_self_managed_addons = false`를 설정하고 세 Add-on을 각각 명시적으로 선언합니다.

이 규칙은 이후 추가하는 `aws-ebs-csi-driver`, `aws-efs-csi-driver`, `aws-mountpoint-s3-csi-driver`, `amazon-cloudwatch-observability`, `adot` 등에도 동일합니다. 여러 Add-on을 `eks_addons` 하나에 묶지 않고 `eks_<addon_name_snake_case>_addon` 모듈 하나씩 둡니다. 다만 Add-on 전용 IAM 역할처럼 **그 Add-on에 강하게 결합된 지원 리소스는 같은 Add-on 모듈이 소유할 수 있습니다**(C-2).

분리하는 이유는 세 가지입니다.

1. **생성·업그레이드 순서가 다릅니다.** 아래의 `coredns`와 `vpc-cni`/`kube-proxy`가 반대 순서를 요구하며, `aws-ebs-csi-driver`는 IAM 역할 같은 별도 선행조건을 가질 수 있습니다. 묶으면 모든 Add-on이 가장 엄격한 조건까지 불필요하게 기다립니다.
2. **버전과 blast radius가 독립적입니다.** `vpc-cni` 보안 패치만 적용해도 `coredns`와 `kube-proxy`는 그대로 둘 수 있어야 합니다. 모듈을 묶으면 한 Add-on의 diff와 수명주기가 다른 Add-on에 섞입니다.
3. **`configuration_values` 스키마가 완전히 다릅니다**(E-5). Add-on별 `variables.tf`에 그 Add-on의 설정만 두어 타입과 스키마를 섞지 않습니다.

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
  cluster_name         = var.cluster_name
  addon_name           = "coredns"
  configuration_values = jsonencode({ replicaCount = var.coredns_replica_count })
}
```

각 Add-on 모듈은 **최소한 자신의 Add-on ARN**을 output으로 노출하고, 호출자가 필요로 하는 자신 소유 리소스의 output(예: 전용 IAM 역할 ARN)도 함께 노출합니다. 다른 Add-on이나 외부 컴포넌트의 값을 대신 재노출하지 않습니다. `vpc_cni_addon_arn`, `kube_proxy_addon_arn`, `coredns_addon_arn`처럼 이름으로 소유자를 드러냅니다.

#### 생성 순서 주의사항 (`rules.md D-2` 적용)

- `vpc-cni`와 `kube-proxy`는 DaemonSet이므로 노드가 0개여도 `desired == ready == 0`으로 즉시 `ACTIVE`가 됩니다. 오히려 워커가 Ready로 조인하려면 이 둘이 먼저 존재해야 하므로, 두 Add-on 모듈은 관리형 노드그룹·Fargate profile·기타 노드 용량보다 먼저 생성합니다. `bootstrap_self_managed_addons = false`인 클러스터에서는 이 Add-on 없이 워커가 정상 조인할 수 없습니다.
- `coredns`는 Deployment이므로 스케줄 가능한 노드 용량이 있어야 `DEGRADED`에서 `ACTIVE`가 됩니다. 노드 없이 먼저 만들면 `Error: ... timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)`로 실패합니다. 이는 `terraform-aws-modules/terraform-aws-eks`의 [#3062](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3062), [#2069](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2069)에 보고된 증상과 같습니다. 관리형 노드그룹이면 `depends_on = [module.eks_node_group]`, Fargate profile이면 `depends_on = [module.eks_fargate_profile]`로 **노드 용량 뒤에** 둡니다. 이는 모듈 순서를 표현하는 D-2번 사례이며 E-4번의 기존 파드 rollout 트리거와는 다른 문제입니다.
- 기본 순서는 `eks_cluster` → `eks_vpc_cni_addon`/`eks_kube_proxy_addon` → 노드 용량 → `eks_coredns_addon`입니다. Karpenter 컨트롤러처럼 자체 구동에 DNS와 bootstrap 용량이 필요한 컴포넌트는 이 단순 사슬로 해결되지 않을 수 있으므로 실제 bootstrap 경로를 확인해 순서를 정합니다.

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

#### 기존 클러스터에 도입할 때는 adoption과 cluster replacement를 구분합니다

- self-managed Add-on이 이미 있는 클러스터에 `aws_eks_addon`을 추가할 때 `resolve_conflicts_on_create = "OVERWRITE"`를 사용하면 기존 Kubernetes 리소스를 관리형 Add-on으로 흡수할 수 있습니다. `NONE`이면 기존 리소스와 충돌해 생성이 실패합니다.
- 이 adoption은 `bootstrap_self_managed_addons` 값을 바꾸지 않습니다. 이미 생성된 클러스터의 값을 `true`에서 `false`로 변경하면 **클러스터 자체가 destroy 후 재생성**됩니다. `OVERWRITE`를 무중단으로 bootstrap 플래그까지 전환하는 수단처럼 설명하지 않습니다.
- 기존 state에 이 패턴을 도입할 때는 Add-on adoption만 할지 클러스터 교체까지 할지 먼저 결정하고 `terraform plan`에서 replacement를 확인합니다. 교체는 되돌릴 수 없는 영향을 알린 뒤 진행하며, 신규 프로젝트는 처음부터 `false`로 시작합니다.
