---
inclusion: always
---

# Variable and Interface Design Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-repository-structure-and-conversion.md`](rules-repository-structure-and-conversion.md) · **Next:** [`rules-module-boundaries-and-composition.md`](rules-module-boundaries-and-composition.md)
> 논리 인용 `rules.md B-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| B-1 | `type`보다 좁은 형식·범위·조합 제약이 있을 때 | 제약을 `validation`으로 강제하되 unknown 값은 apply까지 미뤄질 수 있음을 전제한다 | B-2, F-1 |
| B-2 | AWS가 허용값을 열거한 변수 | 정규식이 아니라 `contains()`로 enum을 검증한다 | B-1 |
| B-3 | 사용자가 루트에서 조정할 리터럴 | 기본값 있는 변수로 승격하고 프로토콜·변형 불변값은 리터럴이나 `local`로 둔다 | B-1, B-5 |
| B-4 | 선택적 기능을 모듈 인터페이스로 노출할 때 | nullable 입력과 템플릿 조건으로 기능을 생략 가능하게 한다 | A-1, H-2 |
| B-5 | 모듈 입력을 호출자의 다른 리소스도 써야 할 때 | 모듈 output으로 재노출해 값을 다시 적지 않는다 | H-2 |
| B-6 | 모듈이 외부 소유 리소스를 사용해야 할 때 | 모듈에서 조회하지 않고 cardinality에 맞는 식별자 입력을 받는다 | B-8, C-1 |
| B-7 | 역할에 여러 plan-known 관리형 정책을 붙일 때 | ARN 목록을 `toset()`한 단일 `for_each` attachment로 관리한다 | B-8 |
| B-8 | unknown 값이 `for_each` 인스턴스 식별자가 될 수 있을 때 | plan-known이고 안정적인 키의 `map`을 사용하고 unknown은 값에만 둔다 | B-6, F-2 |

## B. 변수와 인터페이스 설계

모듈과 루트가 값을 주고받는 방법입니다. 두 축으로 정리됩니다.

**잘못된 값을 가능한 한 이른 단계에서 막는다** — B-1번이 원칙이고 B-2번(열거형)과 F-1번(보안 그룹 문자셋)이 구체 사례입니다. Terraform이 값을 알고 있으면 `plan`에서 막고, 리소스 output처럼 아직 unknown이면 검증이 `apply`까지 미뤄질 수 있습니다. 위반 결과가 AWS API, 컨트롤러, 부팅 스크립트에서만 드러나는 값일수록 이 축의 가치가 큽니다.

**값을 한 곳에만 둔다** — B-3번은 사용자가 조정할 루트 값을 변수로 올리고, B-5번은 모듈이 받은 값을 output으로 되돌려 호출자가 다시 적지 않게 하며, H-2번은 output과 README가 하나의 맵을 보게 합니다. 값이 두 곳에 있으면 어긋나고, 어긋난 것을 `apply`는 알려주지 않습니다.

### B-1. `type`만으로 표현되지 않는 변수 제약은 `validation`으로 강제

**변수의 실제 유효 범위가 선언한 `type`보다 좁을 때 `validation`을 추가합니다.** 리소스 ID 형식, CIDR, 비어 있지 않은 이름, enum, 포트 범위, 변수 간 조합처럼 타입만으로 표현되지 않는 제약이 대상입니다.

`bool`의 `true`와 `false`가 모두 유효하다면 `type = bool`만으로 충분합니다. `condition = var.flag == true || var.flag == false` 같은 항진식은 아무 값도 추가로 거르지 않으므로 만들지 않습니다. 반대로 특정 변형에서 `true`만 유효하면 그것은 타입보다 좁은 **변형 불변조건**이므로 `validation`이 필요합니다.

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

- 리소스 ID(`vpc-*`, `subnet-*`, `ami-*`)는 해당 접두사와 허용 문자 형식을 검증합니다.
- CIDR은 `can(cidrhost(var.x, 0))`으로 검증합니다.
- 빈 문자열이 실제로 무효인 이름·문자열은 `length(var.x) > 0`으로 막습니다. 빈 값도 의미가 있는 문자열에는 기계적으로 붙이지 않습니다.
- nullable 입력은 `var.x == null || ...`처럼 `null`을 유효한 선택에 포함합니다.
- enum은 B-2번대로 `contains()`를 사용하고, 변수 간 관계는 교차 변수 조건으로 표현합니다.

검증은 Terraform이 피연산자를 아는 가장 이른 시점에 평가됩니다. 루트 입력처럼 plan-known 값은 보통 `plan`에서 실패하지만, 다른 리소스나 모듈의 output이 입력에 들어와 unknown이면 해당 조건은 값이 알려지는 `apply`까지 미뤄질 수 있습니다. 따라서 `validation`은 **가능한 경우 plan에서 차단하는 선언적 경계**이지, 모든 입력 오류가 반드시 plan에서 끝난다는 보장은 아닙니다.

#### `description`에 쓴 제약은 강제되지 않습니다

"Must stay true", "이 변형에서는 ip만" 같은 문장을 설명에만 적어두면 아무것도 막지 못합니다. 이런 문장은 타입보다 좁은 실제 제약이 있는지 확인해야 한다는 신호입니다. 특히 위반 결과가 Terraform 밖의 AWS API, Kubernetes 컨트롤러, 부팅 스크립트에서만 드러나면 `plan`은 깨끗하게 통과하고 실패는 한참 뒤에 전혀 다른 모습으로 나타납니다.

```hcl
# 이것만으로는 아무도 막지 못합니다
variable "enable_backend_security_group" {
  description = "... Must stay true in this variant ..."
}

