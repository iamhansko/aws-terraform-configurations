---
inclusion: always
---

# Common Terraform Guidelines

이 문서는 저장소의 Terraform 규칙을 해석하는 공통 원칙과 canonical 인덱스입니다. 각 규칙은 실제 실패에서 출발했으므로 결정뿐 아니라 실패 모양, 진단 절차, 예외의 경계까지 기록합니다.

> **시작:** [A. 저장소 구조 · 파일 · CloudFormation 변환](rules-repository-structure-and-conversion.md)
> 기존 `.tf` 주석의 `rules.md A-1` 같은 표기는 파일명이 아니라 아래 규칙 ID를 가리키는 논리 인용입니다.

## 빠른 탐색

| 파트 | 문서 | 다루는 범위 | 규칙 |
| --- | --- | --- | --- |
| A | [Repository Structure and CloudFormation Conversion](rules-repository-structure-and-conversion.md) | 디렉터리, 파일 배치, 변환, 줄바꿈, 숨은 IAM 권한 | A-1–A-5 |
| B | [Variable and Interface Design](rules-variables-and-interfaces.md) | 입력 검증, 조정 가능한 값, 모듈 인터페이스, `for_each` 키 | B-1–B-8 |
| C | [Module Boundaries and Composition](rules-module-boundaries-and-composition.md) | 소유권 경계, IRSA, network output, EKS Add-on | C-1–C-4 |
| D | [Resource Ordering and Destruction](rules-resource-ordering-and-destruction.md) | 생성 순서, 런타임 수명, 준비·삭제 대기, 순환 방지 | D-1–D-9 |
| E | [Kubernetes Resource Management](rules-kubernetes-resource-management.md) | provider/SSM 분기, 매니페스트, Add-on, Helm | E-1–E-10 |
| F | [Security Groups](rules-security-groups.md) | 문자셋, 규칙 소유권, My IP 기본 인바운드 | F-1–F-3 |
| G | [AWS Load Balancer Controller](rules-aws-load-balancer-controller.md) | ALB/NLB, backend SG, 채택, Service mutator | G-1–G-4 |
| H | [EC2 Workbench and Output Delivery](rules-ec2-workbench-and-outputs.md) | EKS 작업대와 README-safe output 전달 | H-1–H-2 |
| I | [Multi-Account and Multi-Region](rules-multi-account-and-region.md) | 계정/state 경계, handoff, provider alias, 수명주기 DAG | I-1–I-4 |

## 공통 해석 원칙

### 규칙 ID와 논리 인용

규칙 ID는 `<파트>-<순번>`입니다. 새 규칙은 해당 파트의 끝에 다음 순번으로 추가합니다. 중간에 삽입해 뒤 규칙의 ID를 밀지 않습니다.

```bash
grep -rn 'rules\.md D-3' --include='*.tf' .
grep -roh 'rules\.md [A-I]-[0-9]*' --include='*.tf' . | sort | uniq -c | sort -rn
```

- 인용은 **코드만 보고 이유를 되돌리기 쉬울 때** 붙입니다. 규칙이 적용될 때마다 표식처럼 붙이지 않습니다.
- 인용 횟수는 적용 범위나 중요도를 나타내지 않습니다. 준수 여부는 각 파트의 감사 절차로 판정합니다.
- 규칙을 다른 파트로 옮기면 모든 `.tf` 인용을 스크립트로 함께 바꾸고 이전 ID가 남지 않았는지 검색합니다.
- 규칙을 폐기해도 ID를 재사용하거나 빈칸으로 만들지 않습니다. 대체 규칙과 마이그레이션 방향을 본문에 남깁니다.

### 일반 규칙과 예외의 우선순위

서로 어긋나 보이면 먼저 적용 조건을 비교합니다. 더 구체적인 조건을 다루는 규칙이 일반 규칙보다 우선하며, 예외는 일반 원칙을 폐기하지 않습니다.

