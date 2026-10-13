---
inclusion: always
---

# Security Group Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-kubernetes-resource-management.md`](rules-kubernetes-resource-management.md) · **Next:** [`rules-aws-load-balancer-controller.md`](rules-aws-load-balancer-controller.md)
> 논리 인용 `rules.md F-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| F-1 | 보안 그룹 또는 규칙의 `name`/`description`을 AWS API에 전달 | 허용 문자·길이와 `sg-` 접두사 금지를 `validation`으로 강제 | B-1의 AWS 문자셋 특수 규칙 |
| F-2 | 보안 그룹 규칙의 소유자를 정하거나 기존 소유권을 이전 | 신규 그룹은 독립 규칙; populated inline 그룹은 기능 변경 중 소유자를 유지하고 이전은 별도 리허설 | B-8·F-3 |
| F-3 | `allow_inbound_from_anywhere`가 기본 인바운드 소스를 선택 | 규칙 수·주소는 유지하고 `false=/32`, `true=/0`; 명시 CIDR·prefix list·source SG는 추가 소스 | F-2의 소스·cardinality 특수 규칙 |

## F. 보안 그룹

AWS의 문자셋 제약, 규칙 소유권과 state 마이그레이션, 공개 인바운드 스위치의 안전한 기본값이라는 세 가지 함정을 다룹니다.

### F-1. 보안 그룹의 `description`/`name`은 AWS 문자셋 제약을 `validation`으로 검증한다 (아포스트로피 금지, 변경 시 그룹 재생성)

B-1번 패턴의 사례이며, 그중 **가장 값이 큰** 사례입니다. 이 값은 변경하면 보안 그룹이 교체되므로, 오타를 나중에 고치는 비용이 다른 변수와 다릅니다.

`aws_security_group`의 `description`과 `name`에 AWS가 허용하는 문자는 `a-zA-Z0-9`, 공백, 그리고 `. _-:/()#,@[]+=&;{}!$*` 뿐입니다. **아포스트로피(`'`)와 큰따옴표(`"`)는 허용되지 않습니다.** Terraform은 이 값을 검증하지 않고 그대로 전달하므로 `terraform validate`와 `terraform plan`을 모두 통과하고, `CreateSecurityGroup` API 호출에서야 400으로 거부됩니다.

```
Error: creating Security Group (eks-node-sg): operation error EC2: CreateSecurityGroup,
https response error StatusCode: 400, api error InvalidParameterValue: Invalid security group
description. Valid descriptions are strings less than 256 characters from the following set:
a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

영어 설명문을 쓰다 보면 `the cluster's managed network interfaces`처럼 소유격 아포스트로피가 자연스럽게 들어가는데, 이것이 정확히 위 오류의 원인입니다. apply 중반에 터지므로(그 시점에는 VPC/서브넷 등이 이미 만들어져 있음) 반드시 plan 단계에서 잡습니다.

```hcl
variable "description" {
  type        = string
  default     = "Shared security group for EKS worker nodes and the EKS-managed network interfaces"
  description = "Description attached to the security group"

  validation {
    condition     = length(var.description) > 0
    error_message = "description must not be empty."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.description))
    error_message = "description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
```

`name`은 같은 문자셋 제약에 더해 `sg-`로 시작할 수 없습니다(EC2가 보안 그룹 ID용으로 예약).

```hcl
variable "name" {
  type        = string
  default     = "eks-node-sg"
  description = "Name of the security group shared by the cluster managed ENIs and the worker nodes"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.name)) && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
```

주의할 점:

- **`description`과 `name`은 변경 시 보안 그룹이 재생성됩니다** (프로바이더 문서에 `Forces new resource`로 명시). AWS에 `GroupDescription`을 수정하는 API가 없기 때문입니다. 오타를 나중에 고치는 것이 그룹 교체를 의미하고, 보안 그룹은 100개 이상의 다른 리소스가 참조하는 대상이라 교체가 연쇄적으로 번거로워집니다(프로바이더 문서의 _Security Group Deletion Problem_). 그래서 다른 가변 필드보다 plan 단계 검증의 가치가 큽니다. 분류 목적의 값은 `description`이 아니라 `tags`에 넣습니다.
- `description`에 빈 문자열(`""`)을 넣을 수 없습니다. 생략하면 프로바이더가 `Managed by Terraform`을 씁니다.
- 같은 문자셋 제약이 **규칙의 설명**(`aws_vpc_security_group_ingress_rule`/`_egress_rule`의 `description`, 인라인 `ingress`/`egress` 블록의 `description`)에도 적용됩니다. 리터럴로 직접 쓰는 경우가 많아 변수 검증이 걸리지 않으니, 작성 시점에 아포스트로피를 넣지 않도록 주의합니다.
- 검증 대상은 **실제로 AWS API에 전달되는 값**뿐입니다. Terraform의 `variable`/`output` 블록에 붙는 `description`(문서 문자열)은 이 제약과 무관하므로 아포스트로피를 자유롭게 씁니다. 두 가지가 같은 `description =` 문법을 공유해서 혼동하기 쉬우니, 감사 스크립트를 돌릴 때도 `aws_security_group`/`aws_vpc_security_group_*_rule` 리소스 본문 안의 값과 그 값이 참조하는 변수의 `default`만 대상으로 삼습니다.

