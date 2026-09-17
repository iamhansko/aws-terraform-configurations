---
inclusion: always
---

# Terraform Configuration Rules

이 저장소의 Terraform 구성이 따르는 규칙 모음입니다. 각 규칙은 한 번 실패해 본 것을 적어둔 것이므로, "왜 이렇게 하는가"가 "무엇을 하는가"보다 길 때가 많습니다.

## 이 문서를 읽는 방법

### 규칙 ID는 `<파트>-<순번>`입니다

규칙의 이름은 그것이 속한 파트의 letter와 파트 안에서의 순번입니다: `A-1`, `A-2`, ..., `D-1`, `D-2`. 이 문서를 처음 보는 사람이 `D-1`만 보고도 "생성 순서 파트의 첫 규칙"임을 알 수 있게 하는 것이 목적입니다.

`.tf` 파일의 주석 972곳이 이 ID를 `rules.md A-1` 형태로 인용합니다. 인용을 찾을 때:

```bash
grep -rn 'rules\.md D-3' --include='*.tf' .        # 이 규칙을 근거로 삼은 코드 전부
grep -roh 'rules\.md [A-H]-[0-9]*' --include='*.tf' . | sort | uniq -c | sort -rn
```

- **규칙을 추가할 때는 해당 파트의 맨 끝에 붙이고 그 파트의 다음 순번을 씁니다.** 파트 중간에 끼워 넣으면 뒤쪽 규칙의 ID가 전부 밀리므로 하지 않습니다.
- **인용은 "왜 이렇게 썼는지"가 코드만 봐서는 드러나지 않을 때만 답니다.** 규칙을 적용했다는 표시가 아니라, 읽는 사람이 코드를 되돌리려 할 때 멈추게 하는 장치입니다. 그래서 인용 횟수는 그 규칙이 얼마나 쓰이는지와 무관합니다 — B-2번(열거값은 `contains()`로 검증)은 `variables.tf` 131개 파일에서 쓰이지만 인용은 0회입니다. `contains(["ip", "instance"], ...)`를 보고 왜 그렇게 썼는지 의아해할 사람이 없기 때문입니다. 반대로 B-5번은 158회 인용됩니다. "왜 이 값을 모듈 output으로 되돌려받는가"는 코드만 봐서는 알 수 없기 때문입니다.
- 따라서 **인용이 없다고 규칙이 안 지켜지는 것도, 인용이 많다고 더 중요한 규칙인 것도 아닙니다.** 적용 여부를 확인해야 하면 인용을 세지 말고 아래 "규칙이 지켜지는지 확인하는 방법"의 명령을 씁니다.
- **규칙을 다른 파트로 옮기면 ID가 바뀝니다.** 이것이 이 방식의 비용입니다. 옮길 때는 `.tf` 주석의 인용도 함께 고쳐야 하며(현재 339개 파일), 손으로 하지 말고 스크립트로 일괄 치환한 뒤 `grep`으로 잔여 인용이 없는지 확인합니다.
- **규칙을 폐기할 때는 ID를 비워두지 않고, 무엇이 그것을 대체하는지 본문에 적어 남겨둡니다**(E-3·E-4번이 그 예 — 판단은 유효하고 리소스 타입만 E-2번으로 대체되었습니다).

#### 예전 `#N` 번호와의 대응

2026-09 이전에는 파트 구분 없이 `#1`~`#39`를 썼습니다(그 시절 `#8`~`#11`은 첫 커밋부터 결번이었고 이유는 기록이 없습니다). 오래된 커밋·노트·리뷰 코멘트에서 `rules.md #N`을 만나면 여기서 찾습니다.

| 예전 | 현재 | 예전 | 현재 | 예전 | 현재 |
| --- | --- | --- | --- | --- | --- |
| #1 | A-1 | #16 | C-3 | #28 | C-4 |
| #2 | A-2 | #17 | B-2 | #29 | D-4 |
| #3 | B-1 | #18 | E-1 | #30 | F-1 |
| #4 | B-4 | #19 | E-4 | #31 | F-2 |
| #5 | B-5 | #20 | E-6 | #32 | B-8 |
| #6 | D-5 | #21 | C-2 | #33 | E-7 |
| #7 | B-3 | #22 | D-2 | #34 | H-1 |
| #12 | D-1 | #23 | E-5 | #35 | H-2 |
| #13 | B-7 | #24 | E-3 | #36 | A-4 |
| #14 | C-1 | #25 | A-3 | #37 | G-2 |
| #15 | B-6 | #26 | E-2 | #38 | G-1 |
| | | #27 | D-3 | #39 | G-3 |

### 규칙이 서로 어긋나 보일 때

1. **구체적인 규칙이 일반 규칙을 이깁니다.** B-8번(다른 모듈의 output은 맵으로 받는다)은 B-7번(`for_each`로 attach한다)의 예외이고, F-1번은 B-1번(모든 변수에 `validation`)의 사례입니다.
2. **"이 저장소의 실제 구현"이 "원칙"을 이깁니다.** E-1번은 무엇을 하지 말아야 하는지(userdata에서 `kubectl apply`)를 정하고, E-2번은 그 대안을 무엇으로 구현하는지를 정합니다. 충돌하면 E-2번을 따릅니다.
3. **코드가 문서를 이깁니다.** 어긋난 것을 발견하면 어느 쪽이 맞는지 판정하고 **양쪽을 맞춥니다.** 문서만 고치거나 코드만 고치고 넘어가면 다음 사람이 같은 판정을 다시 합니다.

### 저장소 기준값

| 항목 | 값 | 어디에 걸리는가 |
| --- | --- | --- |
| `required_version` | `>= 1.9` | 다른 변수를 참조하는 `validation`을 쓸 수 있습니다(B-1번). `_monolithic/`의 원본은 `>= 1.5`로 남아 있습니다 |
| AWS 프로바이더 | `~> 6.0` | `data.aws_region`의 속성 이름이 `region`입니다(5.x의 `name`이 아님) |
| Kubernetes 리소스 | `alekc/kubectl` | `hashicorp/kubernetes`는 같은 apply에서 만든 클러스터에 쓸 수 없습니다(E-2번) |
| Helm | `hashicorp/helm` | E-2번의 제약을 받지 않으므로 그대로 씁니다 |
| 적용 방식 | 단일 `terraform apply` | 클러스터와 그 안의 리소스를 두 단계로 나누지 않습니다. B-8·E-2번이 이 전제에서 나옵니다 |

### `_monolithic/`은 조회 전용입니다

`_monolithic/` 디렉토리의 파일은 **조회·분석만 가능하고, 절대로 수정하거나 삭제하지 않습니다.** CloudFormation 템플릿을 기계 변환한 원본이며, 모듈화된 구성이 무엇을 재현해야 하는지를 판정하는 기준이기 때문입니다. 원본이 하던 일을 바꾸고 싶으면 모듈화된 쪽을 고치고, 왜 달라졌는지 주석에 남깁니다.

### 규칙이 지켜지는지 확인하는 방법

규칙마다 위반을 찾아내는 명령이 본문에 붙어 있습니다. 여기서는 어디에 있는지만 가리킵니다 — 명령을 여기에 복사하면 두 곳이 어긋나기 때문입니다.

| 확인할 것 | 방법 | 규칙 |
| --- | --- | --- |
| 구성이 유효한가 (에디터의 `Unexpected attribute`가 진짜인가) | `terraform validate -json` | A-2 |
| 모듈 사본마다 변수가 다 들어갔는가 | 사본별 `grep -c 'variable "<name>"'` | A-2 |
| `description`에만 적힌 제약이 남아 있는가 | `grep -rl 'must stay'` 후 `validation` 유무 확인 | B-1 |
| `outputs.tf`와 `local.outputs`의 개수가 맞는가 | 두 블록 수 비교, `terraform console` | H-2 |
| CRLF가 섞였는가 | `grep -qU $'\r'` 순회 | A-4 |
| 포맷이 정렬되어 있는가 | `terraform fmt -check -recursive` (`_monolithic/`의 기계 변환 산출물 3개는 원래 정렬되어 있지 않습니다 — 조회 전용이므로 그대로 둡니다) | A-4 |
| Helm 값이 의도한 타입으로 렌더링되는가 | `helm template` | E-7, G-2 |
| 컨트롤러가 로드밸런서를 채택했는가 (2개가 아닌가) | `resourcegroupstaggingapi get-resources` | G-3 |

### 목차

**A. 저장소 구조 · 파일 · CloudFormation 변환**

- A-1. 디렉토리 구조
- A-2. 루트 구성과 모듈 모두 4파일 분리
- A-3. `aws_iam_instance_profile`의 `role`은 역할 이름 문자열 하나만 받는다 (CloudFormation 변환 시 흔한 버그)
- A-4. `.tf` 파일은 LF로 저장한다 (CRLF는 heredoc 종료자를 깨뜨려 셸 스크립트 전체를 실행 불가로 만든다)

**B. 변수와 인터페이스 설계**

- B-1. 변수에는 `validation` 블록을 기본으로 추가
- B-2. AMI 타입 등 AWS가 정한 고정된 열거값은 `contains()`로 검증
- B-3. 루트 구성의 하드코딩 값은 변수로 승격
- B-4. 선택적 기능은 nullable 변수 + 템플릿 디렉티브로 구현
- B-5. 모듈 입력을 그대로 모듈 출력으로 되돌려주는 패턴 (단일 진실 공급원)
- B-6. 모듈에 필요한 외부 리소스는 ID/이름 목록으로만 주입 (보안그룹 예시)
- B-7. 여러 개의 IAM 관리형 정책은 `for_each`로 attach
- B-8. 다른 모듈의 output(리소스 ID)을 `for_each`로 반복할 때는 `toset(list)`가 아니라 정적 키를 가진 `map(string)`으로 받는다

**C. 모듈 경계와 조립**

- C-1. EKS 클러스터 접근 권한 부여는 루트에서 두 모듈의 output을 연결
- C-2. IRSA(IAM Roles for Service Accounts)를 쓰는 컨트롤러는 IAM 역할과 Helm 릴리스를 같은 모듈에 둔다
- C-3. `network` 모듈은 개별 서브넷 output과 `_ids` 배열 output을 함께 노출한다 (AZ 개수는 프로젝트가 정한다)
- C-4. 모든 EKS Add-on(`aws_eks_addon`)은 각자 독립된 모듈을 가진다 (`vpc-cni`/`coredns`/`kube-proxy` 포함, 클러스터의 자동 셀프매니지드 설치는 끈다)

**D. 생성 순서와 destroy**

- D-1. IAM 역할-정책 결합 리소스는 `depends_on`으로 생성 순서를 명시
- D-2. 모듈 간 생성 순서는 `module` 블록의 `depends_on` 메타 인수로 표현
- D-3. `network` 모듈의 VPC/서브넷을 사용하는 모든 모듈은 `depends_on = [module.network]`를 명시
- D-4. `kubectl_manifest`는 EKS 클러스터가 아니라 그 매니페스트가 실제로 의존하는 노드 리소스에 `depends_on`을 걸어서, `terraform destroy`가 apply의 정확한 역순으로 진행되게 한다
- D-5. SSM Association의 순서는 `depends_on`이 아니라 마커 파일과 `until` 루프로 강제한다

**E. Kubernetes 리소스를 만드는 방법**

- E-1. EC2 userdata/SSM Association으로 만들던 쿠버네티스 리소스는 kubernetes/helm 프로바이더로 대체
- E-2. 단일 `terraform apply`가 필요하면 Kubernetes 리소스는 `hashicorp/kubernetes` 대신 `alekc/kubectl`의 `kubectl_manifest`로 선언
- E-3. Kubernetes CRD(커스텀 리소스)는 매니페스트를 HCL 객체로 그대로 선언한다
- E-4. Fargate profile 생성 후 기존 파드를 재스케줄해야 할 때는 pod 템플릿 애노테이션을 patch해서 rollout을 트리거한다
- E-5. Add-on DaemonSet의 환경변수는 `aws_eks_addon`의 `configuration_values`로 설정 (셸의 `kubectl set env` 대체)
- E-6. AWS 서비스가 EKS에 접근해야 할 때는 principal이 서비스 연결 역할인지 먼저 확인한다 (Access Entry는 서비스 연결 역할을 지원하지 않음)
- E-7. `helm_release`의 `set`은 값의 타입을 추론한다 — 문자열이어야 하는 값(annotation/label)에는 `type = "string"`을 entry별로 지정

**F. 보안 그룹**

- F-1. 보안 그룹의 `description`/`name`은 AWS 문자셋 제약을 `validation`으로 검증한다 (아포스트로피 금지, 변경 시 그룹 재생성)
- F-2. 보안 그룹 규칙은 인라인 `ingress`/`egress` 블록이 아니라 독립 규칙 리소스로 선언한다 (컨트롤러가 규칙을 추가하는 그룹에는 필수)

**G. AWS Load Balancer Controller**

- G-1. AWS Load Balancer Controller로 ALB(Ingress)와 NLB(Service)를 만드는 구성 규칙
- G-2. AWS Load Balancer Controller의 `--enable-backend-security-group`은 변수로 노출하고, `manage-backend-security-group-rules` 애노테이션을 쓰는지로 값을 결정한다
- G-3. AWS Load Balancer Controller가 만들 ALB/NLB는 Terraform이 미리 만들고 컨트롤러가 채택(adopt)하게 한다

**H. EC2 작업대와 산출물 전달**

- H-1. EKS 클러스터와 `vscode_ec2`가 같은 루트 모듈에 함께 선언되면 code-server, kubectl, eksctl, helm, docker를 **모두** 설치한다
- H-2. 루트 `outputs.tf`의 모든 값은 SSM Association으로 `vscode_ec2`의 `README.md`에도 기록한다 (마커 파일로 순서 강제)

## A. 저장소 구조 · 파일 · CloudFormation 변환

프로젝트를 처음 만들거나 `_monolithic` 산출물을 모듈로 쪼갤 때 먼저 읽습니다. 파일이 어디에 놓이고 어떤 바이트로 저장되는지에 관한 규칙입니다.

### A-1. 디렉토리 구조

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

### A-2. 루트 구성과 모듈 모두 4파일 분리

루트 구성(`main.tf`가 있던 폴더)과 각 모듈 모두 아래 4개 파일로 분리합니다:

- `providers.tf` — `terraform` 블록(`required_version`, `required_providers`)과 `provider "aws"` (루트만 해당; 모듈에는 `provider` 블록 없이 `required_providers`만).
- `variables.tf` — 모든 `variable` 선언.
- `main.tf` — `data` 소스, `resource`, `module` 블록만 (변수/출력 선언 없음).
- `outputs.tf` — 모든 `output` 선언.