| 함께 읽을 규칙 | 경계 |
| --- | --- |
| B-1 ↔ B-2·F-1 | B-1은 타입보다 좁은 제약의 일반 원칙이고, B-2와 F-1은 enum·AWS 문자셋의 구체 구현입니다. |
| B-7 ↔ B-8 | plan-known 정책 ARN은 `toset(list)`로 반복할 수 있지만, unknown 값이 인스턴스 키가 되면 plan-known 안정 키의 map을 사용합니다. |
| C-2 ↔ E-1·E-9 | IRSA 역할과 Helm 릴리스의 co-location이 기본입니다. runner는 API에 도달하지 못하지만 지정한 VPC 관리 인스턴스는 도달하는 SSM 분기에서만 AWS 전용 모듈과 설치 단계를 나눕니다. 어느 실행 위치도 도달하지 못하면 먼저 네트워크 경로를 확보합니다. |
| D-4 ↔ D-7·D-8 | D-4는 API 경로·용량·컨트롤러의 수명을 정합니다. D-7은 삭제 finalizer, D-8은 생성·갱신 status 준비를 별도로 기다립니다. |
| E-1 ↔ E-2·E-9 | E-1은 reachable runner의 provider 소유 원칙이고 E-2는 단일 apply의 provider 선택입니다. E-9는 runner 비도달·VPC 관리 인스턴스 도달의 SSM 분기, 어느 실행 위치도 닿지 않는 Blocked 분기, 내부 객체가 없는 AWS-only 분기를 구분합니다. |
| F-2 ↔ F-3 | 신규 그룹은 독립 규칙이 원칙입니다. populated inline state의 소스만 바꾸는 F-3 작업은 안전한 별도 마이그레이션 전까지 기존 소유권을 유지합니다. |
| G-1 ↔ G-2·G-3·G-4 | G-1의 전체 조합 위에 SG 소유권, pre-created LB 채택, Service mutator 정책을 각각 추가합니다. |
| H-2 ↔ I-4 | 작업대 README는 README-safe 표현의 전달 경로입니다. 여러 state의 수명주기 절차는 저장소 README와 모든 참여 루트 output이 권위 있는 기록입니다. |

구현과 문서가 다르면 어느 한쪽을 자동으로 정답으로 간주하지 않습니다. 코드는 현재 동작의 증거이고 문서는 의도한 정책의 증거입니다. 원본 동작, provider/API 제약, 실제 plan/apply 결과로 올바른 결론을 판정한 뒤 양쪽을 함께 맞춥니다. 문서 작업 범위에서 발견했지만 코드 변경이 별도 리허설을 요구하는 항목은 현재 준수로 포장하지 않고 감사·교정 대상으로 명시합니다.

### 저장소 기본값과 기능별 예외

| 항목 | 저장소 기본 | 예외를 읽는 방법 |
| --- | --- | --- |
| Terraform | 모듈화된 활성 구성의 최소 기준은 `required_version = ">= 1.9"` | 기능 때문에 더 높은 최소 버전을 선언한 루트는 그 floor를 유지합니다. `_monolithic/`에는 생성 당시의 `>= 1.5`와 `>= 1.9` 선언이 함께 있으며 소급 수정하지 않습니다. |
| AWS provider | 기본 major 제약은 `~> 6.0` | 특정 리소스나 수정 사항이 더 높은 6.x minor를 요구하면 해당 루트가 더 좁은 floor를 선언할 수 있습니다. `data.aws_region`의 속성은 `region`입니다. |
| Kubernetes 객체 | runner가 API에 도달하면 `alekc/kubectl`의 `kubectl_manifest`; Helm 차트는 `hashicorp/helm`의 `helm_release` | runner는 도달하지 못하지만 지정한 VPC 관리 인스턴스는 도달하고 내부 객체가 있으면 E-9의 SSM 분기입니다. 어느 실행 위치도 도달하지 못하면 먼저 경로를 확보하고, 내부 객체가 없으면 provider와 SSM 단계를 모두 생략합니다. |
| 적용 단위 | 독립 Terraform 루트 하나는 필요한 리소스를 한 번의 `terraform apply`로 구성 | 여러 계정·state는 I-4의 DAG에 따라 루트별로 독립 실행합니다. 이를 한 state나 한 apply로 합치지 않습니다. |
| 줄바꿈 | 모든 활성 `.tf` 파일은 LF | `_monolithic/`은 조회 전용이므로 포맷·줄바꿈 교정 대상에서 제외합니다. |

### `_monolithic/`은 조회 전용

`_monolithic/` 디렉터리는 CloudFormation 기계 변환 원본이며 모듈화된 구성이 재현해야 할 기준입니다. **조회·분석만 하고 수정하거나 삭제하지 않습니다.** 원본과 다른 설계를 택하면 모듈화된 구성만 바꾸고 차이의 이유를 인접 주석에 남깁니다.

## 선별 감사 안내