# 이 변형에서 true만 유효하므로 제약을 실제로 강제합니다
variable "enable_backend_security_group" {
  type    = bool
  default = true

  validation {
    condition     = var.enable_backend_security_group
    error_message = "enable_backend_security_group must be true in this variant, because ... (rules.md G-2)."
  }
}
```

- **다른 변수를 참조하는 `validation`을 사용할 수 있습니다.** 모듈화된 루트와 모듈의 기준은 `required_version = ">= 1.9"`이므로 "A가 켜져 있으면 B는 true" 같은 조합을 조건에 그대로 적습니다. 각 변수를 따로 검증해서는 표현할 수 없는 제약입니다.

```hcl
variable "enable_backend_security_group" {
  type    = bool
  default = false

  validation {
    # Cross-variable condition, available since Terraform 1.9. The constraint is
    # about the pair, not about either value on its own.
    condition     = var.manage_backend_security_group_rules ? var.enable_backend_security_group : true
    error_message = "enable_backend_security_group must be true when manage_backend_security_group_rules is true, because the controller rejects that combination otherwise (rules.md G-2)."
  }
}
```

- **상수 방향 조건(`condition = var.x`)도 실제 불변조건이면 유효합니다.** 특정 변형이 `true`만 지원하는 G-2번 사례가 그렇습니다. 두 bool 값이 모두 유효한데 형식적으로만 넣는 항진식과 구분합니다.
- `_monolithic/` 원본은 각 파일이 생성될 때의 버전 선언을 그대로 보존하며 실제로 `>= 1.5`와 `>= 1.9`가 모두 존재합니다. 조회 전용이므로 일괄 수정하지 않고, 원본을 분석할 때도 저장소의 현재 `>= 1.9` 기준을 소급 가정하지 않습니다.
- 조건이 변형마다 다른 것은 정상입니다. 같은 변수가 한 변형에서는 `false`만, 다른 변형에서는 `true`만 유효할 수 있고, 각 루트가 자기 모듈을 독립적으로 소유하므로(A-1번) 서로 다른 `validation`을 가질 수 있습니다.
- `error_message`에는 유효한 대안을 함께 적습니다. "이 값은 안 된다"로 끝내지 말고, 그 값을 쓰려면 무엇을 함께 바꾸거나 어느 변형을 참고해야 하는지 가리킵니다.
- 애초에 **잘못된 조합을 표현할 수 없게 만드는 것**이 가장 낫습니다. 값이 다른 입력에서 유도되면 변수로 두지 말고 `local`로 파생시킵니다(G-1번의 ALB Service 타입이 이 경우).
- 아래 감사는 위반 확정 목록이 아니라 **후보 목록**입니다. 설명에 제약 문장이 있는 파일을 찾은 뒤, 실제로 타입보다 좁은 제약인지와 대응 `validation`이 없는지를 사람이 확인합니다.

```bash
# description에 "must stay" 류 문장이 있는 validation 후보 찾기
grep -rl --include=variables.tf 'must stay\|Must stay' . | while read f; do
  echo "candidate: $f"
