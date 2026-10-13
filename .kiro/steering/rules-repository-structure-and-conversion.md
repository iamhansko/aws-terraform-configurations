---
inclusion: always
---

# Repository Structure and CloudFormation Conversion Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Next:** [`rules-variables-and-interfaces.md`](rules-variables-and-interfaces.md)
> 논리 인용 `rules.md A-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| A-1 | 새 프로젝트 또는 `_monolithic` 모듈화 | 단일 루트는 주제 디렉터리에 직접 두고, 다중 루트는 각 하위 루트가 자체 `modules/`를 소유한다 | A-2 |
| A-2 | 모든 루트와 자식 모듈 | 선언을 4파일로 분리하고 모든 루트 provider 구성은 `providers.tf`에 둔다 | A-1, D-9 |
| A-3 | CloudFormation의 복수 값을 Terraform 스칼라 인수로 옮길 때 | JSON 배열 문자열이 아니라 필요한 단일 값을 전달한다 | B-1 |
| A-4 | 모든 `.tf` 파일 | LF를 저장소 경계에서 보장하고 전달 지점의 `replace()`로 숨기지 않는다 | D-5, H-2 |
| A-5 | 원본이 Terraform 밖에서 IAM을 만들 때 | 외부 스크립트까지 추적해 실제 권한을 재현하고 광범위 정책으로 대체하지 않는다 | B-1, B-6 |

## A. 저장소 구조 · 파일 · CloudFormation 변환

프로젝트를 처음 만들거나 `_monolithic` 산출물을 모듈로 쪼갤 때 먼저 읽습니다. 파일이 어디에 놓이고 어떤 바이트로 저장되는지에 관한 규칙입니다.

### A-1. 디렉토리 구조

**Terraform 루트가 하나인지 여러 개인지 먼저 결정하고 그 모양을 그대로 디렉터리에 드러냅니다.** 루트가 하나인 프로젝트는 주제 디렉터리 자체가 루트입니다.

```
NNN_<주제>/
├── providers.tf
├── variables.tf
├── main.tf                  # source = "./modules/<name>"
├── outputs.tf
├── modules/                 # 이 루트가 독립적으로 소유
│   ├── network/
│   ├── key_pair/
│   └── <app>_ec2/
└── README.md
```

변형·계정처럼 상태와 실행 경계가 여러 개이면 주제 디렉터리는 컨테이너이고, 각 하위 디렉터리가 독립된 루트입니다.

```
NNN_<주제>/
├── <variant_a>/                 # 독립적으로 init/plan/apply 가능
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf                  # source = "./modules/<name>"
│   ├── outputs.tf
│   └── modules/                 # variant_a 전용
│       ├── network/
│       ├── key_pair/
│       └── <app>_ec2/
├── <variant_b>/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── modules/                 # variant_b 전용; variant_a를 참조하지 않음
└── README.md
```

- 단일 루트와 다중 루트는 모두 표준 구조입니다. 차이는 루트 파일이 주제 디렉터리에 직접 있는지, 독립 상태를 가진 하위 디렉터리에 있는지뿐입니다.
- 다중 루트에서는 리소스 정의가 동일해도 모듈을 상위 폴더로 승격해 공유하지 않습니다. 각 루트는 자신의 `modules/`를 소유하며 `../modules`에 의존하지 않습니다.
- 이유: 루트 하나만 복사·이동·삭제해도 자체 상태, `.terraform.lock.hcl`, 모듈 소스가 함께 움직이는 자기완결 단위여야 합니다.
- 모듈 코드가 루트 간에 같으면 처음에는 복사해도 되지만, 이후 각 사본은 독립적으로 진화합니다. 한 루트의 변경이 다른 루트에 암묵적으로 전파되지 않습니다.

### A-2. 루트 구성과 모듈 모두 4파일 분리

**루트와 자식 모듈 모두 선언 종류에 따라 네 파일로 나눕니다.** 아래는 파일 배치 규칙이며, 어떤 블록을 어느 계층에 둘지에 관한 의미 규칙(예: D-9번의 `check` 위치)은 별도로 적용합니다.

| 파일 | 루트 책임 | 자식 모듈 책임 |
| --- | --- | --- |
| `providers.tf` | `terraform` 블록(`required_version`, `required_providers`)과 모든 `provider` 구성(`aws`, `kubectl`, `helm`, alias 등) | `terraform` 블록(`required_version`, `required_providers`)만 선언하고 `provider` 구성 블록은 두지 않음 |
| `variables.tf` | 모든 `variable` 선언 | 모든 `variable` 선언 |
| `main.tf` | `locals`, `data`, `resource`, `module`, `check`, `action`, `ephemeral`, `moved`, `import` 블록 | 같은 종류의 구현 블록. 단, 계층별 의미 제약은 해당 규칙을 따름 |
| `outputs.tf` | 모든 `output` 선언 | 모든 `output` 선언 |

`main.tf`에 위 구현 블록을 둘 수 있다는 말은 `variable`, `output`, `terraform`, `provider` 블록까지 섞어도 된다는 뜻이 아닙니다. 특히 **루트의 provider 구성은 종류와 alias 여부를 불문하고 모두 `providers.tf`에 둡니다.** 자식 모듈은 `required_version`과 필요한 provider의 소스·버전을 `terraform` 블록에 선언하고, 실제 provider 구성은 호출자에게 맡깁니다.

`120_codepipeline_asg/bluegreen`, `120_codepipeline_asg/inplace`, `120_codepipeline_asg/inplace_elb`가 각각 단일 `main.tf`에 구성을 모아둔 것은 세 개의 레거시 **A-2 위반**입니다. 아직 분리되지 않았다는 사실이 대체 표준이나 허용 예외를 만들지 않으며, 새 코드가 이 형태를 복사해서는 안 됩니다.

#### 모듈 호출의 `Unexpected attribute`는 먼저 `terraform validate`로 판정합니다

```
Unexpected attribute: An attribute named "enable_backend_security_group" is not expected here
```

`module` 블록에 모듈이 선언하지 않은 인수를 넘기면 나는 오류입니다. 다만 **모듈의 `variables.tf`를 에디터 밖에서 고친 직후라면 실제 원인이 아닐 수 있습니다.** A-1번 패턴 때문에 이 저장소는 같은 모듈을 여러 루트가 각각 소유하고, 여러 사본을 스크립트로 한꺼번에 수정하는 일이 잦습니다. 그렇게 파일이 바뀌면 에디터의 Terraform language server가 예전 변수 목록을 그대로 들고 있다가 정상인 `module` 호출에 이 오류를 표시할 수 있습니다.

판정 기준은 CLI입니다.

```bash
terraform validate            # 여기서 통과하면 구성은 유효합니다
terraform validate -json      # valid / error_count를 기계적으로 확인
```

- CLI가 통과하고 에디터만 오류를 표시하면 language server를 재시작하거나 `terraform init`을 다시 실행해 재색인시킵니다.
- CLI도 같은 오류를 내면 진짜 누락입니다. 해당 모듈 사본 **전부**에 변수가 들어갔는지 확인합니다. 한 사본만 빠뜨리는 것이 이 구조에서 가장 흔한 실수입니다.

```bash
# 루트가 넘기는 인수와 모듈이 선언한 변수의 개수가 맞는지 사본별로 대조
for d in */modules/<module_name>; do
  printf '%s %s\n' "$d" "$(grep -c 'variable "<name>"' $d/variables.tf)"