각 파트 본문이 실제 명령과 판정 기준의 source of truth입니다. 아래 표는 자주 함께 확인하는 감사를 찾기 위한 인덱스이며 전체 목록이 아닙니다.

| 확인할 것 | 판정 방법 | 규칙 |
| --- | --- | --- |
| 에디터의 `Unexpected attribute`가 실제 오류인가 | 해당 루트의 `terraform validate -json` | A-2 |
| active `.tf`에 CRLF가 있는가 | `_monolithic/`과 `.terraform/`을 제외한 바이트 검사 | A-4 |
| Terraform 포맷이 맞는가 | 활성 구성에서 `terraform fmt -check`; 조회 전용 원본은 별도 취급 | A-4 |
| 설명에만 남은 입력 제약이 있는가 | 후보를 검색한 뒤 실제 `validation`과 유효 대안을 수동 대조 | B-1 |
| unknown 값이 `for_each` 주소를 결정하는가 | symbol을 입력·local·data까지 추적하고 실제 `plan` 실행 | B-8, D-6 |
| 모든 루트 module이 network 뒤에 있는가 | `depends_on` module 간선의 전이 도달 집합 계산 | D-3 |
| Kubernetes 객체 삭제 동안 런타임이 살아 있는가 | API 경로·용량·controller 간선과 finalizer `wait`, destroy 리허설 대조 | D-4, D-7 |
| 뒤 객체가 status 준비를 요구하는가 | 필요한 `wait_for` field/condition과 객체 간 요청 순서 확인 | D-8 |
| Kubernetes 설치 분기가 맞는가 | 내부 객체 유무, runner와 지정한 VPC 관리 인스턴스 각각의 **실제 DNS/TCP 도달성**으로 provider·SSM·Blocked·AWS-only 분류 | E-1, E-9 |
| Helm 값이 의도한 타입인가 | 핀한 버전과 실제 값으로 `helm template` 렌더링 | E-7, G-2, G-4 |
| EKS Add-on 설정 타입이 맞는가 | `describe-addon-configuration` 스키마와 적용 후 `describe-addon` 대조 | E-5 |
| controller가 바꾼 필드를 Terraform이 되돌리는가 | 값을 옮긴 뒤 두 번째 `terraform plan`이 깨끗한지 확인 | E-8 |
| Helm 차트 버전·용량이 안전한가 | 버전 핀/상한, `helm template`, 최대 단일 파드와 requests 합, 적용 후 Pending 조회 | E-10 |
| `allow_inbound_from_anywhere=false`가 규칙을 없애는가 | 기본값·주소 집합·선택 CIDR 감사; populated state에서는 in-place plan과 다음 plan 확인 | F-3 |
| Service 포트와 SG 규칙이 일치하는가 | 실제 차트 값으로 렌더된 Service 포트와 frontend/pod-side SG 전수 대조 | G-1 |
| pre-created LB가 실제로 채택됐는가 | cluster+prefix+stack 태그로 ARN 하나를 찾고 Terraform ARN·AWS 태그·Kubernetes hostname 대조 | G-3 |
| Service mutator 정책이 명시됐는가 | 모든 controller module call, 렌더된 LoadBalancer Service 표식, live webhook 대조 | G-4 |
| workbench output과 README 표현이 일치하는가 | `local.outputs`, sensitive allowlist, output 블록의 이름 집합과 투영식 대조 | H-2 |
| account root가 다른 계정을 assume하는가 | account root의 전체 AWS provider 블록에서 `profile`·cross-account `assume_role` 확인 | I-1 |
| 계정 handoff와 guard가 실제로 막는가 | producer output/consumer variable, 미래 principal 합의 이름, blocking pre/postcondition 도달성 대조 | I-2 |
| 여러 state의 수명주기가 완전한가 | 저장소 README와 모든 참여 루트 output에서 apply DAG와 reverse destroy DAG 대조 | I-4 |
| 숨은 IAM 권한이 광범위 정책으로 대체됐는가 | 외부 bootstrap script까지 추적하고 controller/agent 역할의 실제 정책 비교 | A-5 |

## Canonical 규칙 레지스트리

아래 제목은 각 파트 문서의 `### <ID>. <제목>`과 정확히 같아야 합니다. 제목을 바꾸면 이 레지스트리도 함께 바꾸고 자동 검증으로 parity를 확인합니다.

### [A. 저장소 구조 · 파일 · CloudFormation 변환](rules-repository-structure-and-conversion.md)