#### 모듈 호출의 `Unexpected attribute`는 먼저 `terraform validate`로 판정합니다

```
Unexpected attribute: An attribute named "enable_backend_security_group" is not expected here
```

`module` 블록에 모듈이 선언하지 않은 인수를 넘기면 나는 오류입니다. 다만 **모듈의 `variables.tf`를 에디터 밖에서 고친 직후라면 실제 원인이 아닐 수 있습니다.** A-1번 패턴 때문에 이 저장소는 같은 모듈을 변형마다 복제해서 갖고 있고, 그래서 여러 사본을 스크립트로 한꺼번에 수정하는 일이 잦습니다. 그렇게 파일이 바뀌면 에디터의 Terraform language server가 예전 변수 목록을 그대로 들고 있다가, 정상인 `module` 호출에 이 오류를 표시합니다.

판정 기준은 CLI입니다.

```bash
terraform validate            # 여기서 통과하면 구성은 유효합니다
terraform validate -json      # valid / error_count 를 기계적으로 확인
```

- CLI가 통과하고 에디터만 오류를 표시하면 language server를 재시작(또는 `terraform init` 재실행)해서 재색인시킵니다.
- CLI도 같은 오류를 내면 진짜 누락입니다. 모듈 사본 **전부**에 변수가 들어갔는지 확인합니다 — 한 사본만 빠뜨리는 것이 이 구조에서 가장 흔한 실수입니다.

```bash
# 루트가 넘기는 인수와 모듈이 선언한 변수의 개수가 맞는지 사본별로 대조
for d in */modules/<module_name>; do
  printf '%s %s\n' "$d" "$(grep -c 'variable "<name>"' $d/variables.tf)"
done
```

### A-3. `aws_iam_instance_profile`의 `role`은 역할 이름 문자열 하나만 받는다 (CloudFormation 변환 시 흔한 버그)

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

### A-4. `.tf` 파일은 LF로 저장한다 (CRLF는 heredoc 종료자를 깨뜨려 셸 스크립트 전체를 실행 불가로 만든다)

`.tf` 파일이 CRLF로 저장되면 heredoc 안의 리터럴 줄이 모두 `\r`로 끝납니다. 그러면 셸 heredoc의 종료자가 `EOF`가 아니라 **`EOF\r`**이 되고, 셸은 이것을 종료자로 인정하지 않습니다. heredoc이 파일 끝까지 이어지고 스크립트 전체가 파싱에 실패합니다 — **한 줄도 실행되지 않습니다.**

H-2번 패턴의 SSM Association에서 이 문제가 발생하면 원인을 짐작할 수 없는 형태로 나타납니다.

```
Error: waiting for SSM Association (...) create: unexpected state 'Failed', wanted target 'Success'
```

#### 진단 절차

SSM은 실패 사실만 알려주므로, 실제 원인은 명령 실행 결과에서 꺼냅니다.

```bash
aws ssm describe-association-executions --association-id <id>
aws ssm describe-association-execution-targets --association-id <id> --execution-id <exec-id>
# OutputSource.OutputSourceId가 run command의 command-id입니다
aws ssm get-command-invocation --command-id <command-id> --instance-id <instance-id>
#   "StandardErrorContent": "_script.sh: line 113: syntax error: unexpected end of file"
#   "ExecutionElapsedTime": "PT0.018S"
```

**`ExecutionElapsedTime`이 0.0x초면 명령이 실행된 게 아니라 파싱에서 실패한 것입니다.** D-5번 패턴의 `until` 루프는 시작조차 하지 않았으므로, 마커 파일이나 `wait_for_success_timeout_seconds`를 의심할 필요가 없습니다.

AWS가 실제로 받은 문자열을 보면 확정할 수 있습니다.

```bash
aws ssm describe-association --association-id <id> --query 'AssociationDescription.Parameters.commands'
# [ "until [ -f /run/terraform/userdata ]; do sleep 10; done\r\ncat > /home/ec2-user/README.md << 'TFREADME'\r\n# eks-cluster\n\n..." ]
#   ^ 템플릿 리터럴 줄은 \r\n, 보간된 readme_body는 \n - 그래서 종료자만 TFREADME\r이 됩니다
```

`terraform` 쪽에서는 파일의 바이트를 직접 확인합니다. `_monolithic`은 조회 전용이므로 제외합니다.

```bash
find . -name '*.tf' -not -path '*/.terraform/*' -not -path '*_monolithic*' \
  | while read f; do grep -qU $'\r' "$f" && echo "CRLF: $f"; done
```

#### 예방

- **`.gitattributes`에 `*.tf text eol=lf`를 둡니다.** 단 이는 git이 추적하는 파일에만 적용되므로, 아직 커밋되지 않은 파일에는 효력이 없습니다. 새 프로젝트를 만든 직후가 가장 위험한 시점입니다.
- **파일을 프로그램으로 수정할 때 텍스트 모드로 쓰지 않습니다.** 이 저장소에서 CRLF가 유입된 실제 경로가 이것이었습니다. Python `pathlib.Path.write_text()`는 Windows에서 `\n`을 `\r\n`으로 변환하므로, LF를 유지해야 하면 `write_bytes()`를 쓰거나 `newline="\n"`을 명시합니다.

```python
# 잘못됨 - Windows에서 파일 전체가 CRLF가 됩니다
path.write_text(text, encoding="utf-8")
# 올바름
path.write_bytes(text.encode("utf-8"))
```

- **`terraform fmt`는 범인이 아닙니다.** 파일을 다시 쓸 때도 기존 LF를 그대로 보존합니다. 원인을 찾을 때 여기서 시간을 쓰지 않습니다.
- 로컬의 `bash -n`으로는 재현되지 않을 수 있습니다. Git for Windows(MSYS)의 bash는 `\r`을 관용하지만 Amazon Linux의 bash는 그렇지 않아서, 인스턴스에서만 실패합니다. 진단은 위의 `get-command-invocation` 출력으로 합니다.
- 이 문제는 heredoc에만 국한되지 않습니다. `\r`은 셸에게 평범한 문자라서 `done\r`은 `done`이 아니고 `fi\r`은 `fi`가 아닙니다. CRLF는 스크립트 어디에 있어도 위험합니다.
- E-5번 패턴의 `configuration_values`처럼 heredoc으로 만드는 설정 파일(Fluent Bit `.conf` 등)도 같은 영향을 받습니다. 모든 지시어 값 끝에 `\r`이 붙어 파서가 값의 일부로 읽습니다.

#### `replace(..., "\r\n", "\n")`를 설정에 넣지 않습니다

문자열이 AWS로 넘어가는 지점마다 `replace()`로 CR을 제거하는 방어도 가능하지만, 이 저장소는 그렇게 하지 않습니다. 파일을 LF로 유지하는 것이 근본 해결이고, 방어 코드는 heredoc마다 다음과 같은 잡음을 남기면서 원인을 가립니다.

```hcl
# 이렇게 하지 않습니다
commands = replace(<<-EOT
  ...
  EOT
  , "\r\n", "\n")
```

- heredoc 종료자 줄에는 마커만 올 수 있어 `replace()`의 나머지 인자가 다음 줄로 밀려나므로, 읽는 사람에게 heredoc이 끝난 위치가 불분명해집니다(B-4번 패턴의 `EOT : ""`가 `Error: Invalid expression`으로 거부되는 것과 같은 제약).
- CRLF가 이미 유입된 상황을 코드가 조용히 덮어써서, 정작 고쳐야 할 파일의 줄바꿈 문제가 드러나지 않습니다.

## B. 변수와 인터페이스 설계

모듈과 루트가 값을 주고받는 방법입니다. 두 축으로 정리됩니다.

**잘못된 값을 `plan` 단계에서 막는다** — B-1번이 원칙이고, B-2번(열거형)과 F-1번(보안 그룹 문자셋)이 그 사례입니다. 위반의 결과가 Terraform 밖(AWS API, 컨트롤러, 부팅 스크립트)에서만 드러나는 값일수록 이 축의 가치가 큽니다.

**값을 한 곳에만 둔다** — 세 규칙이 같은 목적을 서로 다른 지점에서 달성합니다. B-3번은 루트의 리터럴을 변수로 올리고, B-5번은 모듈이 받은 값을 output으로 되돌려 호출자가 다시 적지 않게 하고, H-2번은 output과 README가 하나의 맵을 보게 만듭니다. 값이 두 곳에 있으면 어긋나고, 어긋난 것을 `apply`는 알려주지 않습니다.

### B-1. 변수에는 `validation` 블록을 기본으로 추가

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

#### `description`에 쓴 제약은 강제되지 않습니다

"Must stay true", "이 변형에서는 ip만" 같은 문장을 설명에만 적어두면 아무것도 막지 못합니다. 그런 문장이 있다는 것은 **`validation`으로 옮겨야 하는 제약을 발견했다는 신호**입니다. 특히 위반의 결과가 Terraform 밖(AWS API, 쿠버네티스 컨트롤러, 부팅 스크립트)에서만 드러나는 경우 `plan`은 깨끗하게 통과하고, 실패는 한참 뒤에 전혀 다른 모습으로 나타납니다.

```hcl
# 이것만으로는 아무도 막지 못합니다
variable "enable_backend_security_group" {
  description = "... Must stay true in this variant ..."
}

# 제약을 실제로 강제합니다
variable "enable_backend_security_group" {
  type    = bool
  default = true

  validation {
    condition     = var.enable_backend_security_group
    error_message = "enable_backend_security_group must be true in this variant, because ... (rules.md G-2)."
  }
}
```

- **다른 변수를 참조하는 `validation`을 쓸 수 있습니다.** 저장소가 `required_version = ">= 1.9"`이므로 "A가 켜져 있으면 B는 true여야 한다"를 조건에 그대로 적습니다. 두 변수의 조합이 잘못된 것을 막는 데는 이 형태가 정확합니다 — 각 변수를 따로 검증하면 표현할 수 없는 제약입니다.

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

- **기존의 상수 조건(`condition = var.x`)도 그대로 유효합니다.** 제약이 실제로 "이 변형에서는 이 값만"인 경우(G-2번의 예시)는 참조할 다른 변수가 없으므로 상수 조건이 맞는 표현입니다. 1.9로 올라갔다고 해서 그것을 교차 참조로 바꿔야 하는 것은 아니며, **제약의 성질이 조합에 관한 것일 때만** 교차 참조를 씁니다.
- `_monolithic/`의 원본은 `>= 1.5`로 남아 있습니다. 조회 전용이므로 손대지 않습니다.
- 조건이 변형마다 다른 것은 정상입니다. 같은 변수가 한 변형에서는 `false`만, 다른 변형에서는 `true`만 유효할 수 있고, 각 변형이 자기 모듈을 독립적으로 소유하므로(A-1번 패턴) 서로 다른 `validation`을 갖는 것이 맞습니다.
- `error_message`에는 **유효한 대안을 함께 적습니다.** "이 값은 안 된다"로 끝내지 말고, 그 값을 쓰려면 무엇을 함께 바꿔야 하는지(또는 어느 변형이 그 형태를 보여주는지) 가리킵니다.
- 애초에 **잘못된 조합을 표현할 수 없게 만드는 것**이 가장 낫습니다. 어떤 값이 다른 값에서 유도된다면 변수로 두지 말고 `local`로 파생시킵니다(G-1번 패턴의 ALB Service 타입이 이 경우).
- 감사 방법: 변수 설명에 제약 문장이 있는데 `validation` 블록이 없는 변수를 찾습니다.

```bash
# description에 "must stay" 류 문장이 있으면서 validation이 없는 변수 찾기
grep -rl --include=variables.tf 'must stay\|Must stay' . | while read f; do
  echo "check: $f"
done
```

### B-2. AMI 타입 등 AWS가 정한 고정된 열거값은 `contains()`로 검증

B-1번 패턴의 사례입니다. B-1번이 "모든 변수에 `validation`을 넣는다"를 정하고, 이 규칙은 값의 종류가 열거형일 때 그 조건을 어떻게 쓰는지를 정합니다.

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

### B-3. 루트 구성의 하드코딩 값은 변수로 승격

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

### B-4. 선택적 기능은 nullable 변수 + 템플릿 디렉티브로 구현

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

이렇게 하면 이 기능이 필요 없는 변형(`cloud_init_status`)은 `marker_file_path`를 아예 넘기지 않아도 되고, 모듈은 특정 변형의 존재를 몰라도 됩니다 (낮은 결합도). 이 패턴은 모듈이 변형 간에 공유되든(예전 구조) 변형별로 독립 소유되든(현재 구조, A-1번 항목 참고) 동일하게 적용됩니다.

### B-5. 모듈 입력을 그대로 모듈 출력으로 되돌려주는 패턴 (단일 진실 공급원)

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

### B-6. 모듈에 필요한 외부 리소스는 ID/이름 목록으로만 주입 (보안그룹 예시)

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

### B-7. 여러 개의 IAM 관리형 정책은 `for_each`로 attach

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

**`toset(list)`을 쓸 수 있는 것은 값이 설정 파일에만 있기 때문입니다.** 관리형 정책 ARN은 리터럴 문자열이라 `plan` 시점에 이미 알려져 있고, `for_each`의 키가 될 수 있습니다. 반복할 값이 **다른 모듈의 output이나 아직 만들어지지 않은 리소스의 속성**이면 이 형태를 쓸 수 없으며, 그때는 B-8번 패턴대로 정적 키를 가진 `map(string)`으로 받습니다. 두 규칙은 충돌하는 것이 아니라 값의 출처로 갈라집니다.

### B-8. 다른 모듈의 output(리소스 ID)을 `for_each`로 반복할 때는 `toset(list)`가 아니라 정적 키를 가진 `map(string)`으로 받는다

`for_each`의 **키**는 `plan` 단계에서 결정되어야 합니다. 리소스 주소(`resource["key"]`)를 만드는 값이기 때문입니다. `toset(var.ids)`로 집합을 만들면 **값이 곧 키**가 되는데, 그 값이 아직 만들어지지 않은 리소스의 속성(예: `module.vscode_ec2.security_group_id`)이라면 plan 시점에 unknown이므로 다음 에러로 실패합니다. 원소 **개수**를 아는 것만으로는 부족합니다.

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

B-6번 패턴(모듈에 필요한 외부 리소스는 ID/이름 목록으로만 주입)으로 받은 값을 그대로 `toset()`에 넣으면 거의 항상 이 상황이 됩니다. 그 값의 출처가 **다른 모듈의 output = 아직 생성되지 않은 리소스의 속성**이기 때문입니다. 따라서 모듈은 `list(string)`이 아니라 **호출자가 정한 라벨을 키로 하는 `map(string)`**으로 받고, `toset()` 없이 맵을 그대로 `for_each`에 넣습니다. 에러 메시지가 안내하는 "키는 설정에 정적으로 정의하고 값에만 apply 시점 결과를 담는다"가 바로 이 형태입니다.