done
```

### A-3. `aws_iam_instance_profile`의 `role`은 역할 이름 문자열 하나만 받는다 (CloudFormation 변환 시 흔한 버그)

**CloudFormation의 리스트 속성을 Terraform의 스칼라 인수로 옮길 때는 필요한 원소 하나를 꺼내 전달합니다.** CloudFormation의 `AWS::IAM::InstanceProfile.Roles`는 리스트지만 Terraform의 `aws_iam_instance_profile.role`은 역할 이름 문자열 하나만 받습니다. 인스턴스 프로필에는 역할을 최대 하나만 연결할 수 있습니다.

CloudFormation 변환 코드에서 `role = jsonencode([aws_iam_role.xxx.name])`처럼 리스트를 JSON 인코딩하면 Terraform에는 문자열이므로 형식 검사를 통과하지만, 실제 값은 역할 이름이 아니라 JSON 배열 문자열입니다. 실패는 `apply` 중 IAM API에서 나타납니다.

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

`_monolithic/*.tf`를 참고해 모듈화할 때는 CloudFormation의 복수 속성이 Terraform에서 단일 값이 되는 인수(`role`, `queue_url`, `arn` 등)를 확인하고 원본 표현을 그대로 베끼지 않습니다. 모든 복수 속성이 스칼라로 바뀐다는 뜻은 아니므로 대상 Terraform provider 스키마를 기준으로 판정합니다.

#### `aws_iam_instance_profile`만의 문제가 아닙니다

지금까지 발견된 같은 형태는 다음과 같습니다.

| 리소스 | Terraform 속성(문자열 하나) | CloudFormation 속성(리스트) |
| --- | --- | --- |
| `aws_iam_instance_profile` | `role` | `AWS::IAM::InstanceProfile`의 `Roles` |
| `aws_sqs_queue_policy` | `queue_url` | `AWS::SQS::QueuePolicy`의 `Queues` |
| `aws_sns_topic_policy` | `arn` | `AWS::SNS::TopicPolicy`의 `Topics` |

**속성 이름으로만 찾으면 다음 사례를 놓칩니다.** 위 표의 두 번째 행이 그 증거입니다. `058_eks_fis_experiments`와 `060_eks_node_termination_handler`의 원본에는 `queue_url = jsonencode([aws_sqs_queue.x.id])`가 있었고, `role = jsonencode([`만 찾는 명령은 이를 잡지 못했습니다. 그래서 `jsonencode([` 자체를 찾은 뒤 좌변이 정말 스칼라인지 사람이 판정합니다.

```bash
# jsonencode([...])를 스칼라 속성에 넘긴 곳을 전부 나열합니다.
# 정당한 용법(policy 문서의 Action/Resource 리스트 등)도 함께 걸리므로, 좌변이
# 문자열 하나를 받는 속성인지를 보고 판정합니다. 그 판정은 grep이 할 수 없습니다.
grep -rn 'jsonencode(\[' --include='*.tf' . | grep -v '_monolithic'

# 좌변이 단순 속성 대입인 것만 좁혀 보면 거짓 양성이 크게 줄어듭니다.
grep -rnE '^ *[a-z_]+ *= *jsonencode\(\[' --include='*.tf' . | grep -v '_monolithic'
```

- **`terraform validate`는 이 오류를 잡지 못합니다.** 속성 타입이 어느 쪽이든 문자열이기 때문입니다. `plan`도 통과하고, 실패는 apply 중 해당 서비스의 API 오류로 나타납니다(IAM은 역할 이름 형식 오류, SQS는 malformed queue URL).
- `_monolithic/`을 참고할 때 이 형태를 먼저 훑고 목록을 만들어 두는 것이 변환 중에 하나씩 발견하는 것보다 싸게 끝납니다.

### A-4. `.tf` 파일은 LF로 저장한다 (CRLF는 heredoc 종료자를 깨뜨려 셸 스크립트 전체를 실행 불가로 만든다)

**모든 `.tf` 파일은 LF로 저장하고 CRLF를 발견하면 파일 자체를 고칩니다.** 전달되는 문자열마다 `replace()`를 붙여 숨기지 않습니다.

`.tf` 파일이 CRLF이면 heredoc 안의 리터럴 줄도 `\r`로 끝납니다. 셸 heredoc 종료자는 `EOF`가 아니라 **`EOF\r`**이 되고, 셸은 이를 종료자로 인정하지 않습니다. heredoc이 파일 끝까지 이어져 스크립트 전체가 파싱에 실패하며 **한 줄도 실행되지 않습니다.**

H-2번 패턴의 SSM Association에서는 원인을 짐작하기 어려운 다음 오류만 먼저 보입니다.

```
Error: waiting for SSM Association (...) create: unexpected state 'Failed', wanted target 'Success'
```

#### 진단 절차

SSM은 실패 사실만 알려주므로 실제 원인은 명령 실행 결과에서 꺼냅니다.

```bash
aws ssm describe-association-executions --association-id <id>
aws ssm describe-association-execution-targets --association-id <id> --execution-id <exec-id>
# OutputSource.OutputSourceId가 run command의 command-id입니다
aws ssm get-command-invocation --command-id <command-id> --instance-id <instance-id>
#   "StandardErrorContent": "_script.sh: line 113: syntax error: unexpected end of file"
#   "ExecutionElapsedTime": "PT0.018S"
```

**`ExecutionElapsedTime`이 0.0x초면 명령이 실행된 게 아니라 파싱에서 실패한 것입니다.** D-5번 패턴의 `until` 루프는 시작조차 하지 않았으므로 마커 파일이나 `wait_for_success_timeout_seconds`를 의심할 필요가 없습니다.

AWS가 실제로 받은 문자열을 보면 확정할 수 있습니다.

```bash
aws ssm describe-association --association-id <id> --query 'AssociationDescription.Parameters.commands'
# [ "until [ -f /run/terraform/userdata ]; do sleep 10; done\r\ncat > /home/ec2-user/README.md << 'TFREADME'\r\n# eks-cluster\n\n..." ]
#   ^ 템플릿 리터럴 줄은 \r\n, 보간된 readme_body는 \n - 그래서 종료자만 TFREADME\r이 됩니다
```

Terraform 쪽에서는 파일 바이트를 직접 확인합니다. `_monolithic`은 조회 전용이므로 제외합니다.

```bash
find . -name '*.tf' -not -path '*/.terraform/*' -not -path '*_monolithic*' \
  | while read f; do grep -qU $'\r' "$f" && echo "CRLF: $f"; done
```

#### 예방

- **`.gitattributes`에 `*.tf text eol=lf`를 둡니다.** 이는 Git이 추적하는 파일에만 적용되므로 아직 추적되지 않은 새 파일에는 효력이 없습니다. 새 프로젝트를 만든 직후가 가장 위험한 시점입니다.
- **파일을 프로그램으로 수정할 때 LF를 명시합니다.** 이 저장소에서 CRLF가 유입된 실제 경로가 Windows의 텍스트 쓰기였습니다. `pathlib.Path.write_text()`는 환경의 줄바꿈 변환을 받을 수 있으므로, LF를 보장하려면 `write_bytes()`를 쓰거나 `newline="\n"`을 지원하는 파일 API를 사용합니다.

```python
# 위험함 - Windows 텍스트 쓰기 경로가 줄바꿈을 CRLF로 바꿀 수 있습니다
path.write_text(text, encoding="utf-8")
# LF 바이트를 그대로 기록
path.write_bytes(text.encode("utf-8"))
```

- `terraform fmt`를 줄바꿈 복구 수단으로 의존하지 않습니다. 포맷 검사는 별도로 하고, LF 여부는 바이트 검사와 `.gitattributes`로 보장합니다.
- 로컬 `bash -n`으로는 재현되지 않을 수 있습니다. Git for Windows(MSYS)의 bash는 `\r`을 관용하지만 Amazon Linux의 bash는 그렇지 않아 인스턴스에서만 실패할 수 있습니다. 진단은 위 `get-command-invocation` 출력으로 합니다.
- 이 문제는 heredoc에만 국한되지 않습니다. `\r`은 셸에게 평범한 문자라서 `done\r`은 `done`이 아니고 `fi\r`은 `fi`가 아닙니다. CRLF는 스크립트 어디에 있어도 위험합니다.
- heredoc으로 애플리케이션 설정 파일을 만들 때도 모든 지시어 값 끝의 `\r`을 파서가 값의 일부로 읽을 수 있습니다. 특정 서비스 규칙이 아니라 바이트 전달 경로 전체의 문제입니다.

#### `replace(..., "\r\n", "\n")`를 설정에 넣지 않습니다

문자열이 AWS로 넘어가는 지점마다 `replace()`로 CR을 제거할 수는 있지만 이 저장소는 그렇게 하지 않습니다. 파일을 LF로 유지하는 것이 근본 해결이고, 방어 코드는 heredoc마다 잡음을 남기면서 원인을 가립니다.

```hcl
# 이렇게 하지 않습니다
commands = replace(<<-EOT
  ...
  EOT
  , "\r\n", "\n")
```

- heredoc 종료자 줄에는 마커만 올 수 있습니다. 바깥 함수의 나머지 인자는 다음 줄로 밀려나 종료 경계가 불분명해지고, 종료자에 다른 토큰을 붙이면 HCL이 거부합니다.
- CRLF가 이미 유입된 상황을 코드가 조용히 덮어써서 정작 고쳐야 할 파일의 줄바꿈 문제가 드러나지 않습니다.

### A-5. 원본이 부트스트랩 스크립트로 만들던 IAM 권한을 관리형 광범위 정책으로 대체하지 않는다

**원본이 Terraform 밖에서 만든 IAM 권한까지 추적한 뒤 같은 권한 경계를 코드로 옮깁니다.** 보이지 않는 정책을 `AdministratorAccess` 같은 광범위 관리형 정책으로 대신하는 것은 변환이 아니라 권한 확대입니다.

`_monolithic/*.tf`만 보면 컨트롤러 IAM 역할의 권한을 알 수 없는 경우가 있습니다. 원본이 그 역할을 Terraform으로 만들지 않고 배스천에서 셸 스크립트를 클론해 실행했기 때문입니다.

```bash
# 007/017의 _monolithic이 실제로 하던 것
git clone https://github.com/AWS-Skills/eks-deepdive.git
/home/ec2-user/karpenter/00_install_karpenter.sh
```

그 스크립트 안에서는 다시 공개 템플릿과 `eksctl`을 호출합니다.

```bash
# 00_install_karpenter.sh - Karpenter가 공개한 getting-started 템플릿을 배포합니다
curl -fsSL .../getting-started-with-karpenter/cloudformation.yaml > "$TEMPOUT" && aws cloudformation deploy ...
eksctl create iamserviceaccount --attach-policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER_NAME" ...
```

즉 원본 컨트롤러는 **태그 조건으로 좁혀진 최소권한 정책**을 가졌지만 그 정책은 `_monolithic/*.tf`에 한 글자도 나타나지 않았습니다. 변환하는 사람에게는 정책이 없는 것처럼 보이고, 그 빈자리를 `AdministratorAccess`로 채우기 쉽습니다.

**이 확대는 `plan`과 `validate`가 알려주지 않습니다.** 두 구성의 차이는 유효한 정책 ARN 하나뿐이기 때문입니다.

#### 무엇을 하는가

- **원본이 IAM을 Terraform 밖에서 만들었다면 그 밖을 읽습니다.** 클론하는 저장소, 실행 스크립트, 스크립트가 배포하는 CloudFormation 템플릿까지 따라가 실제 정책을 찾습니다. 위 사례에서는 세 단계가 전부였습니다.
- **찾은 정책을 모듈이 직접 만듭니다.** `aws_iam_policy`와 `aws_iam_role_policy_attachment`로 선언하고 문서 본문은 `jsonencode`로 씁니다. 그러면 정책이 state와 plan에 들어오고 destroy에서도 함께 사라집니다. 외부 스크립트가 만든 CloudFormation 스택은 이 수명주기를 제공하지 않았습니다.
- **추가 정책 인터페이스의 기본값은 비웁니다.** `create_controller_policy`(기본 `true`)로 기본 정책 생성을 제어하고, `controller_policy_arns`(기본 `[]`)는 그 위에 명시적으로 더하는 용도로만 둡니다. 기본값 `[AdministratorAccess]`는 설명에 "필요하면 좁히라"고 적어도 실제로 좁아지지 않습니다.
- **정책이 다른 리소스를 참조하면 식별자를 입력으로 받습니다.** Karpenter의 `sqs:ReceiveMessage`는 인터럽션 큐 하나로 좁혀집니다. 다른 모듈이 큐를 만들면 이름과 ARN을 함께 받고, 둘 중 하나만 온 조합을 교차 변수 `validation`으로 막습니다(B-1번). 이름만 있고 ARN이 없으면 컨트롤러 로그의 `AccessDenied` 반복으로 한참 뒤에 드러납니다.

#### 원본이 정말로 광범위 정책을 붙이고 있었다면

이 경우는 숨은 최소권한 정책을 광범위 정책으로 바꾼 사례와 다릅니다. `004_batch_on_eks`의 원본은 컨트롤러 역할에 `AdministratorAccess`를 Terraform으로 명시했습니다. 이를 최소권한으로 바꾸는 것은 바람직할 수 있지만 **원본 동작을 바꾸는 설계 변경**입니다. 조회 전용인 `_monolithic/`은 그대로 두고 모듈화된 구성만 고치며, 왜 달라졌는지 주석에 남깁니다. 두 경우를 구분해야 다음 사람이 `_monolithic`과 대조하며 같은 결정을 다시 하지 않습니다.

#### 확인하는 방법

아래 감사는 컨트롤러·에이전트 역할의 숨은 권한 확대를 찾는 데 초점을 둡니다. `vscode_ec2`와 `bastion_ec2`를 제외하는 것은 검색 범위를 좁히기 위한 것일 뿐, 작업대에 광범위 IAM을 허용하는 별도 표준이 아닙니다. 작업대 권한도 실제 작업에 필요한 범위와 위험을 독립적으로 검토하고 명시적으로 정당화해야 합니다.

```bash
# 모듈이 컨트롤러 역할에 AdministratorAccess를 붙이는 곳
grep -rln 'policy/AdministratorAccess' --include='*.tf' . \
  | grep -v '/.terraform/' | grep -v '_monolithic' \
  | grep -v 'vscode_ec2' | grep -v 'bastion'

# 변수 기본값으로 숨어 있는 경우까지 보려면 default 줄을 함께 봅니다
grep -rn -B3 'policy/AdministratorAccess' --include='variables.tf' . \
  | grep -E 'variable "|default' | grep -v '_monolithic'
```