- A-1. 디렉토리 구조
- A-2. 루트 구성과 모듈 모두 4파일 분리
- A-3. `aws_iam_instance_profile`의 `role`은 역할 이름 문자열 하나만 받는다 (CloudFormation 변환 시 흔한 버그)
- A-4. `.tf` 파일은 LF로 저장한다 (CRLF는 heredoc 종료자를 깨뜨려 셸 스크립트 전체를 실행 불가로 만든다)
- A-5. 원본이 부트스트랩 스크립트로 만들던 IAM 권한을 관리형 광범위 정책으로 대체하지 않는다

### [B. 변수와 인터페이스 설계](rules-variables-and-interfaces.md)

- B-1. `type`만으로 표현되지 않는 변수 제약은 `validation`으로 강제
- B-2. AMI 타입 등 AWS가 정한 고정된 열거값은 `contains()`로 검증
- B-3. 사용자가 조정할 루트 리터럴은 변수로 승격
- B-4. 선택적 기능은 nullable 변수 + 템플릿 디렉티브로 구현
- B-5. 모듈 입력을 그대로 모듈 출력으로 되돌려주는 패턴 (단일 진실 공급원)
- B-6. 외부 리소스는 조회하지 말고 식별자를 입력으로 주입
- B-7. 여러 개의 IAM 관리형 정책은 `for_each`로 attach
- B-8. unknown 값을 `for_each`로 반복할 때는 plan-known 안정 키의 `map`을 사용

### [C. 모듈 경계와 조립](rules-module-boundaries-and-composition.md)

- C-1. 서로 무관한 모듈이 소유한 principal의 EKS 접근 권한은 루트에서 조립
- C-2. IRSA 컨트롤러는 IAM 역할과 Helm 릴리스를 같은 모듈에 둔다
- C-3. `network` 모듈은 토폴로지에 맞는 zone별 output과 전체 ID 배열을 함께 노출한다
- C-4. 모든 EKS Add-on은 각자 독립된 모듈을 가진다 (`vpc-cni`/`coredns`/`kube-proxy` 포함)

### [D. 생성 순서와 destroy](rules-resource-ordering-and-destruction.md)

- D-1. IAM 역할-정책 결합 리소스는 `depends_on`으로 생성 순서를 명시
- D-2. 모듈 간 생성 순서는 `module` 블록의 `depends_on` 메타 인수로 표현
- D-3. `network` 모듈이 있는 루트의 다른 모든 `module` 블록은 `network` 전체가 끝난 뒤에 시작한다
- D-4. Kubernetes 객체를 관리하는 동안 API 경로·실행 용량·컨트롤러를 살아 있게 둔다
- D-5. SSM Association의 순서는 `depends_on`이 아니라 마커 파일과 `until` 루프로 강제한다
- D-6. `module` 블록의 `depends_on`은 그 모듈 안의 `data` 소스까지 apply로 미룬다 — plan 시점에 읽혀야 하는 `data`는 모듈 밖에 둔다
- D-7. 컨트롤러가 finalizer를 붙이는 오브젝트는 `kubectl_manifest`에 `wait = true`를 설정한다 — `depends_on`은 DELETE를 **보내는** 시점만 정하고 끝나는 시점은 정하지 않는다
- D-8. 뒤 리소스가 **status**를 보고 동작하는 오브젝트는 `kubectl_manifest`에 `wait_for`를 설정한다 — `depends_on`은 CREATE를 **보내는** 시점만 정하고 준비된 시점은 정하지 않는다
- D-9. `check` 블록은 루트에 둔다 — 모듈 안의 `check`는 그 모듈의 close를 검사 단계 뒤로 밀어서, 그 모듈을 `depends_on`으로 가리키는 다른 모듈과 순환을 만든다

### [E. Kubernetes 리소스를 만드는 방법](rules-kubernetes-resource-management.md)