```hcl
# 모듈 variables.tf
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = "Security group IDs allowed inbound on port, keyed by a caller-chosen label ... A map rather than a list because these IDs are usually another module's output, unknown until apply, and for_each needs statically known keys"

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in the rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens."
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

- 키는 반드시 **리터럴 문자열**이어야 합니다. `{ (module.vscode_ec2.security_group_id) = ... }`처럼 unknown 값을 키로 쓰면 아무것도 해결되지 않습니다.
- 검증은 `keys()`/`values()`로 나눠서 씁니다. 값(ID)이 unknown인 동안 Terraform은 그 `validation`을 apply까지 미루지만, 키 검증은 plan 단계에서 즉시 동작합니다.
- `each.key`를 보안 그룹 규칙의 `description`에 넣으면 규칙마다 출처가 드러나 plan을 읽기 쉬워집니다. 대신 키가 F-1번 패턴의 문자셋 제약(아포스트로피 금지)을 위반하지 않도록 위 `validation`으로 라벨 문자셋을 제한합니다.
- 반대로 **값이 설정 파일에만 있는 정적 리스트**(예: `ingress_cidr_blocks`, B-7번 패턴의 `node_iam_policy_arns` 같은 관리형 정책 ARN 목록)는 plan 시점에 이미 알려져 있으므로 `toset(list)`을 그대로 씁니다. 이 패턴은 "리스트를 전부 맵으로 바꾼다"는 뜻이 아니라, **값의 출처가 다른 리소스/모듈이면 맵으로 받는다**는 뜻입니다.
- `-target`으로 두 번 나눠 apply하는 것은 에러 메시지가 제시하는 우회책일 뿐입니다. 이 저장소는 단일 `terraform apply`로 전체가 만들어져야 하므로(E-2번 패턴과 같은 이유) 설정 자체를 맵으로 고칩니다.
- 같은 제약이 `dynamic` 블록의 `for_each`(예: 인라인 `dynamic "ingress"`)에도 적용됩니다. 인라인 블록을 유지하는 그룹(F-2번 패턴의 예외)에서도 소스 ID 목록은 동일하게 맵으로 받습니다.

## C. 모듈 경계와 조립

무엇을 한 모듈에 넣고 무엇을 루트에서 잇는지에 관한 규칙입니다.

### C-1. EKS 클러스터 접근 권한 부여는 루트에서 두 모듈의 output을 연결

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

### C-2. IRSA(IAM Roles for Service Accounts)를 쓰는 컨트롤러는 IAM 역할과 Helm 릴리스를 같은 모듈에 둔다

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

- `helm_release`는 역할 ARN을 변수로 받지 않고, 같은 모듈 안의 `aws_iam_role` 리소스를 직접 참조합니다. B-6/C-1번 패턴(모듈 경계를 넘는 결합은 ID/ARN을 변수로 주입)은 **서로 다른 책임을 가진 모듈 사이**에 적용하는 규칙이며, 이 경우처럼 하나의 컴포넌트(Karpenter)를 구성하는 IAM+Helm은 애초에 분리할 이유가 없는 강결합이므로 한 모듈로 유지합니다.
- 이 모듈의 `providers.tf`는 `aws`와 `helm` 양쪽 `required_providers`를 모두 선언합니다.
- IAM 역할이 필요한 이유가 사라지면(예: IRSA 대신 Pod Identity로 전환) 모듈 하나만 교체하면 되므로, "이 컨트롤러를 설치하는 데 필요한 모든 것"이 한 곳에 모여 있어 유지보수가 쉬워집니다.

### C-3. `network` 모듈은 개별 서브넷 output과 `_ids` 배열 output을 함께 노출한다 (AZ 개수는 프로젝트가 정한다)

이 규칙은 두 가지를 말하며, 둘은 독립적입니다.

**(1) AZ 개수는 그 프로젝트가 무엇을 올리는지가 정합니다.** EKS처럼 컨트롤 플레인 배치가 다중 AZ를 요구하는 프로젝트는 서브넷을 A/B/C 3벌로 확장합니다(`cidrsubnet(..., 5)`까지 사용). 반면 VPC 자체를 보여주는 기본 프로젝트(`014_basic_ec2`, `015_basic_vpc_and_subnets`)는 A/B 2벌입니다 — 3-AZ는 VPC의 요구사항이 아니고, AZ마다 NAT 게이트웨이 비용이 붙기 때문입니다. **"항상 3개"가 아니라 "필요한 만큼"이고, 그 이유를 모듈 주석에 남깁니다.**

**(2) output 형태는 AZ 개수와 무관하게 동일합니다.** 개별 서브넷 output(`public_subnet_a_id` 등)과, 호출자가 리스트로 바로 쓸 수 있는 배열 output을 **항상 함께** 노출합니다. 2-AZ든 3-AZ든 배열 output의 이름은 같으므로, AZ를 늘려도 호출자 코드는 그대로입니다.

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

### C-4. 모든 EKS Add-on(`aws_eks_addon`)은 각자 독립된 모듈을 가진다 (`vpc-cni`/`coredns`/`kube-proxy` 포함, 클러스터의 자동 셀프매니지드 설치는 끈다)

EKS는 클러스터를 만들 때 기본적으로 `vpc-cni`, `coredns`, `kube-proxy`를 **셀프매니지드(self-managed)** 애드온으로 자동 설치합니다. 이 상태에서 같은 이름의 `aws_eks_addon` 리소스를 추가로 만들면 "이미 존재하는 리소스와 충돌"이 발생하거나, Terraform이 이 세 애드온의 존재/버전/설정을 전혀 추적하지 못하는 상태(클러스터 콘솔에는 보이지만 상태 파일에는 없음)가 됩니다. 이 셋을 오직 Amazon EKS 애드온(관리형)으로만 존재하게 하려면, `aws_eks_cluster`에 `bootstrap_self_managed_addons = false`를 설정하고 세 개 모두를 `aws_eks_addon`으로 명시적으로 선언합니다.

**일반 원칙: 모든 EKS Add-on은 각자의 모듈을 가진다.** 이 규칙은 `vpc-cni`/`coredns`/`kube-proxy`에만 한정되지 않고, 이후 프로젝트에 추가하는 모든 `aws_eks_addon`(예: `aws-ebs-csi-driver`, `aws-efs-csi-driver`, `aws-mountpoint-s3-csi-driver`, `amazon-cloudwatch-observability`, `adot` 등)에 동일하게 적용합니다. 여러 Add-on을 하나의 모듈에 묶지 않고 `eks_<addon_name_snake_case>_addon`(예: `eks_vpc_cni_addon`, `eks_ebs_csi_driver_addon`) 이름의 모듈을 Add-on 하나당 하나씩 만듭니다. 이유는 세 가지입니다.

1. **생성/업그레이드 순서가 Add-on마다 다를 수 있습니다.** 아래에서 다루는 `coredns`(노드 용량 필요) vs `vpc-cni`/`kube-proxy`(불필요)의 상반된 순서 요구사항이 대표적인 예이지만, 다른 Add-on도 각자 다른 전제조건을 가질 수 있습니다(예: `aws-ebs-csi-driver`는 IRSA 역할이 먼저 있어야 함, `amazon-cloudwatch-observability`는 CloudWatch 네임스페이스/로그그룹이 먼저 있어야 함). 여러 Add-on이 한 모듈에 있으면 그 모듈 전체가 가장 엄격한 선행조건에 맞춰야 하므로, 다른 Add-on들이 불필요하게 늦게 생성됩니다.
2. **버전 관리와 blast radius가 Add-on별로 독립적입니다.** 각 Add-on은 AWS가 서로 다른 시점에 서로 다른 버전을 릴리스합니다(예: `vpc-cni`에만 보안 패치가 나와도 `coredns`/`kube-proxy`는 그대로 두어야 함). 하나의 모듈에 묶여 있으면 `terraform plan`에서 한 Add-on의 버전만 바꿔도 그 모듈의 다른 리소스까지 diff에 섞여 보이고, 실수로 `-target`을 잘못 지정하지 않는 한 항상 다른 Add-on들과 함께 apply/destroy 대상이 됩니다.
3. **`configuration_values`의 JSON 스키마가 Add-on마다 완전히 다릅니다**(E-5번 패턴). 모듈이 분리되어 있으면 각 모듈의 `variables.tf`가 그 Add-on 고유의 설정 변수만 선언하므로, 스키마가 섞여서 헷갈릴 일이 없습니다.

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

**생성 순서 주의사항 (rules.md D-2 적용):**

- `vpc-cni`/`kube-proxy`는 DaemonSet이라 노드가 0개여도 `desired == ready == 0`으로 즉시 `ACTIVE`가 됩니다. 오히려 노드 자체가 클러스터에 Ready로 조인하려면 이 둘이 먼저 존재해야 하므로, `eks_vpc_cni_addon`/`eks_kube_proxy_addon` 모듈은 **노드 생성 리소스(관리형 노드그룹/Fargate profile/Karpenter)보다 먼저** 생성되어야 합니다. `bootstrap_self_managed_addons = false`인 클러스터에서는 이 둘이 존재하기 전에는 워커 노드가 정상적으로 조인할 수 없습니다.
- `coredns`는 Deployment(파드)이므로 스케줄될 수 있는 노드 용량이 있어야 `DEGRADED` 상태를 벗어나 `ACTIVE`가 됩니다. 노드 용량 없이 `coredns` 애드온을 먼저 만들면 `Error: ... timeout while waiting for state to become 'ACTIVE' (last state: 'DEGRADED', timeout: 20m0s)`로 실패합니다 (`terraform-aws-modules/terraform-aws-eks`의 [#3062](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3062), [#2069](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2069)에 보고된 것과 동일한 증상). 따라서 `eks_coredns_addon` 모듈은 관리형 노드그룹을 쓰는 프로젝트라면 `depends_on = [module.eks_node_group]`을, Fargate profile을 쓰는 프로젝트(E-4번 패턴)라면 `depends_on = [module.eks_fargate_profile]`을 걸어서 **노드 생성 리소스보다 나중에** 생성되게 합니다.
- 정리하면 한 프로젝트 안에서의 순서는 `eks_cluster` → `eks_vpc_cni_addon`/`eks_kube_proxy_addon` → 노드 생성 리소스(`eks_node_group`/`eks_fargate_profile`/Karpenter) → `eks_coredns_addon`입니다. Karpenter처럼 노드를 만드는 컨트롤러 자체가 CoreDNS에 의존해 동작하는 경우(D-2번 패턴)는 `eks_coredns_addon` 뒤에 오도록 순서가 한 번 더 꼬일 수 있으니, 실제로 무엇이 무엇을 필요로 하는지 프로젝트별로 확인합니다.

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

## D. 생성 순서와 destroy

Terraform의 암묵적 그래프는 **값 참조**만 따라갑니다. `a = module.x.y`는 그 값을 만든 **특정 리소스**까지만 순서를 잡고, 그 모듈의 나머지 리소스나 "그 리소스가 실제로 동작하기 시작하는 시점"과는 아무 관계가 없습니다. 값 참조가 없는 런타임 선행조건은 전부 직접 표현해야 하며, 이 파트의 규칙은 모두 그 원칙의 적용 사례입니다.

무엇을 쓸지는 경계가 어디인지로 갈립니다.

| 상황 | 쓰는 것 | 규칙 |
| --- | --- | --- |
| 같은 모듈 안의 리소스가 IAM 정책 attachment 등을 기다려야 함 | 리소스의 `depends_on` | D-1 |
| 다른 모듈이 준비된 뒤여야 하는데 값 참조가 없음 | `module` 블록의 `depends_on` | D-2 |
| `network` 모듈이 있는 루트의 모든 모듈 | `module` 블록의 `depends_on` (**필수**) | D-3 |
| 클러스터 API 서버로 직접 요청하는 리소스, `destroy` 역순이 필요 | 매니페스트가 의존하는 **노드 리소스**를 가리키는 `depends_on` | D-4 |
| 원격 셸 명령의 완료를 기다려야 함 | `depends_on`이 아니라 **마커 파일 + `until` 루프** | D-5 |

마지막 행이 이 파트에서 유일하게 `depends_on`으로 풀지 않는 경우입니다. 같은 마커 파일 메커니즘을 B-4번(userdata가 마커를 만드는 위치)과 H-2번(README를 쓰는 association이 그 마커를 기다림)이 함께 씁니다.

### D-1. IAM 역할-정책 결합 리소스는 `depends_on`으로 생성 순서를 명시

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

### D-2. 모듈 간 생성 순서는 `module` 블록의 `depends_on` 메타 인수로 표현

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

`karpenter` 모듈은 `eks_fargate_profile` 모듈의 output을 전혀 쓰지 않으므로(값 참조로는 암묵적 의존관계가 생기지 않음), Terraform 그래프만 보면 두 모듈이 동시에 생성될 수 있습니다. 하지만 Karpenter 컨트롤러 파드가 뜨려면 CoreDNS가 (Fargate profile 생성 후 E-4번 패턴으로 재스케줄되어) 먼저 응답 가능한 상태여야 하므로, 이 실제 런타임 의존성을 `depends_on`으로 명시적으로 표현합니다. D-1번 패턴(리소스 레벨 `depends_on`)과 동일한 이유이며, 적용 대상이 리소스가 아니라 모듈 블록이라는 점만 다릅니다.

### D-3. `network` 모듈의 VPC/서브넷을 사용하는 모든 모듈은 `depends_on = [module.network]`를 명시

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

- 이는 D-2번 패턴(모듈 간 `depends_on`)의 특수 사례이며, `network` 모듈에 대해서는 선택이 아니라 **필수**로 적용합니다.
- `network`의 output을 전혀 쓰지 않는 모듈(예: `key_pair`)에도 동일하게 `depends_on = [module.network]`를 추가해서, 루트의 모든 리소스/모듈이 `network` 완성 이후에만 시작되도록 통일합니다.
- 값 참조가 있는 모듈이든 없는 모듈이든 규칙은 동일합니다: **루트에 `module "network"` 블록이 있는 프로젝트라면, 다른 모든 `module` 블록에 `depends_on = [module.network]`를 추가합니다.**

### D-4. `kubectl_manifest`는 EKS 클러스터가 아니라 그 매니페스트가 실제로 의존하는 노드 리소스에 `depends_on`을 걸어서, `terraform destroy`가 apply의 정확한 역순으로 진행되게 한다

E-2번 패턴처럼 EKS 클러스터와 `kubectl_manifest` 리소스를 같은 루트 모듈, 같은 `apply`에서 함께 만드는 경우, `provider "kubectl"`은 `module.eks_cluster.cluster_endpoint`/`certificate_authority_data`를 참조하지만 이는 **provider 설정값 참조**일 뿐이라 리소스 레벨 의존관계만큼 강하게 Terraform 그래프에 반영되지 않습니다. `kubectl_manifest` 리소스 자체에 `depends_on`이 없으면 `terraform destroy`가 EKS 클러스터(또는 그 노드 리소스)를 CRD/매니페스트보다 먼저 삭제하려고 시도할 수 있고, 그 순간부터 API 서버가 이미 사라졌거나(클러스터 삭제) 컨트롤러 파드가 이미 죽어서(노드 삭제) `kubectl_manifest`의 삭제 자체가 실패합니다.

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
  # waiting on a controller that no longer exists (rules.md D-4).
  depends_on = [var.node_group_dependency]
}
```

