---
inclusion: always
---

# Multi-Account and Multi-Region Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-ec2-workbench-and-outputs.md`](rules-ec2-workbench-and-outputs.md) · **Next:** [`rules-common-guidelines.md`](rules-common-guidelines.md)
> 논리 인용 `rules.md I-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| I-1 | 서로 다른 AWS 자격증명으로 리소스를 만듦 | 계정마다 독립 루트와 state를 두고 Terraform 실행 중 다른 계정으로 assume하지 않음 | A-1; 자격증명 절차는 `multi_accounts.md` |
| I-2 | 독립 state 사이에 값 또는 아직 없는 principal 정보가 필요 | 기본은 producer output→consumer variable; 미래 principal 때문에 생기는 진짜 순환만 이름을 미리 합의; 계정 guard는 blocking condition | B-1·I-1 |
| I-3 | 같은 계정의 여러 리전에 리소스를 만듦 | 한 루트의 기본 provider와 alias를 쓰고 모든 리소스·모듈의 region binding을 명시적으로 감사 | A-2·B-6 |
| I-4 | 여러 루트 또는 state 밖 리소스 사이에 수명 순서가 있음 | apply DAG와 reverse destroy DAG를 저장소 README와 모든 참여 루트 output에 기록 | H-2; D 파트의 한-state 순서와 대응 |

## I. 여러 계정과 여러 리전

여기까지의 규칙은 대부분 하나의 자격증명과 하나의 state 파일을 전제합니다. 리전 경계와 계정 경계는 다르게 다룹니다.

| | 경계 | 이 저장소의 구성 정책 | 값을 넘기는 방법 |
| --- | --- | --- | --- |
| 여러 리전 | 같은 계정, 다른 리전 | 한 루트 안에서 `provider` alias | 리소스 속성 참조 (같은 state) |
| 여러 계정 | 다른 자격증명 | 계정마다 독립 루트와 state | producer output → 사람/자동화의 전달 → consumer variable |

**리전은 provider의 인수이고, 계정은 자격증명입니다.** Terraform은 기술적으로 provider alias와 `assume_role`을 이용해 한 루트에서 여러 계정을 조작할 수 있습니다. 그러나 이 저장소는 state의 계정 경계, 독립 운영, 실패 격리를 명확히 하기 위해 **여러 계정은 루트 자체를 분리하는 정책**을 택합니다. “Terraform으로 불가능해서”가 아니라 I-1번의 운영상 이유로 하지 않는 것입니다.

현재 패턴은 한 형태뿐이지 않습니다.

- `056_eks_cross_region_velero_dr`: `cluster`는 한 계정의 multi-region 리허설이고, `primary_account`/`secondary_account`는 계정을 분리한 DR 구성입니다.
- `064_s3_cross_account_replication_rule`: destination root의 output을 source root 변수로 넘기고, 아직 없는 복제 역할 이름만 미리 합의합니다.
- `117_cloudformation_cross_account_s3_template`: bucket root의 template URL을 stack root로 넘기며, CLI로 만드는 CloudFormation stack은 Terraform state 밖 수명주기 노드입니다.
- `121_cross_account_codecommit_replication`: target root output을 source root로 넘기고, target trust가 먼저 참조해야 하는 미래 CodeBuild 역할 이름만 별도로 합의합니다.

두 계정의 임시 자격증명을 로드하고 Git Bash 변환 예외를 설정하는 절차는 [multi_accounts.md](multi_accounts.md)를 따릅니다. 각 루트는 그 시점에 로드된 한 계정의 자격증명만 사용합니다.

### I-1. 계정마다 독립된 루트 모듈을 만들고, 한 루트가 두 계정을 건드리지 않는다

기술적으로는 다음처럼 한 루트가 다른 계정 역할을 assume할 수 있지만, 이 저장소에서는 쓰지 않습니다.

```hcl
# 이 저장소에서는 이렇게 하지 않습니다.
provider "aws" {
  alias = "secondary"
  assume_role {
    role_arn = "arn:aws:iam::${var.secondary_account_id}:role/OrganizationAccountAccessRole"
  }
}
```

이 정책의 이유:

- **한 state 파일이 두 계정의 진실을 담지 않게 합니다.** 리소스 주소만 보고도 어느 계정 루트인지 알 수 있고, destroy 범위가 계정 단위로 분리됩니다.
- **한쪽 계정의 권한 상실이 다른 쪽 운영을 막지 않게 합니다.** trust 변경이나 세션 만료가 한 계정의 plan/apply에만 영향을 줍니다.
- **계정별 담당자와 시점을 분리합니다.** 실제 운영에서 두 계정은 같은 사람이 같은 시점에 배포하지 않을 수 있습니다.
- **미리 존재한다고 가정한 cross-account 관리 역할을 숨기지 않습니다.** `OrganizationAccountAccessRole` 같은 전제가 없어서 생기는 `AccessDenied`를 아키텍처의 필수 조건으로 만들지 않습니다.

계정 하나당 루트 하나를 만들고 디렉토리 이름으로 역할을 드러냅니다(A-1번의 변형 구조를 계정 경계에 적용).

```text
056_eks_cross_region_velero_dr/
├── cluster/              # 한 계정 안에서만 도는 multi-region 리허설
├── primary_account/      # 백업을 만드는 계정의 자격증명으로 apply
├── secondary_account/    # 백업을 받는 계정의 자격증명으로 apply
└── README.md
```

다른 현재 이름도 같은 원칙을 표현합니다: `1_destination_account`/`2_source_account`(064), `s3_bucket_policy_1_bucket_account`/`s3_bucket_policy_2_stack_account`(117), `target_account`/`source_account`(121). 번호는 apply 순서를 읽기 쉽게 할 수 있지만 필수는 아니며, I-4번의 output과 README를 대체하지 않습니다.

- 각 루트는 자기 `modules/`를 독립적으로 소유합니다(A-1번). 계정 간에 모듈 디렉토리를 공유하지 않습니다.
- `provider "aws"`에 `profile`이나 계정 간 `assume_role`을 박지 않고, [multi_accounts.md](multi_accounts.md)의 자격증명 로드 절차에 맡깁니다.
- 잘못된 계정에 apply하는 것은 자격증명 관례만으로 막지 않고 I-2번의 blocking account guard로 차단합니다.

감사할 때는 **각 account root의 실제 provider 블록 전체**를 읽습니다. 같은 계정의 multi-region alias(I-3)는 허용되므로 `alias` 자체를 위반으로 세지 않고, `profile` 또는 계정 간 `assume_role`이 account root에 있는지를 판정합니다.

```bash
grep -rn -A8 '^provider "aws"' --include='providers.tf' . \
  | grep -E 'assume_role|profile' || echo "no account root pins or assumes an account"