- E-1. runner가 API 서버에 도달하면 Kubernetes 객체는 `kubectl_manifest`/`helm_release`로 선언한다
- E-2. 단일 `terraform apply`가 필요하면 Kubernetes 리소스는 `hashicorp/kubernetes` 대신 `alekc/kubectl`의 `kubectl_manifest`로 선언
- E-3. Kubernetes 커스텀 리소스(CR)는 매니페스트를 HCL 객체로 그대로 선언한다
- E-4. Fargate profile보다 먼저 존재한 Deployment를 마이그레이션할 때만 annotation patch로 rollout한다
- E-5. Add-on DaemonSet의 환경변수는 `aws_eks_addon`의 `configuration_values`로 설정 (셸의 `kubectl set env` 대체)
- E-6. AWS 서비스가 EKS에 접근해야 할 때는 principal이 서비스 연결 역할인지 먼저 확인한다 (Access Entry는 서비스 연결 역할을 지원하지 않음)
- E-7. `helm_release`의 `set`은 값의 타입을 추론한다 — 문자열이어야 하는 값(annotation/label)에는 `type = "string"`을 entry별로 지정
- E-8. 컨트롤러가 값을 바꾸는 필드는 `kubectl_manifest`의 `ignore_fields`로 그 경로만 제외한다 (`lifecycle.ignore_changes = [yaml_body]`는 매니페스트 전체를 동결한다)
- E-9. runner가 EKS API에 도달하지 못하면 도달 가능한 VPC 관리 인스턴스에서 Kubernetes 객체를 적용한다
- E-10. `helm_release`의 `version`은 핀하고, 차트가 번들 의존성을 떼어낸 메이저는 `validation`으로 막는다 — 차트 호환성은 plan이 보장하지 않으며 대개 apply 렌더링에서 드러난다

### [F. 보안 그룹](rules-security-groups.md)

- F-1. 보안 그룹의 `description`/`name`은 AWS 문자셋 제약을 `validation`으로 검증한다 (아포스트로피 금지, 변경 시 그룹 재생성)
- F-2. 보안 그룹 규칙은 인라인 `ingress`/`egress` 블록이 아니라 독립 규칙 리소스로 선언한다 (컨트롤러가 규칙을 추가하는 그룹에는 필수)
- F-3. `allow_inbound_from_anywhere`는 규칙 존재가 아니라 소스만 선택한다 (`false` = 실행자의 My IP `/32`, `true` = `0.0.0.0/0`)

### [G. AWS Load Balancer Controller](rules-aws-load-balancer-controller.md)

- G-1. AWS Load Balancer Controller로 ALB(Ingress)와 NLB(Service)를 만드는 구성 규칙
- G-2. 프론트엔드 SG 소유권과 effective backend-rule 관리 설정으로 `--enable-backend-security-group`을 결정한다
- G-3. AWS Load Balancer Controller가 만들 ALB/NLB는 Terraform이 미리 만들고 컨트롤러가 채택(adopt)하게 한다
- G-4. Service mutator는 Ready endpoint가 없을 때 Service CREATE를 막는다 — 명시적 controller selection을 기본 정책으로 한다

### [H. EC2 작업대와 산출물 전달](rules-ec2-workbench-and-outputs.md)

- H-1. EKS 클러스터와 `vscode_ec2`가 같은 루트 모듈에 함께 선언되면 code-server, kubectl, eksctl, helm, docker를 **모두** 설치한다
- H-2. 루트의 README-safe output 표현은 SSM Association으로 `vscode_ec2`의 `README.md`에도 기록한다 (실제 민감값은 allowlist 예외)

### [I. 여러 계정과 여러 리전](rules-multi-account-and-region.md)

- I-1. 계정마다 독립된 루트 모듈을 만들고, 한 루트가 두 계정을 건드리지 않는다
- I-2. 계정 간 값은 output→variable로 넘기고, 미래 principal의 진짜 순환만 이름 합의로 끊는다
- I-3. 같은 계정 안의 여러 리전은 `provider` alias로 나누고, 어느 리전의 것인지를 리소스 이름에 남긴다
- I-4. 계정 간 apply·destroy 순서는 저장소 README와 모든 참여 루트 output에 적는다

## 예전 `#N` 번호와의 대응

2026-09 이전에는 파트 구분 없이 `#1`–`#39`를 사용했고 `#8`–`#11`은 첫 기록부터 결번이었습니다. 오래된 커밋·노트·리뷰 코멘트의 `rules.md #N`은 아래 표로 변환합니다.

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
|  |  | #27 | D-3 | #39 | G-3 |

## Steering 문서 구성

공통 인덱스와 A–I 파트 문서는 각각 독립된 Kiro steering 파일이며 모두 `inclusion: always`를 유지합니다. 링크는 탐색용이고 규칙 ID가 안정적인 참조 경계입니다. 파일명을 바꾸더라도 `.tf`의 기존 `rules.md X-N` 논리 인용은 일괄 변경하지 않습니다.