- 모듈이 노드 리소스의 존재를 직접 알지 못하게 하려면(B-6번 패턴), 노드 리소스를 가리키는 값을 루트에서 `depends_on`용 변수로 주입하지 않고, **루트 `main.tf`의 `module` 블록 자체에 `depends_on`을 겁니다** (D-1/D-2번 패턴과 동일한 방식 - 모듈 내부 리소스 각각이 아니라 모듈 경계에서 순서를 표현).

```hcl
# 루트 main.tf
module "pod_security_group_policy" {
  source = "./modules/pod_security_group_policy"

  vpc_id          = module.network.vpc_id
  create_demo_pod = var.create_demo_pod

  # default_sgp/demo_pod (kubectl_manifest) need a live vpc-resource-
  # controller pod, which runs on the node group; ordering the module
  # itself after the node group makes `terraform destroy` remove these
  # manifests before the node group disappears (rules.md D-4).
  depends_on = [module.network, module.eks_node_group]
}
```

- 노드 리소스가 여러 개(예: 004번 프로젝트처럼 Fargate profile과 Karpenter가 함께 있는 경우)라면, 그 매니페스트가 스케줄되는 **구체적인 노드 리소스**를 `depends_on`에 넣습니다. 막연히 "가장 마지막에 만들어지는 모듈"을 넣지 않고, 실제로 어떤 컨트롤러/파드가 이 매니페스트를 처리하는지부터 확인합니다.
- 이 규칙은 `eks_vpc_cni_addon`/`eks_kube_proxy_addon`/`eks_coredns_addon`을 포함한 모든 Add-on 모듈(C-4번 패턴)의 `aws_eks_addon` 리소스에는 적용되지 않습니다. `aws_eks_addon`은 AWS 프로바이더가 EKS API로 직접 삭제를 요청하는 리소스라 클러스터의 API 서버나 컨트롤러 파드에 별도로 접속할 필요가 없기 때문입니다. 이 규칙은 오직 **클러스터 내부의 Kubernetes API 서버로 직접 요청을 보내는** `kubectl_manifest`(및 E-2번 패턴이 대체하기 전의 `kubernetes_manifest`/`kubernetes_annotations` 등 `hashicorp/kubernetes` 타입드 리소스 전체)에만 적용됩니다.

### D-5. SSM Association의 순서는 `depends_on`이 아니라 마커 파일과 `until` 루프로 강제한다

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

## E. Kubernetes 리소스를 만드는 방법

EC2 안에서 `kubectl`/`helm`을 실행하는 대신 프로바이더 리소스로 선언하는 규칙입니다. **E-1번이 원칙, E-2번이 이 저장소의 실제 구현**이고, E-3·E-4번은 E-2번으로 대체된 형태를 남겨둔 것이므로 그 순서로 읽습니다.

### E-1. EC2 userdata/SSM Association으로 만들던 쿠버네티스 리소스는 kubernetes/helm 프로바이더로 대체

> **이 규칙은 "무엇을 하지 않는가"를 정합니다.** userdata나 `aws_ssm_association`에서 `kubectl apply`/`helm install`로 리소스를 만들지 않는다는 것이 요지이며, 그것이 여전히 유효합니다.
>
> **"무엇으로 대체하는가"는 E-2번이 정합니다.** 아래 예시는 Kubernetes 쪽을 `hashicorp/kubernetes`로 적었지만, 이 저장소는 그 프로바이더를 쓰지 않습니다 — 같은 `apply`에서 만든 클러스터에는 `plan` 단계에서 구성이 불가능하기 때문입니다. 타입드 리소스(`kubernetes_namespace`, `kubernetes_cluster_role`, ...)와 `kubernetes_manifest`는 전부 `alekc/kubectl`의 `kubectl_manifest`로 대체됩니다. Helm(`helm_release`)은 이 제약을 받지 않으므로 아래 내용 그대로 유효합니다.
>
> 즉 새 코드를 쓸 때는 **E-1번의 판단 + E-2번의 리소스 타입**을 함께 적용합니다.

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

### E-2. 단일 `terraform apply`가 필요하면 Kubernetes 리소스는 `hashicorp/kubernetes` 대신 `alekc/kubectl`의 `kubectl_manifest`로 선언

> **이 규칙이 E-1·E-3·E-4번의 리소스 타입을 대체합니다.** 그 세 규칙의 판단(셸에서 만들지 않는다 / 애노테이션으로 rollout을 트리거한다 / 매니페스트를 그대로 옮긴다)은 유효하고, 그것을 담는 리소스만 여기서 정해집니다. Kubernetes 쪽 예시가 `kubernetes_*`로 적힌 곳을 보면 이 규칙으로 읽습니다.

`hashicorp/kubernetes` 프로바이더(타입드 리소스인 `kubernetes_namespace`/`kubernetes_cluster_role`/`kubernetes_role_binding`/`kubernetes_annotations`뿐 아니라 E-3번 패턴의 `kubernetes_manifest`도 포함)는 신규 EKS 클러스터를 만드는 것과 같은 루트 모듈, 같은 `apply`에서 클러스터에 리소스를 배포하려고 하면 `Error: Failed to construct REST client ... cannot create REST client: no client config` 에러로 실패합니다. 원인은 Terraform이 `plan` 단계에서 프로바이더를 미리 구성하는데, `module.eks_cluster.cluster_endpoint`/`certificate_authority_data`처럼 아직 존재하지 않는 리소스의 output은 그 시점에 값이 알려지지 않은(unknown) 상태이기 때문입니다. HashiCorp도 공식적으로 "클러스터와 그 클러스터의 Kubernetes 리소스는 별도의 root module/state로 분리하라"고 권장합니다.

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
- `roleRef`/`subjects`처럼 이름을 리터럴 문자열로만 주고받는 관계(속성 참조가 아님)는 D-1번 패턴과 같은 이유로 `depends_on`을 명시합니다.
- E-4번 패턴(`kubernetes_annotations`의 `template_annotations`로 rollout 트리거)은 `kubectl_manifest`로는 `spec.template.metadata.annotations`만 채운 부분 매니페스트를 apply해서 동일하게 구현합니다. `timestamp()`가 매 apply마다 값이 바뀌므로 `lifecycle.ignore_changes = [yaml_body]`로 최초 1회만 반영되게 막습니다 (`kubernetes_annotations`의 `ignore_changes = [template_annotations]`와 동일한 목적, 대상 속성만 다름).
- `helm_release`(C-2번 패턴)는 이 문제의 영향을 받지 않습니다. `helm` 프로바이더는 `plan` 단계에서 클러스터 접속이 필요 없고 `apply` 시점에만 접속하므로, `hashicorp/helm`을 그대로 유지합니다. 이 워크어라운드가 필요한 대상은 오직 Kubernetes 리소스(구 `hashicorp/kubernetes`, `kubernetes_manifest`)뿐입니다.
- `alekc/kubectl`은 `gavinbunney/kubectl`의 유지보수 포크입니다. 신규 프로바이더 도입 시에는 `gavinbunney`가 아니라 `alekc`를 사용합니다 (2024년 이후 `gavinbunney/kubectl`은 유지보수가 중단됨).

### E-3. Kubernetes CRD(커스텀 리소스)는 매니페스트를 HCL 객체로 그대로 선언한다

> **리소스 타입은 E-2번을 따릅니다.** 이 규칙이 정하는 것은 "CRD를 셸에서 `kubectl apply`하지 않고 매니페스트 구조를 그대로 옮겨 선언한다"이며, 그 그릇은 아래 예시의 `kubernetes_manifest`가 아니라 `kubectl_manifest`의 `yaml_body = yamlencode({ ... })`입니다. 아래 예시는 E-2번으로 옮기기 전의 형태이고, 옮긴 뒤의 같은 리소스는 D-4번에 있습니다. **필드 이름을 그대로 옮긴다는 규칙(camelCase 유지)은 두 형태에서 동일하게 적용됩니다.**

`SecurityGroupPolicy`(vpc-resource-controller), 기타 오퍼레이터가 정의한 CRD처럼 프로바이더에 전용 리소스 타입이 없는 커스텀 리소스는, EC2에서 매니페스트 YAML을 렌더링해 `kubectl apply`하는 대신 매니페스트를 HCL 객체로 그대로 선언합니다.

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
- CRD가 먼저 존재해야 스케줄링에 영향을 주는 데모 리소스(예: 데모 Pod)는 `depends_on = [kubernetes_manifest.xxx]`로 순서를 명시합니다 (D-1번 패턴과 동일한 이유).

### E-4. Fargate profile 생성 후 기존 파드를 재스케줄해야 할 때는 pod 템플릿 애노테이션을 patch해서 rollout을 트리거한다

`aws_eks_fargate_profile`은 생성 시점 **이후에 스케줄되는** 파드에만 매칭됩니다. 그래서 프로파일보다 먼저 존재하던 파드(대표적으로 클러스터 생성 시 기본으로 뜨는 CoreDNS)는 프로파일을 만들어도 그대로 노드에 남아 있고, 강제로 재생성해야 Fargate로 옮겨갑니다.

`_monolithic` 설계는 이것을 SSM Association의 `kubectl rollout restart deployment coredns`로 했습니다. 같은 일을 **pod 템플릿의 애노테이션 하나를 patch**해서 만듭니다 — Deployment의 `spec.template`이 바뀌면 쿠버네티스가 rollout을 시작하므로, 애노테이션 값이 바뀌는 것만으로 재생성이 일어납니다(E-1번).

```hcl
# modules/eks_fargate_profile/main.tf (004_batch_on_eks)
#
# Declared as a raw manifest via the alekc/kubectl provider (kubectl_manifest)
# instead of hashicorp/kubernetes' kubernetes_annotations, so the whole root
# module (EKS cluster + this rollout trigger) can apply in a single
# `terraform apply` (rules.md E-2). Only spec.template.metadata.annotations
# is set; kubectl_manifest's merge-patch semantics leave every other field of
# the existing coredns Deployment (containers, replicas, etc.) untouched.
resource "kubectl_manifest" "reschedule_deployment" {
  count = var.reschedule_deployment_name != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.reschedule_deployment_name
      namespace = var.namespace
    }
    spec = {
      template = {
        metadata = {
          annotations = {
            "terraform.io/restartedAt" = timestamp()
          }
        }
      }
    }
  })

  depends_on = [aws_eks_fargate_profile.fargate_profile]

  lifecycle {
    # timestamp() changes on every apply; without this the resource would
    # trigger a fresh rollout every single apply instead of only the first
    # time.
    ignore_changes = [yaml_body]
  }
}
```

- **부분 매니페스트만 씁니다.** `metadata.name`/`namespace`로 대상을 지목하고 `spec.template.metadata.annotations`만 채웁니다. `kubectl_manifest`는 merge patch로 적용하므로 이미 존재하는 Deployment의 컨테이너·replicas·셀렉터는 건드리지 않습니다. 전체 Deployment를 재선언하면 CoreDNS의 실제 정의를 Terraform이 소유하게 되어, EKS가 애드온으로 관리하는 필드와 싸우게 됩니다.
- **`timestamp()`는 매 `apply`마다 바뀌므로 `ignore_changes = [yaml_body]`로 최초 1회만 트리거되게 막습니다.** 없으면 apply마다 CoreDNS가 재시작합니다. `kubernetes_annotations`를 쓰던 시절의 `ignore_changes = [template_annotations]`와 목적이 같고 대상 속성만 다릅니다.
- **리소스가 아니라 `depends_on`이 순서를 만듭니다.** 프로파일이 먼저 존재해야 재생성된 파드가 Fargate에 매칭되므로 `aws_eks_fargate_profile`을 명시적으로 기다립니다(D-1번).
- 이 기능이 필요 없는 호출자는 `reschedule_deployment_name`을 `null`로 두면 되므로, B-4번 패턴(nullable 변수 + 조건부 리소스)과 동일한 방식입니다.
- `hashicorp/kubernetes`의 `kubernetes_annotations`에는 `template_annotations`와 `force` 인수가 있어 같은 일을 더 짧게 표현할 수 있지만, 이 저장소는 클러스터와 이 리소스를 같은 `apply`에서 만들기 때문에 그 프로바이더를 쓸 수 없습니다(E-2번).

### E-5. Add-on DaemonSet의 환경변수는 `aws_eks_addon`의 `configuration_values`로 설정 (셸의 `kubectl set env` 대체)

`vpc-cni`, `coredns`처럼 EKS 관리형 Add-on으로 배포되는 DaemonSet/Deployment의 환경변수(`ENABLE_POD_ENI`, `POD_SECURITY_GROUP_ENFORCING_MODE` 등)를 EC2 userdata에서 `kubectl set env daemonset aws-node -n kube-system ...`으로 설정하지 않고, `aws_eks_addon` 리소스의 `configuration_values`(JSON 문자열)로 선언합니다. 이는 E-1번 패턴(userdata의 kubectl/helm 명령을 프로바이더 리소스로 대체)의 Add-on 전용 구체 사례입니다.

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

### E-6. AWS 서비스가 EKS에 접근해야 할 때는 principal이 서비스 연결 역할인지 먼저 확인한다 (Access Entry는 서비스 연결 역할을 지원하지 않음)

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

### E-7. `helm_release`의 `set`은 값의 타입을 추론한다 — 문자열이어야 하는 값(annotation/label)에는 `type = "string"`을 entry별로 지정

`helm_release`의 `set`은 `helm --set`과 동일하게 값의 타입을 추론합니다. 따라서 HCL에서 `value = "false"`로 문자열을 넘겨도 차트에는 **YAML boolean**으로 도착합니다. Kubernetes의 `annotations`/`labels`는 값이 반드시 문자열이어야 하므로, 렌더링 결과가 따옴표 없는 `safe-to-evict: false`가 되어 API 디코딩에서 실패합니다.