### F-2. 보안 그룹 규칙은 인라인 `ingress`/`egress` 블록이 아니라 독립 규칙 리소스로 선언한다 (컨트롤러가 규칙을 추가하는 그룹에는 필수)

`aws_security_group`의 인라인 `ingress`/`egress` 인자 대신 `aws_vpc_security_group_ingress_rule`/`aws_vpc_security_group_egress_rule`을 씁니다. 프로바이더 문서도 이쪽을 현재 권장 방식으로 안내합니다.

이 저장소에서 결정적인 이유는 따로 있습니다. 인라인 블록은 [attributes-as-blocks](https://developer.hashicorp.com/terraform/language/attr-as-blocks) 모드로 처리되어 **그룹의 규칙 집합 전체를 단독으로 관리합니다.** 즉 Terraform이 모르는 규칙이 그룹에 생기면 다음 apply가 그것을 되돌립니다. 그런데 이 저장소의 보안 그룹 중 상당수는 AWS 쪽 컨트롤러가 규칙을 추가합니다.

- AWS Load Balancer Controller: `alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"`(또는 Service 쪽 대응 애노테이션)를 주면 노드 측 규칙을 컨트롤러가 직접 넣습니다.
- EKS: 클러스터 보안 그룹에 컨트롤 플레인-노드 간 규칙을 자체적으로 추가합니다.

이런 그룹을 인라인 블록으로 정의하면 컨트롤러가 넣은 규칙이 매 apply마다 삭제되고, 로드 밸런서에서 파드로 가는 경로가 조용히 끊어집니다.

```hcl
resource "aws_security_group" "node_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks, so the
# AWS Load Balancer Controller can add its own backend rules to this group
# without Terraform reverting them on the next apply (inline blocks are
# authoritative over the whole group).
resource "aws_vpc_security_group_ingress_rule" "node_security_group_self_ingress" {
  security_group_id            = aws_security_group.node_security_group.id
  description                  = "All traffic between members of this group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.node_security_group.id
}
resource "aws_vpc_security_group_egress_rule" "node_security_group_egress" {
  security_group_id = aws_security_group.node_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
```

- **한 그룹에 인라인 블록과 독립 규칙 리소스를 섞지 않습니다.** 프로바이더 문서가 경고하는 대로 규칙 충돌, 영구적인 diff, 규칙 덮어쓰기가 발생합니다. 신규 그룹은 모든 규칙을 독립 리소스로 선언하고, 소유권을 명시적으로 이전하는 별도 작업에서도 인라인 규칙을 남기지 않고 전부 함께 옮깁니다. **다만 populated state에서 이미 인라인 규칙이 소유된 그룹에 F-3의 소스·cardinality 변경을 적용할 때는 예외적으로 기존 인라인 소유권을 그대로 유지합니다.** 같은 apply에서 인라인 블록을 지우고 독립 규칙을 추가하는 것은 안전한 이전이 아니며, F-3은 이 기존-state 예외를 설명할 뿐 새 인라인 규칙 작성을 허용하지 않습니다.
- 외부에서 주입받은 소스(B-6번 패턴)는 규칙 블록을 복제하지 않고 `for_each`로 반복합니다(B-7번 패턴과 같은 이유). 이번 apply에서 생성되는 다른 모듈의 보안그룹 ID처럼 값이 plan 시점에 unknown이고 그 값을 반복해야 한다면, 값 자체가 키가 되는 `toset(list)` 대신 caller가 정한 plan-known 안정 키의 맵을 받습니다(B-8번). 반대로 output이라도 값이 plan-known이고 안정적이면 output이라는 이유만으로 맵으로 바꾸지 않습니다.

```hcl
resource "aws_vpc_security_group_ingress_rule" "node_security_group_source_ingress" {
  for_each                     = var.ingress_source_security_groups # map(string), 키는 호출자가 정한 라벨
  security_group_id            = aws_security_group.node_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
```

- 선택적 기능 때문에 규칙 자체가 없어져야 하는 경우에는 `count`로 켜고 끕니다. 다만 `allow_inbound_from_anywhere`는 이 경우가 아닙니다. 그 변수는 규칙의 존재가 아니라 소스만 고르며, false에서도 My IP 규칙이 하나 남아야 합니다(F-3번).
- **새로 쓰는 그룹은 예외 없이 독립 규칙 리소스입니다.** 컨트롤러가 손댈지 여부를 판단해서 고르지 않습니다 — 그 판단은 나중에 애노테이션 하나로 뒤집히고, 뒤집힌 것을 알아차리는 시점은 컨트롤러가 넣은 규칙이 조용히 사라진 뒤입니다.
- **populated state의 소유권 이전은 기능 변경과 분리합니다.** 구성에서 인라인 블록을 생략하는 것은 `ingress = []`/`egress = []`로 기존 권한을 지우는 것과 같지 않습니다. 같은 권한의 독립 규칙을 곧바로 만들면 기존 권한이 남아 `InvalidPermission.Duplicate`로 실패할 수 있습니다. 이전이 필요하면 populated state를 사용한 plan으로 삭제·생성 순서를 확인하고, 서비스 중단을 허용한 격리 환경에서 실제 apply/destroy까지 별도로 리허설합니다. 현재 구성도 파일 모양만으로 이전 완료를 단정하지 말고 state와 plan을 감사하며, F-3의 `vscode_ec2` 사례처럼 소스만 바꾸는 작업은 기존 인라인 소유권을 유지합니다.
- `revoke_rules_on_delete = true`는 **컨트롤러나 AWS 서비스가 Terraform이 관리하는 바로 그 보안그룹에 규칙을 추가할 수 있을 때** 설정합니다. 삭제 시 그 그룹에 붙은 권한을 먼저 회수하므로, Terraform이 추적하지 않는 attached rule이나 그 그룹 안에서 생긴 참조 순환 때문에 삭제가 막히는 경우를 다룹니다. 반대로 다른 보안그룹에 붙은 규칙이 이 그룹을 참조한다는 이유만으로 그 외부 규칙까지 지우지는 않습니다. 따라서 모든 `DependencyViolation`의 보편적 해결책도, 컨트롤러와 관련된 모든 그룹에 붙이는 표식도 아닙니다. 외부 그룹이 소유한 참조는 그 규칙·그룹의 삭제 순서를 바로잡거나 소유자가 먼저 제거해야 합니다. 이 플래그는 Terraform의 삭제 동작만 바꾸며 그룹을 재생성시키지 않습니다(F-1번의 `description`/`name`과 달리 `Forces new resource`가 아님).

```hcl
resource "aws_security_group" "node_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # The load balancer controller and EKS can add rules attached to this node
  # security group that Terraform does not track. Revoke this group's attached
  # permissions before deleting it, including untracked permissions. This does
  # not remove a rule attached to some other group merely because that rule
  # references this group (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = {
    Name = var.name
  }
}
```

`node_security_group`처럼 AWS Load Balancer Controller의 backend 규칙이나 EKS 규칙이 **그 그룹에 실제로 붙는** 경우가 적용 대상입니다. 로드밸런서에 프론트엔드 그룹을 연결했다는 사실만으로 `load_balancer_security_group`도 대상이라고 단정할 수는 없습니다. 각 모듈과 실제 AWS 규칙의 `GroupId`를 감사해 외부 주체가 그 그룹에 attached rule을 쓰는지 확인하고, 확인되지 않은 기존 설정은 유지가 아니라 감사·교정 대상으로 기록합니다. 아무 외부 주체도 규칙을 추가하지 않는 `vscode_ec2` 자체 그룹에는 불필요합니다.

### F-3. `allow_inbound_from_anywhere`는 규칙 존재가 아니라 소스만 선택한다 (`false` = 실행자의 My IP `/32`, `true` = `0.0.0.0/0`)

F-2번이 규칙의 **소유자**를 정하고, 이 규칙은 그 소유자가 관리하는 기본 인바운드 규칙의 **소스와 cardinality**만 더 구체화합니다. 신규 그룹에는 계속 독립 규칙 리소스를 사용합니다. populated state에서 이미 인라인 소유인 그룹은 이 기능 변경 동안 그 소유자를 유지하지만, 그것이 새 인라인 규칙을 작성하거나 인라인과 독립 규칙을 섞어도 된다는 허가는 아닙니다.

`allow_inbound_from_anywhere`는 "인바운드 규칙을 만들 것인가"가 아니라 **항상 존재하는 기본 인바운드 규칙의 소스를 무엇으로 할 것인가**를 정합니다.

| 값 | 기본 규칙 | 소스 |
| --- | --- | --- |
| `false` (기본값) | 존재함 | Terraform을 실행한 기계가 외부에서 보이는 공인 IPv4 한 개, `/32` |
| `true` | 존재함 | `0.0.0.0/0` |

#### 명시 CIDR·prefix list·source security group은 추가 소스다

false는 **이 스위치가 제어하는 기본 규칙**의 소스가 My IP라는 뜻입니다. 보안그룹 전체에 My IP 외의 소스가 없다는 뜻은 아닙니다.

- `ingress_cidr_blocks`
- CloudFront 등의 managed prefix list
- `ingress_source_security_groups`

위 입력은 기존 의미대로 additive입니다. 따라서 CloudFront를 쓰는 구성의 설명도 "CloudFront만 유일하게 접근"이라고 쓰지 않고, "CloudFront가 선호되는 HTTPS 경로이며 My IP 직접 접근도 기본으로 추가된다"고 적습니다.

독립 규칙 모듈에서 명시 CIDR이 선택된 `/32` 또는 `/0`와 같으면 EC2는 동등한 권한 두 개를 허용하지 않습니다. host bit가 다른 표기도 EC2가 canonicalize하므로, 명시 CIDR을 `cidrhost(cidr, 0)/prefix` 형태로 정규화하고 선택 소스와 같은 항목을 제거한 뒤 `for_each`를 만듭니다. populated inline 소유자도 한 소유자 안에서 동등한 권한을 중복 렌더링하지 않아야 하며, 중복을 피하려고 독립 규칙을 섞어서는 안 됩니다. 이 필터가 없으면 apply에서 `InvalidPermission.Duplicate`가 납니다.

따라서 `count = var.allow_inbound_from_anywhere ? 1 : 0`이나 `for_each = var.allow_inbound_from_anywhere ? var.ports : {}`는 잘못된 구현입니다. false가 규칙 삭제를 뜻하던 예전 의미를 되살려서, 기본값을 false로 둔 순간 서비스가 아무 데서도 응답하지 않게 만듭니다. 리소스 인스턴스 수와 주소는 두 값에서 같아야 하고 **CIDR만 바뀌어야 합니다.**

#### My IP는 루트에서 한 번 조회하고 `/32`만 모듈에 넘긴다

"My IP"는 로컬 NIC의 사설 주소가 아니라 보안그룹 콘솔의 **My IP**와 같은 의미입니다. 즉 address-reflection endpoint가 본 Terraform 실행 기계의 공인 egress IPv4입니다. VPN·회사 NAT·프록시 뒤에서는 그 장비의 주소가 답이고, CGNAT처럼 그 주소로 되돌아오는 연결을 허용하지 않는 환경에서는 `/32` 규칙이 있어도 직접 접속할 수 없습니다.

조회는 각 독립 루트의 `main.tf`에 둡니다. 보안그룹 모듈은 대부분 `depends_on = [module.network]` 뒤에 있고, 모듈 안의 `data "http"`는 D-6번 때문에 apply까지 미뤄질 수 있습니다. 루트에서 읽으면 plan 시점에 값이 확정되고, 모듈은 외부 서비스가 아니라 CIDR 문자열 하나만 알게 됩니다(B-6번).

```hcl
# root providers.tf
terraform {
  required_providers {
    http = { source = "hashicorp/http", version = "~> 3.4" }
  }
}
```

```hcl
# root variables.tf
variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
```

```hcl
# root main.tf
# No depends_on: this has to be read during plan (rules.md D-6).
data "http" "my_ip" {
  url = var.my_ip_lookup_url

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body))) &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0))
      )
      error_message = "my_ip_lookup_url must return HTTP 200 with one bare IPv4 address."
    }
  }
}

locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
}
```

- 응답은 `trimspace()`로 줄바꿈을 제거하고 `/32`를 붙입니다.
- 정규식은 모양을, `cidrhost()`는 각 octet의 실제 범위를 검사합니다. 둘 중 하나만 쓰면 HTML 응답이나 `999.999.999.999`가 EC2 API까지 흘러가 apply 중간에 실패합니다.
- endpoint는 반드시 HTTPS이며 변수로 노출합니다. 이 호출은 AWS API가 아닌 외부 네트워크 의존성이라, 막힌 네트워크에서는 mirror로 바꿀 수 있어야 합니다.
- 현재 구현은 루트당 한 번 조회하므로 `true`를 넘겨도 plan은 endpoint에 접근합니다. 값이 바뀐 네트워크에서 다시 plan하면 false인 규칙은 새 `/32`로 이동하고 이전 주소는 막힙니다.

#### 루트와 모듈의 기본값은 모두 false다

모듈 입력은 nullable `/32`를 받고, false인데 값이 없는 조합을 Terraform 1.9의 교차 변수 validation으로 막습니다(B-1번).

```hcl
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rule uses 0.0.0.0/0; false uses my_ip_cidr"
}

variable "my_ip_cidr" {
  type        = string
  default     = null
  description = "Public IPv4 /32 supplied by the root"

  validation {
    condition = (
      var.my_ip_cidr == null ||
      (can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/32$", var.my_ip_cidr)) && can(cidrhost(var.my_ip_cidr, 0)))
    )
    error_message = "my_ip_cidr must be a valid IPv4 host CIDR such as 203.0.113.10/32, or null when allow_inbound_from_anywhere is true."
  }
  validation {
    condition     = var.allow_inbound_from_anywhere || var.my_ip_cidr != null
    error_message = "my_ip_cidr must be supplied when allow_inbound_from_anywhere is false."
  }
}
```

루트가 다른 이름(`alb_allow_inbound_from_anywhere`, `nlb_allow_inbound_from_anywhere`, `allow_bastion_inbound_from_anywhere` 등)으로 같은 선택을 노출해도 **그 기본값은 false**여야 합니다. README/output의 안내는 자식 모듈 이름이 아니라 사용자가 실제로 `-var`/tfvars에 쓸 수 있는 루트 변수 이름을 적습니다.

#### 독립 규칙은 개수를 유지하고 CIDR만 선택한다

이미 독립 규칙을 쓰는 모듈은 리소스 주소를 유지합니다. 단일 포트의 기존 `count` 주소가 state에 있다면 `count = 1`을 남기는 것도 의도입니다.

```hcl
resource "aws_vpc_security_group_ingress_rule" "code_server_from_anywhere" {
  count = 1

  security_group_id = aws_security_group.vscode_ec2_security_group.id
  description       = var.allow_inbound_from_anywhere ? "code-server from anywhere" : "code-server from My IP"
  ip_protocol       = "tcp"
  from_port         = var.code_server_port
  to_port           = var.code_server_port
  cidr_ipv4         = var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr
}
```

여러 포트면 `for_each`의 키 집합도 항상 같아야 합니다.

```hcl
resource "aws_vpc_security_group_ingress_rule" "listener" {
  for_each = var.ports

  from_port = each.value
  to_port   = each.value
  cidr_ipv4 = var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr
  # ...
}
```

`for_each = var.allow_inbound_from_anywhere ? var.ports : {}`로 쓰면 false에서 주소가 전부 사라지므로 이 규칙을 위반합니다.

#### 기존 인라인 규칙은 소유권을 유지하고 값만 바꾼다

신규 보안그룹은 F-2번대로 독립 규칙 리소스를 사용합니다. 그러나 **기존 state가 인라인 규칙을 소유하는 그룹은 예외**입니다. 인라인 블록을 지우고 같은 apply에 독립 규칙을 추가하는 것은 안전한 마이그레이션이 아닙니다.

실제 populated-state 리허설에서 다음이 확인되었습니다.

1. 기존 state에는 `aws_security_group`의 inline ingress `0.0.0.0/0`와 inline egress가 있었습니다.
2. 구성에서 inline 블록을 없애고 같은 권한의 standalone ingress/egress를 추가했습니다.
3. plan은 `aws_security_group`을 **변경 없음**으로 두고 standalone 두 개만 `+ create`로 표시했습니다.
4. 즉 apply하면 기존 권한이 남은 상태에서 같은 권한을 다시 만들고, EC2가 `InvalidPermission.Duplicate`로 거부합니다.

블록을 **생략**하는 것은 `ingress = []`/`egress = []`로 비우는 것과 같지 않습니다. 그래서 기존 `vscode_ec2` 인라인 그룹은 아래처럼 규칙을 항상 한 개 렌더링하고 소스만 바꿉니다.

```hcl
resource "aws_security_group" "vscode_ec2_security_group" {
  # Existing inline ownership is retained; do not add standalone rules for this group.
  dynamic "ingress" {
    for_each = [1]
    content {
      description = var.allow_inbound_from_anywhere ? "code-server from anywhere" : "code-server from My IP"
      protocol    = "tcp"
      from_port   = var.code_server_port
      to_port     = var.code_server_port
      cidr_blocks = [var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr]
    }
  }

  # Existing prefix-list ingress and egress blocks stay inline too. A group never mixes owners (rules.md F-2).
}
```

격리된 실제 AWS 리허설에서는 기존 `/0` → 기본 false의 `/32` → true의 `/0`가 모두 **같은 보안그룹 ID의 in-place update**였고, 각 전환은 `0 added, 1 changed, 0 destroyed`였습니다. 동일 입력의 다음 plan은 `No changes`였습니다.

소유권을 반드시 독립 리소스로 바꿔야 한다면 이 기능 변경과 분리합니다. populated state 없이 주소 모양만 보고 판단하지 말고, 서비스 중단을 허용하는 별도 단계와 격리된 실제 apply/destroy 리허설을 먼저 설계합니다. stale backup을 `-state`로 읽은 plan은 diff 형태를 보는 fixture일 뿐이며, 그것을 apply하거나 현재 state로 복원하지 않습니다.

#### 보안 경계

- My IP `/32`는 네트워크 allow-list일 뿐 인증이 아닙니다. `auth: none`인 code-server URL을 같은 NAT를 공유하는 다른 사용자가 얻으면 그 사람도 들어올 수 있습니다.
- `true`는 의도적으로 전 세계에 엽니다. 데모용이어도 별도 opt-in이어야 하고 기본값으로 두지 않습니다.
- 실행 위치가 CI runner라면 허용되는 것은 개발자의 주소가 아니라 runner의 egress 주소입니다. apply 후 브라우저가 있는 네트워크와 다르면 직접 접속은 실패합니다.
- 보안그룹이 internal ALB/NLB에 붙어 있으면 My IP 규칙이 있어도 인터넷 라우팅이 생기는 것은 아닙니다. 내부 source-security-group 규칙은 계속 별도로 필요합니다.

#### 확인하는 방법

false에서 규칙을 삭제하는 예전 패턴은 한 건도 없어야 합니다.

```bash
grep -rnE '^[[:space:]]*(count|for_each)[[:space:]]*=.*allow_inbound_from_anywhere[[:space:]]*\?' \
  --include='main.tf' . | grep -v '/_monolithic/' | grep -v '/.terraform/'
```

모듈마다 두 형태 중 하나가 있어야 합니다.

```bash
# standalone owner
# cidr_ipv4 = var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr
# existing inline owner
# cidr_blocks = [var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr]
grep -rn 'var.allow_inbound_from_anywhere ? "0.0.0.0/0" : var.my_ip_cidr' \
  --include='main.tf' . | grep -v '/_monolithic/' | grep -v '/.terraform/'
```

기본값과 루트 전달은 변수 이름만 세지 말고 모듈 호출까지 따라갑니다. 특히 모듈 호출이 bool 인수를 생략해 자식의 false 기본값을 쓰는 경우에도 `my_ip_cidr = local.my_ip_cidr`는 있어야 합니다.

```bash
grep -rn 'my_ip_cidr[[:space:]]*=[[:space:]]*local.my_ip_cidr' --include='main.tf' . \
  | grep -v '/_monolithic/' | grep -v '/.terraform/'
grep -rn 'data "http" "my_ip"' --include='main.tf' . \
  | grep -v '/_monolithic/' | grep -v '/.terraform/'
```

기존 state가 있는 인라인 그룹을 손댈 때는 반드시 그 SG를 향한 plan을 읽습니다.

```bash
terraform plan -refresh=false -lock=false \
  -target='module.vscode_ec2.aws_security_group.vscode_ec2_security_group'
# 기대: false로 바꾸면 SG 하나의 update in-place. SG replacement나 standalone rule create가 나오면 중단합니다.
```

apply 후에는 AWS가 실제로 저장한 소스와 다음 plan의 idempotency를 확인합니다.

```bash
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=<sg-id> \
  --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4,Description]' \
  --output table
terraform plan    # No changes
```