done
```

### B-2. AMI 타입 등 AWS가 정한 고정된 열거값은 `contains()`로 검증

B-1번의 구체 사례입니다. 문자열 타입만으로는 AWS가 정한 허용값 집합을 표현할 수 없으므로, `ami_type`, `capacity_type` 같은 enum은 정규식이 아니라 `contains([...], var.x)`로 검증합니다.

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

### B-3. 사용자가 조정할 루트 리터럴은 변수로 승격

**환경·배포마다 사용자가 바꿀 수 있어야 하는 루트 값은 기본값 있는 변수로 승격합니다.** `name = "vscode"`, `instance_type = "t3.small"`, `key_name = "ec2-keypair"`처럼 이름, 크기, 운영 선택에 해당하는 값을 `module` 블록에 직접 박아두면 변형별 변경에 코드 수정이 필요합니다. 루트 `variables.tf`로 올리면 `.tfvars`만으로 오버라이드할 수 있습니다.

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

모든 리터럴을 변수로 만들지는 않습니다.

- provider나 API 프로토콜이 정한 상수(`addon_name = "vpc-cni"`, 리소스 `type`, 고정 애노테이션 키), 모듈 `source`, 이 변형의 정체성을 이루는 불변값은 리터럴이나 `local`로 둡니다. 바꿀 수 없는 값을 변수로 노출하면 잘못된 구성을 표현할 수 있게 됩니다.
- 다른 입력에서 결정되는 값은 변수 대신 `local`로 파생합니다(B-1번). 같은 사실을 호출자에게 다시 적게 하지 않습니다.
- 변형 불변값을 호환성 때문에 입력으로 유지해야 한다면 B-1번의 `validation`으로 유일한 유효값을 강제하고 이유와 대안을 적습니다.

판정 질문은 "리터럴인가"가 아니라 **"사용자가 코드 변경 없이 조정해야 하는 선택인가"**입니다.

### B-4. 선택적 기능은 nullable 변수 + 템플릿 디렉티브로 구현

**일부 호출자만 필요한 기능은 필수 입력으로 만들지 않습니다.** 각 루트가 독립적으로 소유한 모듈에서 기본값 `null`인 선택적 변수를 노출하고, heredoc의 `%{ if ... }` 템플릿 디렉티브로 해당 부분만 렌더링합니다.

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
  ${var.additional_user_data}
  # 마커는 항상 스크립트의 가장 마지막에 생성합니다. additional_user_data보다
  # 먼저 touch하면 아직 kubectl/helm 설치가 돌고 있는 중에 이 마커를 기다리던
  # SSM Association이 출발합니다 (H-2번 패턴).
  %{ if var.marker_file_path != null ~}
  mkdir -p ${var.marker_file_path}
  touch ${var.marker_file_path}/userdata
  %{ endif ~}
  EOT
```

이 기능이 필요 없는 `cloud_init_status` 변형은 `marker_file_path`를 넘기지 않아도 되고, 모듈은 특정 변형의 존재를 알 필요가 없습니다. 다중 루트에서 각 모듈 사본을 독립적으로 소유한다는 A-1번과 선택적 인터페이스라는 이 규칙은 서로 다른 문제입니다.

### B-5. 모듈 입력을 그대로 모듈 출력으로 되돌려주는 패턴 (단일 진실 공급원)

**모듈이 받은 경로·이름을 호출자의 다른 리소스도 써야 하면 모듈 output으로 그대로 재노출합니다.** 루트의 `local`이나 하드코딩 값으로 양쪽에 다시 적지 않습니다.

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

값이 한 곳(`var.marker_file_path`)에서만 정의되고 모듈 input/output을 거쳐 전파됩니다. 두 곳에서 독립적으로 관리하다 어긋나는 문제를 구조적으로 막습니다.

### B-6. 외부 리소스는 조회하지 말고 식별자를 입력으로 주입

**모듈이 다른 모듈이나 루트가 소유한 리소스를 써야 하면 내부에서 이름으로 조회하지 않고 호출자가 ID·ARN·이름을 입력으로 전달합니다.** 모듈은 식별자의 출처나 리소스 종류의 상위 맥락을 몰라도 됩니다.

입력 형태는 외부 리소스라는 이유가 아니라 cardinality와 소비 방식으로 정합니다.

| 필요 형태 | 입력 타입 | 예 |
| --- | --- | --- |
| 정확히 하나 | `string` | `vpc_id`, `cluster_arn` |
| 0개 이상이고 일반 인수로 함께 전달 | `list(string)` | EC2에 추가로 붙일 보안 그룹 ID |
| 0개 이상이고 각 항목에 안정적인 식별자가 필요 | `map(string)` | unknown ID를 값으로 둔 `for_each` 입력(B-8) |

다음 예시는 여러 추가 보안 그룹을 EC2의 일반 인수에 병합하므로 리스트가 맞습니다.

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

모듈 자신의 기본 보안 그룹은 모듈이 만들고 외부에서 추가할 그룹만 입력으로 받습니다. 이 리스트를 그대로 `for_each` 인스턴스 키로 바꿔야 한다면 값의 출처와 무관하게 B-8번의 plan-known 키 요구사항을 다시 적용합니다.

### B-7. 여러 개의 IAM 관리형 정책은 `for_each`로 attach

**역할 하나에 여러 관리형 정책을 붙일 때 attachment 블록을 번호로 복제하지 않고 ARN 컬렉션을 반복합니다.**

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

호출자는 모듈을 수정하지 않고 정책을 추가하거나 제거할 수 있습니다.