```

### I-2. 계정 간 값은 output→variable로 넘기고, 미래 principal의 진짜 순환만 이름 합의로 끊는다

루트를 분리하면 한 state에서 다른 state의 리소스 속성을 직접 참조할 수 없습니다. 그러나 **분리했다고 곧바로 순환이 생기는 것은 아닙니다.** 대부분은 producer를 먼저 apply하고 그 output을 consumer의 변수로 전달하면 끝나는 단방향 DAG입니다.

#### 기본: output → 전달 → variable

| 프로젝트 | producer output | consumer variable | 순환 여부 |
| --- | --- | --- | --- |
| 064 | destination의 `source_account_variables` | source의 같은 이름 변수들 | 단방향; 생성된 버킷 정보 전달 |
| 117 | bucket account의 `template_url` | stack account의 `template_url` | 단방향; 반대쪽 값 불필요 |
| 121 | target의 `source_root_handoff` | source의 같은 이름 변수들 | 단방향; target 저장소·역할 정보 전달 |

```hcl
# 먼저 적용하는 producer root의 outputs.tf
output "consumer_inputs" {
  value = {
    target_account_id = data.aws_caller_identity.current.account_id
    target_name       = module.target.name
    target_region     = data.aws_region.current.region
  }
  description = "Values to copy into the same-named variables of the consumer root"
}
```

전달은 사람이 `terraform output -json`을 읽어 tfvars에 넣거나 승인된 자동화가 수행합니다. 독립 state를 직접 결합하는 참조처럼 가장하지 않고, 어떤 값이 어느 루트의 입력이 되는지를 producer output과 consumer 변수 설명 양쪽에 적습니다. 생성된 이름·ARN을 넘길 수 있으면 고정 이름을 새로 만들지 않습니다.

#### 예외: 먼저 만드는 정책이 아직 없는 principal을 정확히 가리켜야 하는 경우

진짜 bootstrap 순환은 다음 조건이 함께 있을 때 생깁니다.

1. destination/target 쪽 정책 또는 trust를 먼저 만들어야 합니다.
2. 그 정책이 source 쪽에서 나중에 생길 IAM 역할 하나만 허용해야 합니다.
3. IAM `Principal`에 아직 존재하지 않는 역할 ARN을 직접 넣으면 생성이 거부됩니다.

이때만 역할 이름을 양쪽이 미리 합의합니다. 먼저 만드는 정책은 항상 존재하는 source account root를 `Principal`로 쓰고, `aws:PrincipalArn` 조건으로 합의한 **미래 역할 ARN 하나**에 제한합니다.

```hcl
# 먼저 적용하는 target root
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = { AWS = "arn:${var.partition}:iam::${var.source_account_id}:root" }
    Action    = "sts:AssumeRole"
    Condition = {
      ArnEquals = {
        "aws:PrincipalArn" = "arn:${var.partition}:iam::${var.source_account_id}:role/${var.source_codebuild_role_name}"
      }
    }
  }]
})
```

현재의 구체적인 예는 064의 `replication_role_name`과 121의 `source_codebuild_role_name`입니다. 반대로 121의 target `cross_account_role_name`은 target apply 뒤 `source_root_handoff`로 전달할 수 있으므로 순환을 끊는 합의 이름이 아닙니다. 056은 destination bucket/policy와 source replication role이 서로의 미래 정보를 필요로 하는 구성을 양쪽의 사전 합의 이름으로 잇는 패턴입니다.

- 고정 이름은 같은 계정에 같은 구성을 병렬 배포할 때 충돌할 수 있습니다. 필요한 경우 양쪽이 공유하는 배포 접두사/접미사를 입력으로 받고, 둘 다 같은 값인지 운영 절차와 output으로 확인합니다.
- 합의 이름은 각 서비스의 이름 형식을 `validation`으로 검증합니다(B-1번). 형식 검증은 두 state의 값이 같은지를 증명하지 못하므로, 양쪽 output에 기대 ARN/이름을 노출해 대조할 수 있게 합니다.
- 모든 cross-account 값에 이름 합의를 적용하지 않습니다. producer가 먼저 만들어 output할 수 있으면 output→variable이 우선입니다.

#### 잘못된 계정 apply를 막는 guard는 blocking condition이어야 한다

계정 ID 변수의 `validation`은 12자리 형식이나 두 계정이 서로 다른지만 확인할 수 있고, 현재 자격증명의 계정은 `data.aws_caller_identity`에서 옵니다. **`check` 블록 실패는 warning-only이므로 account guard가 아닙니다.** 메시지를 출력해도 apply를 막지 않습니다. 056의 현재 caller-identity `check`는 진단용일 뿐 blocking guard로 인용하지 않습니다.

표준 guard는 다음 둘 중 하나입니다.

- 064처럼 `data "aws_caller_identity"`의 lifecycle `postcondition`으로 기대 계정을 검사합니다.
- 117·121처럼 루트 `terraform_data`의 lifecycle `precondition`으로 검사하고, 리소스를 만드는 모든 루트 진입점이 그 guard를 `depends_on`으로 기다리게 합니다.

```hcl
data "aws_caller_identity" "current" {}

resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "This root must be applied with credentials for expected_account_id."
    }
  }
}

module "account_resources" {
  source = "./modules/account_resources"

  # Nothing in this creation branch starts unless the account guard passes.
  depends_on = [terraform_data.account_guard]
}
```

`precondition`/`postcondition` 실패가 plan/apply를 차단하는지가 guard의 판정 기준입니다. `check`, 주석, output 경고, 디렉토리 이름은 유용한 안내지만 guard를 대신하지 않습니다.

감사할 때는 (1) producer output과 consumer 변수의 키·타입, (2) 미래 principal ARN을 조립하는 모든 trust/policy와 양쪽의 합의 이름, (3) 모든 생성 진입점에서 blocking guard까지의 `depends_on` 도달성을 각각 봅니다. 변수 이름을 고정한 grep 하나로 세 경우를 섞지 않습니다.

### I-3. 같은 계정 안의 여러 리전은 `provider` alias로 나누고, 어느 리전의 것인지를 리소스 이름에 남긴다

계정이 하나면 리전은 한 루트 안에서 나눕니다. 자격증명이 같으므로 I-1번의 state·운영 경계 정책이 적용되지 않고, 값도 같은 state 안의 참조로 흐릅니다.

```hcl
provider "aws" {
  region = var.primary_region
}
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