```
* Deployment in version "v1" cannot be handled as a Deployment: json: cannot unmarshal
  bool into Go struct field ObjectMeta.spec.template.metadata.annotations of type string
```

해당 entry에만 `type = "string"`을 지정합니다(`--set-string`과 같은 의미). `set`의 `type`은 `"auto"`(생략 시 기본) 또는 `"string"`만 받습니다.

```hcl
set = concat([
  {
    name  = "rbac.serviceAccount.create"
    value = "true" # 차트가 boolean을 기대하므로 auto로 둔다
  },
  {
    name  = "podAnnotations.cluster-autoscaler\\.kubernetes\\.io/safe-to-evict"
    value = "false"
    type  = "string" # annotation 값은 문자열이어야 한다
  },
  ],
  var.additional_set_values,
)
```

- **릴리스 전체를 문자열로 강제하지 않고 entry별로 지정합니다.** 같은 릴리스 안에서 `rbac.serviceAccount.create`(boolean), `replicaCount`(number)는 추론된 타입이 맞는 값입니다. 일괄 `--set-string`은 이쪽을 깨뜨립니다.
- `set` 목록을 확장하는 변수(`additional_set_values`)의 object 타입에도 `type = optional(string)`을 넣고 `auto`/`string`만 허용하도록 검증합니다. 그렇지 않으면 호출자는 문자열이 필요한 값을 넘길 방법이 없습니다.
- 판단이 애매하면 apply 전에 `helm template`으로 렌더링해서 확인합니다. 값이 따옴표 없이 나오면 그 값은 문자열이 아닙니다.

```bash
helm template cluster-autoscaler autoscaler/cluster-autoscaler --version 9.51.0 -n kube-system \
  --set 'podAnnotations.cluster-autoscaler\.kubernetes\.io/safe-to-evict=false'
#   annotations:
#     cluster-autoscaler.kubernetes.io/safe-to-evict: false     # 실패
# --set-string 이면
#     cluster-autoscaler.kubernetes.io/safe-to-evict: "false"   # 정상
```

- `extraArgs`처럼 차트가 값을 `toString`으로 감싸 렌더링하는 경우는 auto여도 결과가 같습니다. 다만 차트 템플릿이 `{{ if $value }}`로 분기하면 boolean `false`가 플래그 자체를 누락시켜 **의미가 반대로 뒤집힐** 수 있으니, bool 값을 넘길 때는 렌더 결과를 확인합니다.

#### 실패한 릴리스가 남아 다음 apply가 막히는 경우

`helm install`이 실패하면 릴리스는 클러스터에 `failed` 상태로 남지만 Terraform state에는 기록되지 않습니다. 그 상태로 다시 apply하면 **첫 실패의 원인이 아닌** 다음 에러가 뜹니다.

```
Error: installation failed
  with module.cluster_autoscaler.helm_release.cluster_autoscaler,
  ...
cannot re-use a name that is still in use
```

이 메시지는 증상일 뿐이고 진짜 원인은 릴리스 히스토리에 있습니다. 먼저 원인을 확인한 뒤 정리합니다.

```bash
helm history cluster-autoscaler -n kube-system            # STATUS=failed, DESCRIPTION에 실제 원인
helm uninstall cluster-autoscaler -n kube-system          # 설정을 고친 뒤 이름을 비우고
terraform apply
```

- **`terraform import`로 가져오지 않습니다.** 실패한 릴리스를 state에 넣으면 이후 apply가 upgrade로 진행되면서 `has no deployed releases`로 다시 막힙니다. 정상 배포된 적 없는 릴리스는 지우고 새로 설치하는 것이 맞습니다.
- `atomic = true`(또는 `replace = true`)를 켜면 실패한 릴리스가 자동으로 정리되어 이 상태에 빠지지 않지만, 원인 진단에 필요한 릴리스 히스토리도 함께 사라집니다. 이 저장소는 학습/데모 목적이라 실패 흔적을 남기는 쪽을 택하고 위 수동 복구 절차를 따릅니다.
- `helm uninstall`은 실패한 리비전이 이미 만들어둔 리소스(ServiceAccount, RBAC, Service 등)까지 지웁니다. **정상 배포된 릴리스에는 쓰지 않습니다** — 이 절차는 `helm history`의 STATUS가 `failed`이고 성공한 리비전이 하나도 없을 때에 한정합니다.

## F. 보안 그룹

AWS의 문자셋 제약과 "컨트롤러가 규칙을 추가하는 그룹"이라는 두 가지 함정을 다룹니다.

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

- **한 그룹에 인라인 블록과 독립 규칙 리소스를 섞지 않습니다.** 프로바이더 문서가 경고하는 대로 규칙 충돌, 영구적인 diff, 규칙 덮어쓰기가 발생합니다. 기존 모듈을 독립 리소스로 옮길 때는 인라인 블록을 남겨두지 않고 전부 이전합니다.
- 외부에서 주입받은 소스(B-6번 패턴)는 규칙 블록을 복제하지 않고 `for_each`로 반복합니다(B-7번 패턴과 같은 이유). 단, 소스 보안 그룹 ID는 **다른 모듈의 output이라 plan 시점에 값이 unknown**이므로 `toset(list)`가 아니라 **정적 키를 가진 맵**으로 받습니다(B-8번 패턴).

```hcl
resource "aws_vpc_security_group_ingress_rule" "node_security_group_source_ingress" {
  for_each                     = var.ingress_source_security_groups # map(string), 키는 호출자가 정한 라벨
  security_group_id            = aws_security_group.node_security_group.id
  description                  = "All traffic from the ${each.key} security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = each.value
}
```

- 조건부 규칙은 `count`로 켜고 끕니다. 인라인에서 `dynamic "ingress"`로 하던 것을 독립 리소스에서는 `count = var.allow_inbound_from_anywhere ? 1 : 0`으로 표현합니다.
- **새로 쓰는 그룹은 예외 없이 독립 규칙 리소스입니다.** 컨트롤러가 손댈지 여부를 판단해서 고르지 않습니다 — 그 판단은 나중에 애노테이션 하나로 뒤집히고, 뒤집힌 것을 알아차리는 시점은 컨트롤러가 넣은 규칙이 조용히 사라진 뒤입니다.
- **아무 컨트롤러도 손대지 않는 그룹**(예: `vscode_ec2`가 자기 인스턴스용으로만 만드는 보안 그룹)에 인라인 `dynamic "ingress"`가 **이미 있다면** 그것 때문에 깨지는 것은 없으므로 그 자체를 고치려고 그룹을 건드리지는 않습니다. 다른 이유로 그 그룹을 손볼 때 함께 옮깁니다.
- 컨트롤러나 AWS 서비스가 규칙을 추가하는 그룹에는 `revoke_rules_on_delete = true`를 설정합니다. AWS는 어떤 규칙이 그룹을 참조하는 동안 그 그룹을 삭제하지 않고, 컨트롤러가 넣은 규칙은 Terraform이 추적하지 않으므로 `terraform destroy`가 `DependencyViolation`으로 막힐 수 있습니다. 이 옵션은 그룹을 지우기 전에 **Terraform이 만들지 않은 규칙까지 포함해** 붙어 있는 규칙을 먼저 회수합니다. Terraform 쪽 삭제 동작만 바꾸는 플래그이므로 그룹을 재생성시키지 않습니다(F-1번 패턴의 `description`/`name`과 달리 `Forces new resource`가 아님).

```hcl
resource "aws_security_group" "node_security_group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # The controllers listed above add rules to this group that Terraform does not
  # track. AWS refuses to delete a group while rules referencing it remain, and
  # a controller-added rule can reference the group being deleted (or form a
  # cycle with another group), which blocks the destroy. This revokes the
  # group's attached rules first, including the ones Terraform did not create
  # (rules.md F-2).
  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = {
    Name = var.name
  }
}
```

이 저장소에서는 `node_security_group`(AWS Load Balancer Controller의 backend 규칙 + EKS의 컨트롤 플레인-노드 규칙)과 `load_balancer_security_group`(AWS Load Balancer Controller)에 적용되어 있습니다. 반대로 아무도 규칙을 추가하지 않는 그룹(`vscode_ec2`의 자체 그룹)에는 불필요합니다.

## G. AWS Load Balancer Controller

**G-1번부터 읽습니다.** G-1번이 전체 구성, G-2번이 백엔드 보안그룹 플래그 하나, G-3번이 로드밸런서를 미리 만드는 변형입니다.

### G-1. AWS Load Balancer Controller로 ALB(Ingress)와 NLB(Service)를 만드는 구성 규칙

컨트롤러 설치는 C-2번 패턴대로 IRSA 역할과 `helm_release`를 한 모듈(`modules/aws_load_balancer_controller`)에 둡니다. 차트 버전은 핀하고(`chart_version` 변수), `wait = true`로 Deployment가 Available이 될 때까지 apply를 붙잡습니다 — `_monolithic`의 `kubectl rollout status -n kube-system deploy aws-load-balancer-controller`가 하던 일입니다.

#### 컨트롤러에게 넘기는 스위치를 먼저 확인한다

가장 자주 틀리는 지점입니다. 이 스위치가 없으면 아래의 모든 애노테이션이 **조용히 무시**됩니다.

| | 만들 것 | 넘기는 스위치 | 없으면 |
| --- | --- | --- | --- |
| ALB | `Ingress` | `spec.ingressClassName: alb` | Ingress를 처리할 컨트롤러가 없어 아무 일도 일어나지 않음 |
| NLB | `Service` (`type: LoadBalancer`) | `service.beta.kubernetes.io/aws-load-balancer-type: "external"` (또는 `spec.loadBalancerClass: service.k8s.aws/nlb`) | **in-tree 클라우드 프로바이더가 Classic Load Balancer를 만들고**, 프론트엔드 SG·타깃 타입 애노테이션을 전부 무시 |

NLB 쪽이 특히 위험합니다. Service는 정상 생성되고 `EXTERNAL-IP`에 CLB 주소까지 채워지므로 성공한 것처럼 보이지만, 컨트롤러는 그 Service를 reconcile조차 하지 않습니다. 애노테이션을 여러 개 붙여놓고 `aws-load-balancer-type`만 빠뜨린 구성이 이 상태가 됩니다.

```bash
# CLB가 만들어졌다면 컨트롤러가 관여하지 않은 것입니다
aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type]' --output table
aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output table   # 여기 나오면 CLB
```

#### Service 타입과 `target-type`은 짝이 정해져 있다

```hcl
# ALB - Ingress가 Service를 앞에서 받습니다
service_type   = "ClusterIP"   # target-type = ip 이면 충분합니다
create_ingress = true
ingress_annotations = {
  "alb.ingress.kubernetes.io/scheme"      = "internet-facing"   # 또는 internal
  "alb.ingress.kubernetes.io/target-type" = "ip"
}
```

```hcl
# NLB - Service 자체가 로드밸런서입니다
service_type   = "LoadBalancer"
create_ingress = false
service_annotations = {
  "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
  "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
  "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
}
```

| 로드밸런서 | `target-type` | Service 타입 | 트래픽이 도착하는 포트 |
| --- | --- | --- | --- |
| ALB | `ip` | `ClusterIP` 또는 `NodePort` | 파드의 컨테이너 포트 |
| ALB | `instance` | `NodePort` **필수** | 노드의 NodePort |
| NLB | `ip` | `LoadBalancer` | 파드의 컨테이너 포트 |
| NLB | `instance` | `LoadBalancer` | 노드의 NodePort |

`target-type = ip`는 VPC CNI가 파드 IP를 VPC에서 라우팅 가능하게 만들어 주기 때문에 동작하므로, `eks_vpc_cni_addon`이 노드보다 먼저 있어야 합니다(C-4번 패턴). NLB에서는 클라이언트 소스 주소도 proxy protocol 없이 보존됩니다.

#### 애노테이션 접두사가 다르다

같은 개념이 ALB와 NLB에서 다른 이름을 씁니다. 한쪽 이름을 다른 쪽에 쓰면 오타가 아니라 **그냥 무시**되므로 plan/apply 모두 성공합니다.

| 개념 | ALB (Ingress) | NLB (Service) |
| --- | --- | --- |
| 스킴 | `alb.ingress.kubernetes.io/scheme` | `service.beta.kubernetes.io/aws-load-balancer-scheme` |
| 타깃 타입 | `alb.ingress.kubernetes.io/target-type` | `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type` |
| 프론트엔드 SG | `alb.ingress.kubernetes.io/security-groups` | `service.beta.kubernetes.io/aws-load-balancer-security-groups` |
| 백엔드 규칙 관리 | `alb.ingress.kubernetes.io/manage-backend-security-group-rules` | `service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules` |

NLB의 타깃 타입만 `nlb-`가 붙는 점에 주의합니다(컨트롤러 소스의 `SvcLBSuffixTargetType`이 이 값이며, 축약형이 아니라 정식 이름입니다).

#### 서브넷 자동 발견 태그는 `network` 모듈이 심는다

컨트롤러는 서브넷 태그로 배치할 곳을 찾습니다. `network` 모듈의 기본 태그가 이것이며, C-3번 패턴의 `public_subnet_tags`/`private_subnet_tags`로 주입합니다.

| 태그 | 대상 | 쓰이는 곳 |
| --- | --- | --- |
| `kubernetes.io/role/elb = 1` | public 서브넷 | `scheme: internet-facing` |
| `kubernetes.io/role/internal-elb = 1` | private 서브넷 | `scheme: internal` |

`scheme`과 태그가 어긋나면 컨트롤러가 서브넷을 못 찾아 `couldn't auto-discover subnets`로 실패합니다.

#### 프론트엔드 보안그룹과 백엔드 규칙

프론트엔드 SG를 애노테이션으로 직접 넘기면 규칙이 plan에 보이므로 이 저장소는 그 방식을 기본으로 합니다(`modules/load_balancer_security_group`). 이때 노드 측 규칙을 누가 쓰는지가 `enable_backend_security_group`과 얽히며, 조합 규칙은 **G-2번 패턴**에 정리되어 있습니다. 요약하면:

- `manage-backend-security-group-rules: "true"`를 붙이면 컨트롤러가 노드 규칙을 쓰고, `--enable-backend-security-group=true`가 **필수**입니다.
- 애노테이션을 붙이지 않으면 `false`로 둘 수 있고, 노드 측 규칙은 Terraform이 직접 선언합니다(`target-type: ip` 한정).
- 컨트롤러가 규칙을 추가하는 보안그룹에는 인라인 `ingress`/`egress`를 쓰지 않고 독립 규칙 리소스를 쓰며 `revoke_rules_on_delete = true`를 켭니다(**F-2번 패턴**).