이 예에서 `toset(list)`이 유효한 이유는 기본 ARN과 오버라이드 값이 `plan`에서 알려져 **집합 원소 자체를 리소스 주소 키로 확정할 수 있기 때문**입니다. 다른 리소스의 아직 unknown인 속성이 원소가 되면 값이 곧 키인 집합을 사용할 수 없습니다. 그 컬렉션을 `for_each`에 써야 할 때는 B-8번대로 plan-known 키의 맵을 사용합니다.

### B-8. unknown 값을 `for_each`로 반복할 때는 plan-known 안정 키의 `map`을 사용

**`for_each`의 키는 plan 시점에 알려져 있고 수명주기 동안 의미가 안정적이어야 합니다.** 키는 `resource["key"]` 주소를 만들기 때문에 개수만 아는 것으로는 부족합니다. `toset(var.ids)`는 원소 값 자체를 키로 사용하므로, 원소가 아직 생성되지 않은 리소스 속성이면 다음 오류로 실패합니다.

```
Error: Invalid for_each argument

  on modules\load_balancer_security_group\main.tf line 40, in resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress":
  40:   for_each                     = toset(var.ingress_source_security_group_ids)
    ├────────────────
    │ var.ingress_source_security_group_ids is list of string with 1 element

The "for_each" set includes values derived from resource attributes that cannot be
determined until apply, and so Terraform cannot determine the full set of keys that
will identify the instances of this resource.
```

B-6번으로 받은 외부 ID 목록을 `toset()`해 반복하면 ID가 unknown인 동안 값이 곧 키가 되어 이 문제가 생깁니다. 이때 호출자가 의미 있는 라벨을 키로 정한 `map(string)`을 받고, unknown ID는 값에만 둡니다.

```hcl
# 모듈 variables.tf
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on port, keyed by a caller-chosen stable label because for_each keys must be known during plan"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys must be non-empty labels of letters, digits, dots, underscores or hyphens."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
```

```hcl
# 모듈 main.tf
resource "aws_vpc_security_group_ingress_rule" "load_balancer_source_group_ingress" {
  for_each                     = var.ingress_source_security_groups
  security_group_id            = aws_security_group.load_balancer_security_group.id
  description                  = "Listener port from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}
```

```hcl
# 루트 main.tf
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }
}
```

- 키가 반드시 HCL의 **리터럴 토큰**일 필요는 없습니다. 루트 입력이나 `local`에서 계산했더라도 plan 시점에 알려지고 같은 논리 항목을 계속 식별하면 유효합니다. 호출자가 정한 짧은 리터럴 라벨은 이를 만족하는 가장 단순한 형태입니다.
- `{ (module.vscode_ec2.security_group_id) = ... }`처럼 생성될 리소스의 unknown 값을 키로 쓰면 해결되지 않습니다. 키가 바뀌면 기존 인스턴스 삭제와 새 인스턴스 생성으로 해석되므로 값뿐 아니라 의미도 안정적이어야 합니다.
- 검증은 `keys()`와 `values()`로 나눕니다. plan-known 키 검증은 즉시 평가되지만 ID 값이 unknown이면 값 검증은 Terraform이 값을 아는 apply 시점까지 미룰 수 있습니다.
- `each.key`를 보안 그룹 규칙 `description`에 넣으면 출처가 plan과 AWS에 드러납니다. 키가 F-1번의 AWS 문자셋 제약을 어기지 않도록 위처럼 라벨 문자셋을 제한합니다.
- **다른 모듈 output이라는 이유만으로 모든 리스트를 맵으로 바꾸지 않습니다.** C-3번의 subnet ID처럼 일반 리소스 인수에 전달하는 리스트는 unknown이어도 괜찮습니다. 맵이 필요한 시점은 unknown 값이 `for_each`의 인스턴스 키가 될 때입니다.
- 반대로 관리형 정책 ARN이나 명시 CIDR처럼 집합 원소가 plan-known이면 `toset(list)`을 그대로 사용할 수 있습니다.
- `-target`으로 두 번 나눠 apply하는 것은 우회책일 뿐입니다. 각 독립 Terraform 루트는 `-target` 단계 없이 한 번의 `terraform apply`로 완성되어야 하므로(E-2번), 리소스 주소를 plan에서 정할 수 있는 인터페이스로 고칩니다. 여러 계정·state의 루트별 실행 순서는 I-4번의 DAG를 따릅니다.
- 같은 식별자 판단은 `dynamic` 블록에서 항목별 안정적인 반복이 필요한 경우에도 적용합니다. 기존 인라인 소유권을 유지하는 보안 그룹(F-2번의 마이그레이션 예외)에서도 unknown ID를 반복 식별자로 삼지 않습니다.