module "secondary_network" {
  source    = "./modules/network"
  providers = { aws = aws.secondary }
  # ...
}

resource "aws_s3_bucket" "secondary_backup" {
  provider = aws.secondary
  # ...
}
```

- **기본 provider에 alias를 붙이지 않습니다.** 모든 기본 리전 모듈에 `providers`를 명시해야 하게 되고, 하나를 빠뜨리면 의도와 다른 provider가 상속됩니다.
- **리소스와 모듈 이름에 리전 역할을 넣습니다**(`primary_network`, `secondary_cluster`). 이름은 리뷰 단서이지 provider binding의 증거는 아닙니다. `056`의 원본은 이름과 실제 배치가 어긋났으므로 이름만 믿지 않습니다.
- 루트 리소스는 `provider = aws.secondary`, 자식 모듈은 `providers = { aws = aws.secondary }`로 실제 간선을 명시합니다. 모듈에는 `provider` 블록을 두지 않고 `required_providers`만 선언합니다(A-2번).
- **`data.aws_region`은 그 data/module에 결합된 provider의 리전을 돌려줍니다.** 기본 provider의 `data.aws_region.current.region`을 secondary 리전 값으로 넘기지 않습니다. 루트의 aliased data를 쓰거나, 리전 문자열이 필요한 모듈에 올바른 변수를 명시적으로 넘깁니다(B-6번).
- 리전마다 달라지는 AMI ID, ACM 인증서 위치(ALB는 같은 리전, CloudFront는 us-east-1), EBS 스냅샷, ECR 리포지토리, 관리형 prefix list ID를 별도로 확인합니다.

#### 감사 방법

`grep -A8 'module "secondary'`처럼 **이름 접두사와 고정 줄 수를 세는 감사는 취약합니다.** 블록이 길면 `providers`가 창 밖에 있고, 다른 이름의 secondary 모듈은 놓치며, 이름이 secondary여도 binding이 기본 provider일 수 있습니다.

대신 먼저 “어느 root resource/module/data가 어느 리전에 있어야 하는가”라는 기대 인벤토리를 만들고, HCL 블록 전체를 파싱해 다음을 대조합니다.

1. 기본 리전 root resource/module은 의도한 기본 provider를 상속하는가.
2. secondary 리전 root resource에는 `provider = aws.secondary`, module에는 `providers` 맵의 `aws = aws.secondary`가 있는가.
3. 리전 값을 읽는 data source도 같은 alias에 결합되어 있는가.
4. module 경계를 넘어 전달한 region 문자열이 그 module의 provider binding과 같은가.

자동 감사도 정규식의 줄 창이 아니라 HCL parser로 블록과 provider 간선을 수집합니다. `terraform providers`로 provider 트리를 보조 확인하고, plan에서 리전별 이름·ARN·output을 대조하지만, plan 출력에 alias가 항상 충분히 드러난다고 가정하지 않습니다. 핵심은 이름의 개수가 아니라 **기대 리전에서 실제 provider binding까지의 전수 대응**입니다.

### I-4. 계정 간 apply·destroy 순서는 저장소 README와 모든 참여 루트 output에 적는다

서로 다른 state 사이에는 Terraform `depends_on`을 걸 수 없습니다. 따라서 계정 간 수명주기는 사람이거나 상위 자동화가 실행하는 **DAG**로 명시합니다.

- 간선 `A → B`는 “B를 만들기 전에 A가 준비되어야 한다”는 뜻입니다.
- apply는 DAG의 위상 순서로 `A` 다음 `B`를 실행합니다.
- destroy는 **reverse DAG**로 `B`를 완전히 지운 다음 `A`를 지웁니다.
- Terraform state 밖에서 CLI·콘솔·CloudFormation 등이 만든 리소스도 수명주기 vertex로 포함합니다. Terraform이 모른다는 이유로 순서에서 빼면 안 됩니다.

#### 기록 위치

1. **프로젝트의 저장소 README**에 전체 DAG, handoff, 자격증명 역할, reverse-DAG 철거 순서를 적습니다. 체크인된 문서가 전체 절차의 durable source입니다.
2. **모든 참여 루트의 output**에 그 루트가 어디에 놓이는지와 다음/이전 단계, 전체 destroy 순서를 적습니다. 작업자가 한 루트만 열어도 순서를 알 수 있어야 합니다.
3. 루트에 `vscode_ec2`가 있어 H-2번이 적용되면 lifecycle output도 `local.outputs`를 통해 작업대 README에 미러링합니다. 작업대가 없는 루트는 `outputs.tf`에 직접 선언합니다. 작업대 README는 추가 전달 경로이지 1·2번을 대체하지 않습니다.
4. state 밖 vertex가 있으면 생성 명령뿐 아니라 삭제 명령과 **완료 대기 명령**을 output과 README에 둡니다. 삭제 요청만 보내고 다음 Terraform destroy로 넘어가지 않습니다.

자격증명을 어느 계정 것으로 전환하는지는 각 단계에 명시하고, 실제 로드 절차는 [multi_accounts.md](multi_accounts.md)에 링크합니다.

#### 현재 수명주기 예시

| 프로젝트 | apply DAG | reverse destroy DAG | 결정적인 이유 |
| --- | --- | --- | --- |
| 056 Velero DR | `secondary_account → primary_account` | `primary_account → secondary_account` | 대상 버킷·정책이 먼저 있어야 source replication 설정을 만들 수 있음 |
| 117 cross-account template | `bucket-account Terraform → stack-account Terraform role → state 밖 CloudFormation stack` | `CloudFormation delete + stack-delete-complete 대기 → stack-account terraform destroy → bucket-account terraform destroy` | stack은 Terraform state에 없고, service role을 먼저 지우면 stack 삭제가 `DELETE_FAILED`가 됨 |
| 121 CodeCommit replication | `target_account → handoff → source_account` | `source_account → target_account` | source pipeline과 미래 principal을 먼저 제거한 뒤 target trust·repository를 지워야 함 |

117의 CloudFormation stack처럼 out-of-state vertex가 있으면 다음처럼 삭제 완료를 간선의 조건으로 만듭니다.

```hcl
output "teardown_order" {
  value = "aws cloudformation delete-stack --stack-name ${var.stack_name} && aws cloudformation wait stack-delete-complete --stack-name ${var.stack_name} && terraform destroy"
  description = "Delete the out-of-state stack and wait for completion before Terraform removes its service role; then destroy the bucket-account root."
}
```

H-2가 적용되는 workbench root에서는 같은 절차를 README-safe 표현으로 투영합니다.

```hcl
# main.tf의 local.outputs
apply_order = {
  order       = 1
  title       = "이 루트를 apply하기 전에"
  description = "선행 계정 루트와 handoff가 완료되어야 합니다."
  value       = "cd ../prerequisite_account && terraform output -json"
}
teardown_order = {
  order       = 99
  title       = "철거 순서"
  description = "reverse DAG에서 이 루트를 먼저 destroy한 뒤 선행 계정 루트를 지웁니다."
  value       = "terraform destroy"
}
```

#### `force_destroy`는 데이터 폐기를 명시적으로 허용한 리소스에만 사용한다

`force_destroy = true`는 multi-account의 일반 기본값이 아닙니다. Velero 백업, S3 복제본의 버전, pipeline artifact처럼 Terraform 밖에서 객체가 쌓이고 **이 데모의 철거가 그 데이터를 영구 삭제해도 된다고 명시적으로 결정한 경우**에만 적합합니다. 보존이 목적인 백업/운영 버킷은 보통 `false`로 두고 별도 데이터 폐기 절차를 설계합니다.

- 변수나 리소스에서 값을 명시하고 기본값에 숨기지 않습니다.
- repository README와 모든 참여 루트의 teardown output에 삭제 범위를 경고합니다.
- 버전 관리 버킷에서는 객체뿐 아니라 모든 버전과 delete marker까지 삭제될 수 있음을 적습니다.
- `force_destroy`는 reverse-DAG 순서를 대신하지 않으며, 117의 state 밖 CloudFormation stack 같은 외부 vertex를 삭제해 주지도 않습니다.

같은 DAG 원칙은 KMS key policy, RAM 공유와 수락, Route 53 연계, ECR repository policy에도 적용됩니다. 서비스 이름으로 순서를 외우지 말고, **누가 누구의 존재·권한·수명에 의존하는지**를 간선으로 적고 destroy에서 정확히 뒤집습니다.