#### 로드밸런서는 Terraform 리소스가 아니다

주소를 Terraform output으로 만들 수 없습니다. 컨트롤러가 만들기 때문입니다. H-2번 패턴대로 값 대신 **확인 명령**을 output에 넣습니다.

```hcl
output "load_balancer_hostname_command" {
  value = "kubectl -n ${var.namespace} get ${local.load_balancer_object} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
```

ALB(Ingress)와 NLB(Service)는 주소가 담기는 오브젝트가 다르지만 필드는 같은 `status.loadBalancer`이므로, 읽을 오브젝트만 한 곳에서 결정하면 명령 하나로 양쪽을 덮습니다(B-5번 패턴).

```hcl
load_balancer_object = var.create_ingress ? "ingress ${var.ingress_name}" : "service ${var.service_name}"
```

**예외는 G-3번 패턴입니다.** 로드밸런서를 Terraform이 미리 만들어 컨트롤러가 채택하게 하면 그 로드밸런서는 다시 Terraform 리소스가 되므로, ARN과 DNS 이름을 output으로 낼 수 있습니다. 그때도 확인 명령은 **함께** 남깁니다 — 컨트롤러가 실제로 그 로드밸런서를 채택했는지(아니면 두 번째를 만들었는지)는 클러스터를 봐야만 알 수 있기 때문입니다.

#### 순서와 destroy

워크로드 모듈(`kubectl_manifest`로 Ingress/Service를 만드는 모듈)은 **컨트롤러와 노드 그룹 뒤에** 옵니다. 컨트롤러가 reconcile하고 있지 않으면 Service/Ingress는 주소를 얻지 못하고, `terraform destroy` 때는 반대로 컨트롤러가 아직 살아 있는 동안 매니페스트가 지워져야 로드밸런서가 정리됩니다(**D-4번 패턴**).

```hcl
depends_on = [module.network, module.eks_node_group, module.aws_load_balancer_controller]
```

#### 기존 로드밸런서를 채택시키는 sync 패턴

로드밸런서를 Terraform으로 미리 만들고 컨트롤러가 그것을 재사용하게 하는 구성은 **G-3번 패턴**에 정리되어 있습니다. 컨트롤러가 자기 소유물에 붙이는 태그 3개(`elbv2.k8s.aws/cluster`, `<prefix>.k8s.aws/resource`, `<prefix>.k8s.aws/stack`)를 모두 맞춰야 하고, 하나라도 다르면 에러가 아니라 컨트롤러가 두 번째 로드밸런서를 따로 만듭니다.

#### 진단 순서

주소가 채워지지 않을 때 볼 곳은 정해져 있습니다.

```bash
kubectl -n <ns> describe ingress <name>     # 또는 describe service - 컨트롤러 이벤트가 여기 붙습니다
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail 100
```

- 이벤트/로그가 아예 없으면 컨트롤러가 그 오브젝트를 보고 있지 않은 것입니다 → 위의 "넘기는 스위치"를 확인합니다.
- `couldn't auto-discover subnets` → 서브넷 태그와 `scheme` 불일치.
- `backendSG feature is required ...` → G-2번 패턴.

### G-2. AWS Load Balancer Controller의 `--enable-backend-security-group`은 변수로 노출하고, `manage-backend-security-group-rules` 애노테이션을 쓰는지로 값을 결정한다

**결정 기준은 하나입니다: 워크로드가 `manage-backend-security-group-rules` 애노테이션을 설정하는가.**

| 워크로드가 그 애노테이션을 | 이 플래그 | 노드 측 규칙을 쓰는 주체 |
| --- | --- | --- |
| 설정한다 | **`true`여야 합니다** (컨트롤러가 거부) | 컨트롤러 |
| 설정하지 않는다 | `false`로 둡니다 | **Terraform** (`target-type: ip` 한정) |

커스텀 프론트엔드 보안그룹의 유무는 이 판단에 들어가지 않습니다. 흔한 오해라서 아래 "커스텀 프론트엔드 보안그룹을 쓰는 프로젝트에서는 끌 수 없다" 절에서 소스로 확인합니다.

`008_eks_aws_load_balancer_controller`의 7개 변형은 **전부 두 번째 행**입니다: 애노테이션을 설정하지 않고, `enable_backend_security_group = false`이며, 노드 측 규칙을 루트의 `load_balancer_to_pods`로 직접 선언합니다.

컨트롤러는 기본적으로 **공유 백엔드 보안그룹** 하나를 만들어(`k8s-traffic-<cluster>-<hash>`) 모든 로드밸런서에 붙이고, 노드/ENI 보안그룹에 추가하는 규칙의 소스로 그 그룹을 지정합니다. `--enable-backend-security-group`(기본 `true`)이 이 동작을 켜고 끕니다. 끄면 v2.3.0 이전 동작으로 돌아가, 노드 측 규칙이 **각 로드밸런서의 프론트엔드 보안그룹**을 직접 참조합니다.

모듈에 bool 변수로 노출합니다. 루트의 기본값은 위 표의 두 번째 행에 해당하는 `false`이며, 이는 **컨트롤러의 기본값(`true`)과 반대**입니다 — 끄는 쪽이 이 저장소의 기본 선택이라서 그렇고, 컨트롤러의 기본값을 따라간 결과가 아닙니다.

```hcl
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "... 공유 백엔드 보안그룹 사용 여부 ..."
}
```

#### `set` 항목은 반드시 bool로 렌더링한다 (E-7번 패턴의 구체 사례)

차트 템플릿이 이 플래그를 **타입 검사**로 감싸고 있습니다.

```gotemplate
{{- if kindIs "bool" .Values.enableBackendSecurityGroup }}
- --enable-backend-security-group={{ .Values.enableBackendSecurityGroup }}
{{- end }}
```

`kindIs "bool"`은 truthiness가 아니라 타입을 봅니다. 따라서 문자열 `"false"`를 넘기면 검사를 통과하지 못해 **플래그 자체가 Deployment에서 사라지고**, 컨트롤러는 자신의 기본값 `true`로 동작합니다 — 의도한 것과 정반대이면서, 렌더링도 apply도 조용히 성공합니다. `values.yaml`의 기본값이 빈 값(null)인 이유도 이 가드 때문입니다.

`helm --set`은 `"false"`에서 boolean을 추론하므로, 이 항목에는 **`type = "string"`을 붙이지 않습니다**(E-7번 패턴).

```hcl
{
  name  = "enableBackendSecurityGroup"
  value = tostring(var.enable_backend_security_group)
  # type을 지정하지 않습니다 - auto 추론이 bool을 만들어야 합니다
},
```

의심되면 렌더 결과를 확인합니다.

```bash
helm template aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set enableBackendSecurityGroup=false | grep enable-backend-security-group
#   - --enable-backend-security-group=false      # 정상
# --set-string enableBackendSecurityGroup=false 였다면 이 줄이 아예 없습니다
```

#### 커스텀 프론트엔드 보안그룹을 쓰는 프로젝트에서는 끌 수 없다

Ingress/Service에 프론트엔드 보안그룹을 직접 지정하면(`alb.ingress.kubernetes.io/security-groups`, `service.beta.kubernetes.io/aws-load-balancer-security-groups`) 컨트롤러는 기본적으로 노드 측 규칙을 건드리지 않습니다. 그래서 F-2번 패턴처럼 `manage-backend-security-group-rules: "true"`를 함께 붙여 규칙 관리를 다시 켜는데, **이 조합에서 `--enable-backend-security-group=false`는 허용되지 않습니다.**

컨트롤러가 로드밸런서 모델을 만드는 단계에서 에러로 중단합니다.

```go
// pkg/ingress/model_build_load_balancer.go
if manageBackendSGRules {
    if !t.enableBackendSG {
        return nil, errors.New("backendSG feature is required to manage worker node SG rules when frontendSG manually specified")
    }
```

- **증상이 특히 나쁩니다.** `terraform apply`는 성공합니다(Helm 릴리스와 매니페스트는 정상 생성). 로드밸런서만 영원히 만들어지지 않아서 Ingress의 `ADDRESS`, Service의 `EXTERNAL-IP`가 계속 비어 있고, 이유는 컨트롤러 파드 로그에만 남습니다.

```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller | grep backendSG
kubectl -n <ns> describe ingress <name>   # 컨트롤러 이벤트도 함께 확인
```

- 따라서 끄기 전에 확인할 것은 커스텀 프론트엔드 SG의 유무가 아니라 **`manage-backend-security-group-rules`를 켰는지**입니다. 소스를 보면 프론트엔드 SG는 `if manageBackendSGRules` **밖에서** 이미 `lbSGTokens`에 추가되고, 에러는 그 블록 안에만 있습니다. 즉 커스텀 프론트엔드 SG를 쓰면서도 이 애노테이션을 붙이지 않으면 `false`로 둘 수 있고, ELB에는 지정한 그룹만 붙습니다.

```go
} else {   // 애노테이션으로 SG를 지정한 경로
    manageBackendSGRules, err := t.buildManageSecurityGroupRulesFlag(ctx)
    frontendSGIDs, err := t.sgResolver.ResolveViaNameOrID(ctx, sgNameOrIDsViaAnnotation)
    for _, sgID := range frontendSGIDs {
        lbSGTokens = append(lbSGTokens, core.LiteralStringToken(sgID))   // ← 여기서 이미 붙는다
    }
    if manageBackendSGRules {                     // ← 에러는 이 안에만 있다
        if !t.enableBackendSG { return nil, errors.New("backendSG feature is required ...") }
```

`manageBackendSGRules`의 기본값은 CLI 플래그 `--enable-manage-backend-security-group-rules`(기본 `false`)에서 오고, 개별 애노테이션이 그보다 우선합니다.

| 프로젝트 구성 | `enable_backend_security_group` | 노드 측 규칙의 주인 |
| --- | --- | --- |
| 프론트엔드 SG 직접 지정 + `manage-backend-security-group-rules: "true"` | `true` (필수) | 컨트롤러 |
| 프론트엔드 SG 직접 지정 + 애노테이션 없음 | `false` 가능 | **Terraform (직접 선언해야 함)** |
| 프론트엔드 SG를 컨트롤러가 자동 생성 | `false` 가능 | 컨트롤러 (자동 생성 그룹을 소스로) |

#### 두 번째 행을 택하면 노드 측 규칙을 반드시 직접 선언한다

`backendSGIDToken`이 비면 컨트롤러는 TargetGroupBinding에 `networking` 스펙을 아예 넣지 않습니다. 즉 노드/파드 쪽으로 가는 규칙이 **하나도** 만들어지지 않습니다.

```go
func (t *defaultModelBuildTask) buildTargetGroupBindingNetworking(...) *...TargetGroupBindingNetworking {
	if t.backendSGIDToken == nil {
		return nil          // 규칙 0개
	}
```

`target-type: ip`면 트래픽이 파드 IP의 **컨테이너 포트**로 도착하고 파드는 EKS 클러스터 보안그룹을 쓰므로, 그 그룹에 프론트엔드 SG를 소스로 하는 인바운드를 직접 선언합니다. 헬스체크도 같은 포트(`traffic-port`)라 규칙 하나로 덮입니다.

```hcl
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  count = var.service_type == "LoadBalancer" ? 1 : 0

  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "NLB to pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = module.workload.container_port   # 포트를 아는 모듈에서 받는다 (B-5번 패턴)
  to_port                      = module.workload.container_port
  referenced_security_group_id = module.frontend_security_group.security_group_id
}
```

- **`target-type: instance`에서는 이 방식을 쓸 수 없습니다.** NodePort는 쿠버네티스가 30000-32767에서 임의로 배정하므로 Terraform이 포트를 알 수 없고, 표현 가능한 규칙은 그 범위 전체를 여는 것뿐입니다. 이 조합을 쓰는 변형에서는 `target_type` 변수를 `ip`로 제한하는 `validation`을 걸어 apply 전에 막습니다.
- 이 경로를 택할 때 **`aws-load-balancer-type = "external"`(또는 `spec.loadBalancerClass`)이 붙어 있는지 먼저 확인합니다.** 둘 중 아무것도 없으면 in-tree 클라우드 프로바이더가 Service를 처리해 Classic Load Balancer를 만들고, 프론트엔드 SG 애노테이션과 타깃 타입을 통째로 무시합니다. 컨트롤러가 Service를 아예 reconcile하지 않으므로 위의 모든 이야기가 적용되지 않습니다.
- 기존에 붙어 있는 프론트엔드 SG의 `description`을 손보고 싶어도 참으십시오. 보안그룹은 `description` 변경 시 **교체**되고(F-1번 패턴), 로드밸런서가 그 그룹을 참조하는 동안 AWS는 삭제를 거부하므로 `DependencyViolation`으로 막힙니다. 문구 수정은 API 값이 아니라 주석에서 합니다.

#### 이 플래그를 변수로 노출하면 반드시 `validation`을 함께 넣는다

`enable_backend_security_group`을 변수로 만들면, 첫 번째 행(애노테이션을 쓰는 구성)에 해당하는 프로젝트에서 **`false`를 넣을 수 있는 길이 생깁니다.** 그런데 그 조합은 `terraform plan`을 깨끗하게 통과합니다 — 잘못된 조합인지는 컨트롤러만 알기 때문입니다. `apply`도 성공하고(Helm 릴리스와 매니페스트는 정상 생성), 로드밸런서만 영원히 만들어지지 않습니다. B-1번 패턴대로 제약을 `description`이 아니라 `validation`에 둡니다.

```hcl
variable "enable_backend_security_group" {
  type    = bool
  default = true

  validation {
    # 이 변형의 워크로드가 manage-backend-security-group-rules 애노테이션을 쓰므로
    # false는 컨트롤러가 거부합니다. plan은 이를 알 수 없어 통과하고, 실패는
    # 컨트롤러 로그에만 남습니다.
    condition     = var.enable_backend_security_group
    error_message = "enable_backend_security_group must be true in this variant, because its workload sets the manage-backend-security-group-rules annotation alongside its own frontend security group. To run with it false, drop that annotation and declare the node-side security group rule in Terraform instead."
  }
}
```

같은 이유로 `manage-backend-security-group-rules`의 값을 변수로 노출한 경우에도 `validation`이 필요합니다. 이쪽을 `false`로 만들면 컨트롤러도 Terraform도 노드 측 규칙을 열지 않아, **로드밸런서는 정상 생성되고 모든 타깃이 unhealthy로 남습니다.** 에러 메시지가 없으므로 plan/apply만 보고는 알 수 없습니다.

| 변형의 구성 | `enable_backend_security_group` | `manage-backend...` 애노테이션 |
| --- | --- | --- |
| 프론트엔드 SG 직접 지정 + 컨트롤러가 노드 규칙 관리 | `validation`으로 `true` 고정 | `validation`으로 `true` 고정 |
| 프론트엔드 SG 직접 지정 + Terraform이 노드 규칙 선언 | `false` (기본값으로 둠) | 설정하지 않음 |
| 프론트엔드 SG 자동 생성 | 둘 다 유효 → 검증 불필요 | 설정하지 않음 |

세 번째 행에는 `validation`을 넣지 않습니다. 애노테이션이 없으면 `true`/`false` 모두 성립하므로(컨트롤러가 자동 생성 그룹을 소스로 삼음) 제약할 것이 없습니다.

- 끄는 쪽의 이득은 계정에 보안그룹이 하나 줄고, 노드 측 규칙이 실제로 로드밸런서가 달고 있는 그룹을 가리켜 데이터 경로가 눈에 보인다는 점입니다. 대신 **로드밸런서마다 노드 보안그룹에 규칙이 하나씩 쌓입니다.** 로드밸런서가 많아지면 그룹당 규칙 한도에 걸리므로, 기본값을 `false`로 삼지 않는 이유가 이것입니다(업스트림 문서도 같은 경고를 합니다).
- 전체 리소스에 일괄 적용하는 `--enable-manage-backend-security-group-rules` 플래그도 있지만, 이것 역시 `--enable-backend-security-group`이 `true`여야 동작합니다. 개별 애노테이션이 이 플래그보다 우선합니다.

### G-3. AWS Load Balancer Controller가 만들 ALB/NLB는 Terraform이 미리 만들고 컨트롤러가 채택(adopt)하게 한다

G-1번 패턴의 기본형에서는 로드밸런서가 Terraform 리소스가 아닙니다. 컨트롤러가 Ingress/Service를 reconcile하면서 만들기 때문에 ARN도 DNS 이름도 `terraform plan`에 없고, `apply`가 끝난 뒤 클러스터를 조회해야 비로소 알 수 있습니다.

이 패턴은 그 순서를 뒤집습니다. **`aws_lb`를 Terraform이 먼저 만들고, 컨트롤러가 자기 소유물에 붙이는 태그를 그 로드밸런서에 미리 심어둡니다.** 그러면 컨트롤러가 Ingress/Service를 reconcile할 때 Resource Groups Tagging API로 자기 스택의 리소스를 찾다가 이 로드밸런서를 발견하고, 새로 만드는 대신 **그것을 채택해서** 리스너와 타깃그룹을 붙입니다. 리스너·타깃그룹·타깃 등록은 계속 컨트롤러의 일이고, 로드밸런서 껍데기만 Terraform이 소유합니다.

`008_eks_aws_load_balancer_controller`의 `sync_alb`(Ingress→ALB)와 `sync_nlb`(Service→NLB)가 이 패턴이며, 두 변형 모두 `modules/synced_load_balancer` 하나로 양쪽 모양을 덮습니다.

#### 이 패턴을 쓰는 이유

- **주소를 Terraform이 안다.** ARN·DNS 이름·`zone_id`가 state에 있으므로 output으로 낼 수 있고, Route 53 alias 레코드나 CloudFront origin처럼 로드밸런서를 참조하는 다른 Terraform 리소스를 같은 `apply` 안에서 만들 수 있습니다. 컨트롤러가 만든 로드밸런서로는 이것이 불가능합니다.
- **구성이 plan에 보인다.** 서브넷, 보안그룹, scheme이 애노테이션 문자열이 아니라 리소스 속성으로 리뷰됩니다.
- **NLB의 보안그룹은 생성 시점에만 붙일 수 있다.** AWS 문서가 명시하는 제약입니다 — 보안그룹 없이 만들어진 NLB에는 나중에 붙일 수 없고(`SetSecurityGroups`가 거부), 그래서 `sync_nlb`처럼 프론트엔드 보안그룹을 Terraform이 통제해야 하는 구성에서는 로드밸런서를 미리 만드는 것이 가장 확실한 방법입니다.

#### 태그 3개가 채택의 유일한 조건이다

```hcl
# modules/synced_load_balancer/main.tf
locals {
  # ingress.k8s.aws/* for a load balancer fronting an Ingress,
  # service.k8s.aws/* for one fronting a Service of type LoadBalancer.
  controller_tags = {
    "elbv2.k8s.aws/cluster"                       = var.cluster_name
    "${var.resource_tag_prefix}.k8s.aws/resource" = "LoadBalancer"
    "${var.resource_tag_prefix}.k8s.aws/stack"    = var.stack
  }
}
resource "aws_lb" "synced_load_balancer" {
  name                       = var.name
  name_prefix                = var.name == null ? "k8s-" : null
  load_balancer_type         = var.load_balancer_type
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = length(var.security_group_ids) > 0 ? var.security_group_ids : null
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.controller_tags, var.additional_tags)

  lifecycle {
    # The controller mutates the load balancer once it adopts it - attributes,
    # listeners and target group wiring. Ignoring these keeps every subsequent
    # terraform plan from proposing to undo the controller's work.
    ignore_changes = [security_groups, subnets, tags, tags_all]
  }
}
```

| 태그 | 값 | Ingress(ALB) | Service(NLB) |
| --- | --- | --- | --- |
| `elbv2.k8s.aws/cluster` | 클러스터 이름 | 동일 | 동일 |
| `<prefix>.k8s.aws/resource` | `LoadBalancer` (리터럴) | `ingress.k8s.aws/resource` | `service.k8s.aws/resource` |
| `<prefix>.k8s.aws/stack` | `<namespace>/<이름>` | `ingress.k8s.aws/stack` | `service.k8s.aws/stack` |

- **접두사를 틀리는 것이 가장 흔한 실수입니다.** Service에서 오는 NLB에 `ingress.k8s.aws/*`를 붙이면 채택되지 않습니다(업스트림 [#3576](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/3576)이 정확히 이 사례). G-1번 패턴의 애노테이션 접두사 표와 같은 종류의 함정이며, 마찬가지로 **오류가 아니라 무시**됩니다.
- `resource` 태그의 값은 `LoadBalancer` 고정입니다. 컨트롤러 모델에서 로드밸런서의 리소스 ID가 그 문자열이고, 타깃그룹은 `<svc>/<port>` 같은 다른 값을 받습니다. 타깃그룹은 Terraform이 만들지 않으므로 이 값은 항상 `LoadBalancer`입니다.

#### `stack` 값은 워크로드 모듈의 output에서 받는다

`stack`은 `<namespace>/<Ingress 또는 Service 이름>`입니다. 이 문자열을 루트에 리터럴로 다시 적으면(`_monolithic`이 `"default/ingress-2048"`로 하드코딩했던 방식) 워크로드의 이름이나 네임스페이스를 바꾸는 순간 조용히 어긋나므로, 워크로드 모듈이 자기 이름에서 파생시켜 output으로 내보내고 로드밸런서 모듈은 그 output만 받습니다(B-5번 패턴).

```hcl
# modules/game_2048/outputs.tf - Ingress가 있으면 Ingress 이름, 없으면 Service 이름
output "ingress_stack_tag" {
  value       = var.create_ingress ? "${var.namespace}/${var.ingress_name}" : "${var.namespace}/${var.service_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack (Ingress) or service.k8s.aws/stack (Service) tag. A pre-created load balancer must carry exactly this value to be adopted rather than duplicated, so it is derived here instead of being restated by the caller (rules.md B-5)"
}
```

```hcl
# 루트 main.tf - 워크로드 모듈을 로드밸런서 모듈보다 먼저 선언해서 output을 넘깁니다
module "synced_alb" {
  source = "./modules/synced_load_balancer"

  cluster_name       = module.eks_cluster.cluster_name
  name               = var.synced_load_balancer_name
  load_balancer_type = "application"
  internal           = false
  # An internet-facing scheme needs public subnets; this has to match what the
  # Ingress's scheme annotation implies.
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  # ingress.k8s.aws/* because this load balancer fronts an Ingress rather than a
  # Service of type LoadBalancer.
  resource_tag_prefix = "ingress"
  # Taken from the workload module rather than restating "<namespace>/<ingress>",
  # so the tag cannot drift from the Ingress the controller is reconciling
  # (rules.md B-5).
  stack = module.game_2048.ingress_stack_tag

  depends_on = [module.network]
}
```

- **`alb.ingress.kubernetes.io/group.name`을 쓰면 `stack` 값이 달라집니다.** 명시적 IngressGroup의 스택 ID는 `<namespace>/<name>`이 아니라 **그룹 이름 하나**입니다. 기존 Ingress에 이 애노테이션을 추가하면 컨트롤러가 로드밸런서를 새로 만드는 이유가 이것입니다(업스트림 [#2271](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2271)). 워크로드가 `group.name`을 쓰는 구성이라면 `stack`도 그 그룹 이름을 내보내야 하고, 그 파생 역시 워크로드 모듈이 책임집니다.

#### 태그 외에 반드시 일치해야 하는 것

태그가 맞아 채택 대상이 되더라도, 컨트롤러가 계산한 로드밸런서 명세와 실제 로드밸런서가 **재생성 없이는 맞출 수 없는 항목**에서 어긋나면 채택이 성립하지 않습니다.

| 항목 | Terraform | 워크로드 쪽 |
| --- | --- | --- |
| 타입 | `load_balancer_type = "application" \| "network"` | Ingress(ALB) / `type: LoadBalancer` Service(NLB) |
| scheme | `internal = false \| true` | `scheme` 애노테이션(`internet-facing` / `internal`) |
| 서브넷 | `subnet_ids` | `scheme`이 요구하는 쪽(public / private) + G-1번 패턴의 서브넷 태그 |

- `internal`과 `scheme`이 어긋나는 것은 에러가 아니라 **두 번째 로드밸런서**입니다. 이 패턴의 실패는 거의 전부 이 모양으로 나타납니다.
- 서브넷은 `ignore_changes`에 들어 있어 컨트롤러가 조정할 수 있지만, ELB가 요구하는 **최소 2개 AZ**는 Terraform이 먼저 만족시켜야 하므로 모듈에서 검증합니다.

```hcl
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer's nodes are placed in: public subnets for an internet-facing scheme, private ones for internal"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least two valid availability zones."
  }
}
```

#### 이름은 비워둔다 (`name = null` + `name_prefix`)

채택은 오직 태그로 이루어지므로 로드밸런서 이름은 아무 역할도 하지 않습니다. 반대로 이름을 고정하면 **태그가 어긋났을 때의 실패 모양이 나빠집니다.** 워크로드에도 `aws-load-balancer-name` 애노테이션이 있고 그 이름이 같다면, 채택에 실패한 컨트롤러가 같은 이름으로 새 로드밸런서를 만들려다 AWS에게 거부당합니다.

```
A load balancer with the same name 'XXXXXXX' exists, but with different settings.
```

이 메시지는 "이름이 겹쳤다"가 아니라 **"태그가 맞지 않아 채택되지 않았다"**로 읽어야 합니다(업스트림 [#3576](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/3576)). 이름을 비워두면 같은 실패가 조용한 "로드밸런서 2개"로 나타나므로 진단 방향이 헷갈릴 수 있지만, 계정에 같은 프로젝트를 두 번 배포할 수 있게 되는 이득이 더 큽니다. 그래서 기본값은 `null`이고 `name_prefix = "k8s-"`로 유일한 이름을 생성합니다.

```hcl
variable "name" {
  type        = string
  default     = null
  description = "Optional load balancer name. When null, a unique name is generated, which avoids collisions when this project is deployed twice in one account"

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.name))
    error_message = "name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
```

#### 리스너·타깃그룹은 Terraform이 선언하지 않는다

`aws_lb`만 만들고 `aws_lb_listener`/`aws_lb_target_group`/`aws_lb_listener_rule`은 **선언하지 않습니다.** 채택 후 그것들은 컨트롤러가 만들고, 파드가 뜨고 죽을 때마다 타깃 등록을 갱신합니다. Terraform이 같은 것을 선언하면 두 소유자가 같은 리스너를 두고 싸우게 됩니다.

같은 이유로 채택 후 컨트롤러가 바꾸는 속성은 `lifecycle.ignore_changes`로 막습니다. 이것이 없으면 채택 직후부터 모든 `terraform plan`이 컨트롤러의 작업을 되돌리자고 제안합니다.

```hcl
lifecycle {
  ignore_changes = [security_groups, subnets, tags, tags_all]
}
```

- `tags`가 목록에 있는 이유: 컨트롤러는 자기가 관리하는 로드밸런서에 태그를 추가합니다. `tags`를 무시하지 않으면 매 apply가 그 태그를 지우려 하고, 하필 그 태그 중에는 **채택의 조건인 태그들도 있습니다.**
- `security_groups`가 목록에 있는 이유: G-2번 패턴의 공유 백엔드 보안그룹이 켜져 있으면 컨트롤러가 `k8s-traffic-<cluster>-<hash>` 그룹을 로드밸런서에 **추가**합니다. Terraform이 그것을 되돌리면 데이터 경로가 끊어집니다.

#### 보안그룹은 최소 하나를 생성 시점에 붙인다

NLB는 보안그룹 없이 만들어지면 나중에 붙일 수 없으므로, 컨트롤러가 백엔드 보안그룹을 추가하려 해도 실패합니다. 프론트엔드 보안그룹을 Terraform이 만들어(G-1번 패턴의 `load_balancer_security_group`) 그것을 `security_group_ids`로 넘기고, 같은 그룹 ID를 워크로드의 `security-groups` 애노테이션에도 넘겨서 컨트롤러가 그 그룹을 자기가 유지해야 할 그룹으로 인식하게 합니다.

```hcl
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the pre-created ALB the controller adopts from the 2048 Ingress"
  # ...
  depends_on = [module.network]
}
module "game_2048" {
  # ...
  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = var.alb_target_type
    "alb.ingress.kubernetes.io/security-groups" = module.alb_security_group.security_group_id
  }
}
module "synced_alb" {
  # ...
  security_group_ids = [module.alb_security_group.security_group_id]
}
```

노드/파드 측 규칙을 누가 쓰는지는 이 패턴과 무관하게 G-2번 패턴이 정하며, `sync_alb`/`sync_nlb`는 그 표의 두 번째 행(애노테이션 없이 Terraform이 직접 선언)을 따릅니다. `target-type: ip`이므로 규칙 하나로 덮입니다.

```hcl
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "ALB to pods on the container port"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = module.alb_security_group.security_group_id
}
```

#### output은 값과 확인 명령을 모두 낸다

이 패턴에서는 G-1번 패턴의 "로드밸런서는 Terraform 리소스가 아니다"가 뒤집히므로 주소를 output으로 낼 수 있습니다. 다만 **채택이 실제로 일어났는지는 output만 봐서는 알 수 없습니다** — 컨트롤러가 두 번째 로드밸런서를 만들었어도 이 output은 여전히 Terraform이 만든 쪽의 주소를 정확히 보여줍니다. 그래서 H-2번 패턴의 맵에 미리 만든 주소와 **클러스터에서 읽는 주소**를 나란히 넣어, 둘을 비교하는 것이 데모의 검증 단계가 되게 합니다.

```hcl
locals {
  outputs = {
    synced_load_balancer_url = {
      order       = 6
      title       = "Pre-created ALB URL"
      description = "This is the point of the sync variant: Terraform creates the load balancer, so its address is known from state at apply time rather than only after the controller has reconciled an Ingress"
      value       = module.synced_alb.url
    }
    synced_load_balancer_stack_tag = {
      order       = 9
      title       = "Adoption stack tag"
      description = "The <namespace>/<name> value the load balancer carries in its ingress.k8s.aws/stack tag. The controller adopts the load balancer only when this matches the Ingress it is reconciling - a mismatch makes it build a second one instead"
      value       = module.synced_alb.stack
    }
    ingress_endpoint_command = {
      order       = 11
      title       = "2. Read the adopted ALB DNS name"
      description = "Compare this against the pre-created URL above. They should be the same load balancer"
      value       = module.game_2048.load_balancer_hostname_command
    }
  }
}
```

모듈이 입력받은 `stack`을 output으로 되돌려주는 것도 같은 목적입니다(B-5번 패턴). 태그에 실제로 들어간 값이 output에 보이므로, 워크로드와 어긋났는지를 `terraform output`에서 바로 대조할 수 있습니다.

```hcl
# modules/synced_load_balancer/outputs.tf
output "stack" {
  value       = var.stack
  description = "The <namespace>/<name> stack tag this load balancer was tagged with, re-exposed so a mismatch with the workload is visible in outputs (rules.md B-5)"
}
```

#### 채택 후 수명주기는 컨트롤러와 공유된다

채택된 로드밸런서는 컨트롤러의 스택에 속하므로, **Ingress/Service가 사라지면 컨트롤러가 그 로드밸런서를 지웁니다.** 자기가 만들지 않았어도 마찬가지입니다(업스트림 [#2493](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2493): "Controller deletes an ALB it didn't create when there are no ingresses left"). 결과적으로:

- `terraform destroy`에서 워크로드 매니페스트가 먼저 지워지면(D-4번 패턴의 순서) 컨트롤러가 로드밸런서를 먼저 삭제하고, Terraform의 `aws_lb` 삭제는 이미 없는 리소스를 지우는 것이 됩니다. 이 순서 자체는 문제가 아니지만, 미리 만든 로드밸런서가 Terraform만의 소유물이 아니라는 뜻입니다.
- 워크로드만 지우고(`kubectl delete ingress`) 인프라를 남겨두면 다음 `terraform plan`이 로드밸런서를 다시 만들자고 제안합니다. 이는 drift가 아니라 이 패턴의 정상적인 결과입니다.
- 따라서 이 로드밸런서를 참조하는 Route 53 레코드처럼 **로드밸런서보다 오래 살아야 하는 리소스**를 붙일 때는, 워크로드를 지우면 그 참조가 끊어진다는 점을 전제로 설계합니다. `enable_deletion_protection`은 이 상황을 막아주지 못합니다(컨트롤러의 삭제는 막지만, 그러면 컨트롤러가 에러 루프에 빠집니다). 데모 구성에서는 `false`로 둡니다.

#### 선언 순서

```
network → eks_cluster → addons/node group → aws_load_balancer_controller
        → load_balancer_security_group → game_2048(워크로드) → synced_load_balancer
```

- **워크로드 모듈이 로드밸런서 모듈보다 먼저 선언됩니다.** 로드밸런서의 `stack` 태그가 워크로드 모듈의 output에서 오기 때문이며, 값 참조로 순서도 함께 잡힙니다.
- 워크로드 모듈 자체는 컨트롤러와 노드그룹 뒤에 옵니다(G-1번 패턴). 로드밸런서를 미리 만들었다고 이 순서가 완화되지는 않습니다 — 리스너와 타깃 등록은 여전히 컨트롤러가 reconcile해야 생깁니다.
- `synced_load_balancer` 모듈에는 `depends_on = [module.network]`를 붙입니다(D-3번 패턴). 컨트롤러나 노드그룹을 기다릴 필요는 없습니다. `aws_lb`는 클러스터 API 서버에 접속하지 않는 순수 AWS 리소스이므로 D-4번 패턴의 대상이 아닙니다.

#### 진단

주소가 채워지지 않거나 예상과 다르면, 로드밸런서가 **몇 개 있는지**부터 셉니다. 이 패턴의 실패는 대부분 "에러 없이 2개"입니다.

```bash
# 태그로 컨트롤러 소유 로드밸런서를 전부 나열합니다. 2개 나오면 채택 실패입니다
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=elbv2.k8s.aws/cluster,Values=<cluster> \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --query 'ResourceTagMappingList[].ResourceARN' --output table

# 컨트롤러가 실제로 붙인 주소와 Terraform이 만든 주소를 대조합니다
kubectl -n <ns> get ingress <name> -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
terraform output synced_load_balancer_url
```

2개라면 순서대로 확인합니다.

1. `<prefix>.k8s.aws/*`의 접두사가 워크로드의 종류(Ingress면 `ingress`, Service면 `service`)와 맞는지.
2. `stack` 태그가 `kubectl -n <ns> get ingress <name>`의 네임스페이스/이름과 정확히 같은지. `group.name` 애노테이션이 있으면 값이 그룹 이름이어야 합니다.
3. `internal`과 `scheme` 애노테이션, `load_balancer_type`과 워크로드의 종류가 맞는지.
4. `elbv2.k8s.aws/cluster`가 그 컨트롤러의 `--cluster-name`과 같은지.

`A load balancer with the same name ... exists, but with different settings`가 나오면 위 1~4 중 하나가 틀린 상태에서 이름만 겹친 것입니다. 이름 문제로 접근하지 않습니다.

```bash
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail 100
kubectl -n <ns> describe ingress <name>   # 또는 describe service
```

## H. EC2 작업대와 산출물 전달

루트에 `vscode_ec2`가 있는 프로젝트에만 적용되는 규칙입니다.

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
- **E-1번 패턴과의 경계**: 이 도구들은 사람이 조사·디버깅·데모하는 용도입니다. 설치되어 있다는 이유로 userdata나 `aws_ssm_association`에서 `kubectl apply`/`helm install`로 **리소스를 만들지 않습니다**. 리소스 생성은 계속 `helm_release`/`kubectl_manifest`가 담당합니다.
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

### H-2. 루트 `outputs.tf`의 모든 값은 SSM Association으로 `vscode_ec2`의 `README.md`에도 기록한다 (마커 파일로 순서 강제)

**적용 조건: 루트에 `module "vscode_ec2"`가 있는 프로젝트.** 없으면 이 규칙은 적용되지 않습니다 — 렌더링할 대상이 없으므로 `local.outputs` 맵도 필요 없고, `outputs.tf`에 값 표현식을 직접 쓰는 평범한 output이 맞습니다. 그때는 **왜 맵을 쓰지 않았는지를 `outputs.tf` 상단 주석에 남깁니다**(`014_basic_ec2`, `015_basic_vpc_and_subnets`가 그 형태). 이유를 적지 않으면 다음 사람이 이 규칙 위반으로 읽습니다.

실제 작업은 code-server 브라우저 세션 안에서 일어나고, 그 안에는 `terraform output`이 없습니다. 그래서 **루트 `outputs.tf`가 노출하는 output 전부가 인스턴스의 `/home/ec2-user/README.md`에도 있어야 합니다.** code-server가 `/home/ec2-user`를 열기 때문에 파일 탐색기 첫 화면에 보입니다.

**중요한 것은 "일부"가 아니라 "전부"라는 점입니다.** output이 12개면 README 섹션도 12개입니다. 어떤 값이 중요해 보이는지로 골라 담지 않습니다. 인스턴스에 접속한 사람은 `terraform output`을 볼 수 없으므로, README에서 빠진 output은 그 사람에게는 존재하지 않는 정보입니다.

이걸 사람의 기억에 맡기지 않으려면 구조를 뒤집어야 합니다. **모든 output의 값을 루트 `locals`의 맵 한 곳에서 정의하고, `outputs.tf`의 `output` 블록은 그 맵을 그대로 투영하기만 합니다.** 이렇게 하면 참조할 맵 항목 없이는 output을 선언할 수 없으므로, "output은 있는데 README에는 없는" 상태가 애초에 만들어지지 않습니다.

작성은 `aws_ssm_association`(`AWS-RunShellScript`)으로 하고, 순서는 마커 파일로 강제합니다(D-5번 패턴).

```hcl
# 루트 main.tf
locals {
  # 이 프로젝트가 노출하는 모든 output의 정의. outputs.tf의 output 블록과 README가
  # 똑같이 여기만 참조하므로, 값 표현식이 저장소에 단 한 번만 존재합니다
  # (B-5번 패턴). 맵의 키가 곧 output 이름입니다.
  #
  # output을 추가할 때는 반드시 여기에 항목을 먼저 추가합니다. 여기 없는 output은
  # outputs.tf에서 참조할 것이 없어 선언 자체가 불가능하므로, README에서 누락되는
  # 경우가 구조적으로 생기지 않습니다.
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
  # 있습니다. order 필드로 다시 키를 만들고 values()를 取하면(values는 맵의 값을
  # 키 순서로 돌려줍니다) 의도한 순서가 되고, 순서는 여전히 설정만으로 결정됩니다.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # 맵을 순회해 본문을 만들기 때문에, 항목을 추가하면 README에 자동으로 반영됩니다.
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
# 루트 outputs.tf - 값은 전부 local.outputs의 투영입니다. 여기서 새 표현식을
# 만들지 않습니다.
#
# description만은 맵을 참조할 수 없습니다. Terraform은 output의 description에
# 표현식을 허용하지 않아서 "Error: Variables not allowed - Variables may not be
# used here"로 거부합니다. 그래서 설명 문구는 맵과 output 블록 양쪽에 리터럴로
# 존재하는 유일한 항목입니다 (값은 여전히 한 곳에만 있습니다).
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

- **`outputs.tf`에 값 표현식을 직접 쓰는 `output`을 만들지 않습니다.** `value = module.eks_cluster.cluster_name`처럼 맵을 거치지 않고 선언한 output은 README에서 빠지고, 그 누락은 apply가 성공하기 때문에 아무도 알려주지 않습니다. 모든 `value`가 `local.outputs.<키>.value`인지가 이 패턴이 지켜지고 있는지 판별하는 기준입니다.
- 리뷰할 때는 개수를 셉니다. `outputs.tf`의 `output` 블록 수와 `local.outputs`의 항목 수가 다르면 둘 중 하나가 누락된 것입니다. 값이 아직 unknown이어도 키는 plan 이전에 알 수 있으므로 `echo '[for k, v in local.outputs : k]' | terraform console`로 목록을 뽑아 대조할 수 있습니다.
- 각 항목에 `order`를 붙이고 `values(...)`로 정렬합니다. README는 사람이 위에서 아래로 읽는 문서이고 데모 명령에는 실행 순서가 있는데, 맵을 그대로 순회하면 키의 사전순이 되어 그 순서가 깨집니다.
- **`aws_ssm_association`은 루트에 둡니다.** 여러 모듈의 output을 조합하는 책임은 루트의 것이고(C-1번 패턴), `vscode_ec2` 모듈은 자기 홈에 무엇이 적히는지 몰라도 됩니다.
- 마커 경로는 모듈 input을 그대로 output으로 되돌려받은 `module.vscode_ec2.marker_file_path`를 참조합니다(B-5번 패턴). 루트에서 `var.marker_file_path`를 직접 다시 쓰지 않습니다.
- 대기 조건은 `depends_on`이나 `wait_for_success_timeout_seconds`가 아니라 `until [ -f .../userdata ]` 루프입니다(D-5번 패턴). 그리고 이 association도 자신의 마커(`vscode_readme`)를 남겨서, 뒤에 오는 association이 이어서 기다릴 수 있게 합니다.
- **userdata의 마커는 스크립트 맨 마지막에 생성되어야 합니다.** `${var.additional_user_data}`보다 먼저 `touch`하면 kubectl/eksctl/helm 설치 도중에 이 association이 출발해서, README는 써지지만 도구는 아직 없는 상태가 됩니다(B-4번 패턴의 스니펫 참고).
- SSM 명령은 root로 실행되므로 `chown ec2-user:ec2-user`가 필요합니다. 없으면 code-server에서 편집이 안 됩니다.
- 셸 heredoc 구분자는 `<< 'TFREADME'`처럼 인용합니다. 값은 Terraform이 이미 채워 넣었으므로 셸이 `$`나 백틱을 건드릴 이유가 없습니다. 구분자는 본문에 나올 수 없는 문자열로 정합니다. README에 kubectl 명령이나 마크다운이 들어가는 만큼 `EOF`/`MD` 같은 짧은 단어보다 안전합니다.
- `parameters`가 바뀌면 association이 갱신되며 다시 실행되고, `cat >`는 덮어쓰기이므로 output이 바뀌면 다음 apply에서 README도 따라 갱신됩니다. 맵 하나만 고치면 output과 README가 같이 따라옵니다.
- **apply 시점에 Terraform이 모르는 값**(예: AWS Load Balancer Controller가 만드는 로드밸런서의 DNS 이름)은 그 항목을 빼는 게 아니라, 값 자리에 **확인 명령**을 넣습니다: `kubectl -n <ns> get service <name>`. output과 README가 같은 맵을 보므로 양쪽에 동일하게 그 명령이 나갑니다.
- **`sensitive = true`가 필요한 값은 예외입니다.** 비밀번호·토큰 같은 값을 README로 디스크에 남기면 인증 없이 열리는 code-server를 통해 그대로 노출됩니다. 이런 항목은 맵의 `value`에 값 대신 조회 방법(`aws secretsmanager get-secret-value --secret-id ...`)을 넣고, 실제 값이 필요한 output은 별도로 `sensitive = true`로 선언합니다. 이때만 output과 README가 서로 다른 것을 담습니다.
- 이 패턴은 인스턴스에 `AmazonSSMManagedInstanceCore`가 붙어 있어야 동작합니다(`vscode_ec2` 모듈의 `iam_policy_arns` 기본값에 포함).
