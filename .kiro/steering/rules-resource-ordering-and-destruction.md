---
inclusion: always
---

# Resource Ordering and Destruction Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-module-boundaries-and-composition.md`](rules-module-boundaries-and-composition.md) · **Next:** [`rules-kubernetes-resource-management.md`](rules-kubernetes-resource-management.md)
> 논리 인용 `rules.md D-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| D-1 | 같은 모듈의 리소스가 IAM 정책 attachment 완료를 요구 | 해당 리소스에 명시적 `depends_on` | D-2는 모듈 경계 |
| D-2 | 모듈 사이에 값 참조로 드러나지 않는 런타임 순서가 있음 | 호출자 `module` 블록에 `depends_on` | D-3·D-4의 기본 수단 |
| D-3 | 루트에 `module "network"`가 있음 | `network`를 제외한 모든 `module` 블록을 직접 또는 전이적으로 network 뒤에 둠 | D-2의 저장소 전역 특수 규칙 |
| D-4 | Kubernetes 객체의 생성·삭제 동안 API 경로, 실행 용량, 컨트롤러가 살아 있어야 함 | 기본은 루트 `module` 블록에서 실제 런타임 의존성에 `depends_on` | D-7의 finalizer 대기와 결합 |
| D-5 | SSM 원격 단계의 실제 완료 순서가 필요 | 마커 파일과 `until` 루프로 완료를 증명 | B-4·H-2 |
| D-6 | `depends_on`이 있는 모듈의 `data` 결과가 plan 시점 주소 결정에 필요 | `data`를 루트에서 읽어 값으로 주입 | D-2·D-4 순서는 유지 |
| D-7 | 컨트롤러가 객체에 finalizer를 붙임 | `kubectl_manifest.wait = true`와 컨트롤러 수명 순서를 함께 설정 | D-4 |
| D-8 | 뒤 객체가 앞 객체의 status 준비 완료를 요구 | `kubectl_manifest.wait_for`로 필요한 field/condition을 기다림 | 객체 간 준비 간선; D-4와 역할이 다름 |
| D-9 | 중첩 `data`를 가진 `check`의 모듈을 다른 모듈이 기다림 | `check`를 루트로 이동 | D-2와 결합 시 순환 방지 |

## D. 생성 순서와 destroy

Terraform의 암묵적 그래프는 **값 참조**만 따라갑니다. `a = module.x.y`는 그 값을 만든 **특정 리소스**까지만 순서를 잡고, 그 모듈의 나머지 리소스나 "그 리소스가 실제로 동작하기 시작하는 시점"과는 아무 관계가 없습니다. 값 참조가 없는 런타임 선행조건과 destroy 동안 유지해야 할 수명 조건은 직접 표현해야 하며, 이 파트의 규칙은 모두 그 원칙의 적용 사례입니다.

무엇을 쓸지는 경계가 어디인지로 갈립니다.

| 상황 | 쓰는 것 | 규칙 |
| --- | --- | --- |
| 같은 모듈 안의 리소스가 IAM 정책 attachment 등을 기다려야 함 | 리소스의 `depends_on` | D-1 |
| 다른 모듈이 준비된 뒤여야 하는데 값 참조가 없음 | 호출자 `module` 블록의 `depends_on` | D-2 |
| `network` 모듈이 있는 루트의 다른 모든 `module` 블록 | 직접 또는 전이적인 `module` 블록의 `depends_on` (**필수**) | D-3 |
| Kubernetes 객체를 다루는 동안 API 경로·실행 용량·컨트롤러가 살아 있어야 함 | 기본적으로 그 객체를 소유한 루트 `module` 블록의 `depends_on` | D-4 |
| 원격 셸 명령의 완료를 기다려야 함 | `depends_on`이 아니라 **마커 파일 + `until` 루프** | D-5 |
| `depends_on`이 붙은 모듈이 plan 시점에 읽혀야 하는 `data`를 가짐 | 그 `data`를 **루트로 옮기고** 결과를 변수로 넘김 | D-6 |
| 컨트롤러가 finalizer를 붙이는 객체 | 수명 `depends_on`에 더해 `kubectl_manifest.wait = true` | D-7 |
| 뒤 객체가 앞 객체의 status를 보고 동작함 | 객체 간 순서에 더해 `kubectl_manifest.wait_for` | D-8 |
| plan 시점 상태를 단정하는 `check`가 있고 그 모듈을 다른 모듈이 기다림 | `check` 블록을 **루트에** 둠 | D-9 |

D-6번은 읽기 시점을 순서와 분리하고, D-7·D-8번은 요청 순서와 완료 조건을 분리하며, D-9번은 검사 단계를 모듈 close와 분리합니다. 같은 마커 파일 메커니즘을 B-4번(userdata가 마커를 만드는 위치)과 H-2번(README를 쓰는 association이 그 마커를 기다림)이 함께 씁니다.

#### 대기 기능 분류

| 기능 | 단계 | 기다리는 것 | 대신하지 못하는 것 |
| --- | --- | --- | --- |
| `kubectl_manifest.wait` | 삭제 | 객체가 실제로 사라짐; finalizer 완료 | 생성 준비 상태, 컨트롤러 수명 순서 |
| `kubectl_manifest.wait_for` | 생성·갱신 | 지정한 `status` field 또는 condition | 삭제 finalizer, 모듈 런타임 수명 |
| `kubectl_manifest.wait_for_rollout` | 생성·갱신 | 프로바이더가 지원하는 workload rollout | 임의 CR의 status, 삭제 finalizer |
| `helm_release.wait` | install·upgrade | 차트가 만든 지원 리소스의 준비 완료 | 별도 `kubectl_manifest`의 status, destroy 수명 간선 |

네 기능 모두 **준비·삭제 완료를 기다리는 방식**일 뿐, API 경로·노드 용량·컨트롤러를 언제까지 살려둘지는 정하지 않습니다. 그 수명은 D-4번의 `depends_on`으로 별도 표현합니다. D-7번의 DELETE와 D-8번의 CREATE/UPDATE 모두 요청을 보낸 시점과 필요한 완료 시점이 다르지만, 기다리는 조건은 각각 finalizer 소멸과 명시한 status로 서로 다릅니다.

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

한 모듈의 리소스가 다른 모듈이 실제로 준비된 뒤에 동작해야 하지만 두 모듈 사이에 값(output→input) 참조가 없는 경우, 호출자의 `module` 블록에 `depends_on` 메타 인수를 추가해 순서를 명시합니다.

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The managed CoreDNS add-on must be ACTIVE before the Karpenter controller
  # starts, because the controller needs cluster DNS to reach its dependencies.
  # eks_coredns_addon already depends on the Fargate profile, so this edge also
  # keeps the profile before Karpenter transitively (rules.md D-2/C-4).
  depends_on = [module.eks_coredns_addon]
}
```

현재 순서는 `eks_cluster` → `eks_vpc_cni_addon`/`eks_kube_proxy_addon` → `eks_fargate_profile` → `eks_coredns_addon` → `karpenter`입니다. 관리형 CoreDNS는 Fargate profile 뒤에 생성되어 그 위에 바로 스케줄되고, Karpenter는 **ACTIVE가 된 CoreDNS Add-on**을 직접 기다립니다. `eks_coredns_addon`의 `depends_on = [module.eks_fargate_profile]` 간선 때문에 Fargate 순서는 전이적으로 포함되므로 Karpenter가 Fargate profile을 다시 직접 적을 필요가 없습니다.

Karpenter 모듈은 CoreDNS Add-on의 output을 쓰지 않으므로 값 참조만으로는 이 런타임 순서가 생기지 않습니다. 이처럼 `depends_on`은 "값이 어디서 왔는가"가 아니라 "무엇이 실제로 동작한 뒤여야 하는가"를 표현합니다. D-1번과 이유는 같고 적용 경계만 리소스에서 모듈로 넓어집니다.

### D-3. `network` 모듈이 있는 루트의 다른 모든 `module` 블록은 `network` 전체가 끝난 뒤에 시작한다

루트에 `module "network"`가 있으면, **그 블록을 제외한 모든 루트 `module` 블록**이 직접 또는 다른 모듈을 거쳐 `module.network` 뒤에 오게 합니다. 네트워크 output을 입력으로 받는지, VPC와 기능적으로 관련 있어 보이는지는 판정 조건이 아닙니다.

```hcl
module "eks_cluster" {
  source = "./modules/eks_cluster"

  subnet_ids = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)

  # Subnet value references wait only for the producing subnet resources. This
  # module-wide edge waits for NAT gateways, routes, and associations too.
  depends_on = [module.network]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

  depends_on = [module.network]
}
```

`module.network.vpc_id`/`*_subnet_id` 같은 값 참조는 그 값을 생성한 특정 리소스까지만 간선을 만듭니다. NAT 게이트웨이, 인터넷 게이트웨이, 라우트 테이블과 연결처럼 output에 포함되지 않은 network 모듈의 나머지 리소스는 기다리지 않습니다. 프라이빗 서브넷의 인스턴스가 NAT 준비 전에 부팅하는 경합을 없애고 apply/destroy 순서를 루트 전체에서 일관되게 읽기 위해 network 모듈은 통째로 먼저 완성시킵니다.

- 이는 D-2번의 저장소 전역 특수 규칙이며 선택 사항이 아닙니다.
- `key_pair`, ECR, S3, EventBridge처럼 network 값을 전혀 쓰지 않는 **모듈 블록도 포함**합니다. 모듈마다 네트워크 관련성을 다시 판정하지 않게 하는 것이 목적입니다.
- 범위는 오직 루트의 **다른 `module` 블록**입니다. 루트 `data` 블록과 `resource` 블록은 이 규칙의 대상이 아니며, D-3을 이유로 `depends_on = [module.network]`를 붙이지 않습니다. 그 객체에는 실제 값·런타임 관계가 만드는 일반 그래프와 해당 객체에 적용되는 다른 규칙을 사용합니다.
- 값 참조만으로 생긴 간선은 이 규칙을 만족시키는 간선으로 세지 않습니다. 명시적인 `depends_on` 경로만 봅니다.

#### 직접 간선과 전이 간선은 모두 유효합니다

`depends_on = [module.network]`를 직접 붙이거나, 이미 network를 기다리는 다른 모듈을 `depends_on`으로 가리킬 수 있습니다. `module` 블록의 `depends_on`은 그 모듈 전체를 기다리므로 관계는 합성됩니다. 예를 들어 `eks_coredns_addon`이 `eks_node_group`을 기다리고 `eks_node_group`이 network를 기다리면, CoreDNS는 network 뒤에 전이적으로 놓입니다. 여기에 network를 다시 적어도 그래프에 새로운 순서는 생기지 않습니다.

감사는 `depends_on = [module.network]`의 개수가 아니라 **모듈 간 명시적 간선의 도달 가능성**을 봅니다. 아래 스크립트는 루트 `module` 블록만 수집하므로, 이 규칙의 범위 밖인 루트 `data`/`resource`를 검사하거나 요구하지 않습니다.

```bash
# main.tf의 module 블록과 그 depends_on만 읽어 network에서 도달하지 못하는 모듈을 찾습니다
python - <<'PY'
import pathlib, re
for main in list(pathlib.Path('.').glob('*/main.tf')) + list(pathlib.Path('.').glob('*/*/main.tf')):
    if {'_monolithic', 'modules', '.terraform'} & set(main.parts):
        continue
    text = main.read_text(encoding='utf-8')
    edges = {}
    for m in re.finditer(r'^module "([^"]+)" \{$', text, re.M):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += (text[i] == '{') - (text[i] == '}')
            i += 1
        body = text[m.end():i]
        edges[m.group(1)] = set(re.findall(r'module\.([A-Za-z0-9_]+)',
            ''.join(re.findall(r'depends_on\s*=\s*\[(.*?)\]', body, re.S))))
    if 'network' not in edges:
        continue
    reached, changed = {'network'}, True
    while changed:
        changed = False
        for name, deps in edges.items():
            if name not in reached and deps & reached:
                reached.add(name); changed = True
    missing = sorted(set(edges) - reached)
    if missing:
        print(f'{main.parent}: {missing}')
PY
```

### D-4. Kubernetes 객체를 관리하는 동안 API 경로·실행 용량·컨트롤러를 살아 있게 둔다

E-2번처럼 EKS 클러스터와 `kubectl_manifest`를 같은 루트와 같은 apply에서 만들 때, provider 설정이 `module.eks_cluster.cluster_endpoint`와 인증 정보를 참조한다는 사실만으로는 객체가 필요로 하는 **전체 런타임 수명**이 그래프에 표현되지 않습니다. apply에서 Kubernetes 객체를 만들기 전부터 destroy에서 그 객체가 완전히 사라질 때까지 다음 중 실제로 필요한 것을 살아 있게 둡니다.

| 런타임 의존성 | 필요한 이유 | 대표 대상 |
| --- | --- | --- |
| API 서버와 그 네트워크 경로 | provider가 CREATE/READ/DELETE 요청을 보냄 | EKS 클러스터, private endpoint로 가는 network 경로 |
| 스케줄 가능한 실행 용량 | admission webhook이나 정리 작업을 수행할 파드가 실행됨 | 관리형 노드그룹, Fargate profile, Karpenter가 제공한 용량 |
| 객체를 reconcile하는 컨트롤러 | status 갱신, 외부 리소스 정리, finalizer 제거 | AWS Load Balancer Controller, VPC Lattice controller 등 |

하나가 먼저 사라지면 서로 다른 원인이 같은 연결 실패로 보일 수 있습니다. 실제로 다음 오류는 API 서버 자체가 사라졌을 때뿐 아니라 API 경로가 끊겼을 때도 나타납니다.

```
Error: default/default-sgp failed to create kubernetes rest client for update of resource: Get "https://....eks.amazonaws.com/api?timeout=32s": dial tcp 10.0.0.101:443: i/o timeout
```

`default-sgp`의 `SecurityGroupPolicy`는 **커스텀 리소스(CR)**입니다. 그 kind를 정의하는 `CustomResourceDefinition`(CRD)과 같은 것이 아닙니다. CR이 finalizer나 컨트롤러 동작에 기대면 해당 컨트롤러도 객체 삭제가 끝날 때까지 살아 있어야 합니다.

#### 기본은 루트 `module` 블록의 `depends_on`

모듈 경계에서 실제 런타임 관계를 아는 호출자가, Kubernetes 객체를 소유한 `module` 블록에 의존성을 겁니다. apply에서는 객체 모듈을 런타임 의존성 뒤에 두고, destroy에서는 역순으로 객체 모듈을 먼저 제거합니다.

```hcl
module "lattice_routes" {
  source = "./modules/lattice_routes"

  # The manifests need a reachable API, schedulable controller capacity, and
  # the Lattice controller through deletion. node_group is already after the
  # cluster and network, so those lifetimes are included transitively.
  depends_on = [
    module.eks_node_group,
    module.vpc_lattice_gateway_controller,
  ]
}
```

- 막연히 "가장 마지막 모듈"을 고르지 말고 각 객체의 API 경로, webhook, scheduler, reconciler, finalizer 주체를 확인합니다.
- 여러 실행 용량이 있어도 그 객체를 처리하는 파드가 실제로 스케줄되는 용량만 넣습니다. 값 참조나 provider 설정이 이 수명을 대신한다고 가정하지 않습니다.
- finalizer가 있는 객체에는 이 순서와 D-7번의 `wait = true`가 **둘 다** 필요합니다. 순서는 컨트롤러를 살려두고, `wait`는 DELETE가 실제 소멸까지 끝나게 합니다.
- `aws_eks_addon`은 AWS provider가 EKS 서비스 API로 관리하므로 이 규칙의 `kubectl_manifest` 수명 간선 대상이 아닙니다. 반면 `kubectl_manifest`로 적용한 CRD와 CR은 모두 클러스터 API를 직접 사용하므로 대상입니다.

#### 예외: 혼합 모듈 전체를 늦추는 피해가 더 클 때만 좁은 dependency carrier를 쓴다

우선 Kubernetes 객체를 별도 모듈로 분리해 루트 `module` 블록에서 순서를 표현합니다. 다만 하나의 혼합 모듈에 plan 시점 `data`, 독립 AWS 리소스, Kubernetes 객체가 함께 있고 모듈 전체 `depends_on`이 무관한 객체까지 apply로 미뤄 D-6번 문제나 불필요한 직렬화를 만드는 경우에는, **관련 `kubectl_manifest` 하나에만 도달하는 dependency-carrier input**을 문서화된 예외로 둘 수 있습니다.

carrier는 실제 upstream 런타임 리소스에서 나온 output을 받고 그 output의 구체 타입으로 선언합니다. `type = any`로 리소스나 모듈 객체 전체를 넘기지 않고, `depends_on = [var.x]`처럼 변수를 메타 인수에 직접 넣지도 않습니다. 다음은 release ID 문자열을 `terraform_data`에 소비시켜 해당 매니페스트에만 간선을 전달하는 형태입니다.

```hcl
# child variables.tf
variable "controller_release_id" {
  type        = string
  description = "Release ID used only to carry the controller runtime dependency to controller-owned manifests"

  validation {
    condition     = length(var.controller_release_id) > 0
    error_message = "controller_release_id must be a non-empty release ID from the controller module."
  }
}

# child main.tf
resource "terraform_data" "controller_runtime" {
  input = var.controller_release_id
}

resource "kubectl_manifest" "route" {
  yaml_body = yamlencode({ ... })

  # Narrow exception: delaying this mixed module as a whole would defer its
  # unrelated plan-time data. Keep the controller alive only for this object.
  depends_on = [terraform_data.controller_runtime]
}

# root module call
module "mixed_workload" {
  source = "./modules/mixed_workload"

  controller_release_id = module.vpc_lattice_gateway_controller.release_id

  # D-3 still applies to the module as a whole. The carrier above is only the
  # narrower controller-lifetime edge.
  depends_on = [module.network]
}
```

이 output은 모듈 입력을 그대로 되돌린 문자열이 아니라 `helm_release` 같은 **실제 런타임 리소스에서 파생**되어야 간선의 의미가 있습니다. 예외를 쓸 때는 왜 모듈 분리가 불가능하거나 더 해로운지, 어떤 객체만 어떤 런타임을 필요로 하는지를 인접 주석에 적습니다.

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

### D-6. `module` 블록의 `depends_on`은 그 모듈 안의 `data` 소스까지 apply로 미룬다 — plan 시점에 읽혀야 하는 `data`는 모듈 밖에 둔다

`module` 블록의 `depends_on`은 리소스만 늦추는 것이 아닙니다. **그 모듈 안에 선언된 모든 `data` 소스가 plan 단계에서 읽히지 않고 apply로 미뤄집니다.** 순서를 지키려면 의존 대상이 만들어진 뒤에 읽어야 하므로 Terraform으로서는 맞는 동작이지만, 결과적으로 그 `data`에서 파생된 모든 값이 plan 시점에 unknown이 됩니다.

이것이 B-8번과 겹치면 진단이 어긋납니다. `for_each`의 키를 그 `data`에서 만들고 있으면 plan이 이렇게 실패합니다.

```
Error: Invalid for_each argument
  on modules\gateway_api_crds\main.tf line 79, in resource "kubectl_manifest" "crd":
  79:   for_each  = local.keyed_documents
    │ local.keyed_documents will be known only after apply
```

**메시지는 `local`을 가리키지만 원인은 루트의 `module` 블록에 있습니다.** `data "http"`는 클러스터와 아무 관계가 없어 혼자 두면 plan에서 읽히는데, 그 모듈에 `depends_on = [module.eks_node_group]`이 붙어 있어서 미뤄진 것입니다. 로컬 표현식이나 split 방식을 의심하며 시간을 쓰게 되는 지점입니다.

`070_eks_vpc_lattice`의 Gateway API CRD 번들이 이 사례입니다. 해결은 **`data`를 루트로 옮기고 그 결과를 변수로 넘기는 것**입니다.

```hcl
# 루트 main.tf - 이 data 소스에는 depends_on이 없으므로 plan에서 읽힙니다
data "http" "gateway_api_bundle" {
  url = local.gateway_api_crd_url
}
module "gateway_api_crds" {
  source = "./modules/gateway_api_crds"

  bundle_yaml = data.http.gateway_api_bundle.response_body

  # 모듈의 순서는 그대로 유지합니다. 이 depends_on이 정하는 것은 CRD가 "언제 적용되는지"이고,
  # 번들을 "언제 읽는지"와는 분리되었습니다 (rules.md D-6).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
```

- **모듈의 `depends_on`을 떼는 방식으로 풀지 않습니다.** 그 순서는 D-4번이 요구하는 것이고(destroy 역순), 값을 읽는 시점과는 별개의 요구사항입니다. 둘을 분리하는 것이 옳습니다.
- **모듈 안에 남아도 되는 `data`는 apply 시점 값으로 충분한 것뿐입니다.** `data.aws_caller_identity`, `data.aws_region`처럼 결과가 리소스 주소나 `count`/`for_each` 키에 쓰이지 않는 것은 미뤄져도 아무 문제가 없습니다. 판정 기준은 "그 값이 plan 시점에 알려져야 하는가"입니다.
- 이 규칙은 리소스 레벨 `depends_on`(D-1번)에는 해당하지 않습니다. 리소스에 붙인 `depends_on`은 그 리소스만 늦추므로, 같은 모듈의 `data` 소스는 정상적으로 plan에서 읽힙니다.
- **`terraform validate`는 이것을 잡지 못합니다.** 구성은 유효하고, 실패는 `plan`에서만 드러납니다. A-2번의 "validate로 판정한다"가 적용되지 않는 사례이므로, `for_each`를 쓰는 모듈을 추가했으면 `plan`까지 돌립니다.

#### 감사: 후보 검색 뒤에 수동 symbol trace와 `plan`을 한다

정적 검색만으로 위반을 확정할 수 없습니다. 같은 모듈에 `data`와 `for_each`가 있다는 사실만으로는 둘 사이의 데이터 흐름이 없을 수 있습니다. 아래 스크립트는 **검토 후보만** 나열합니다. 출력 한 줄을 위반으로 간주하거나 자동 수정하지 않습니다.

```bash
# 후보 검색 전용: depends_on이 있는 로컬 모듈 중 data와 count/for_each를 함께 가진 곳
python - <<'PY'
import pathlib, re
for main in list(pathlib.Path('.').glob('*/main.tf')) + list(pathlib.Path('.').glob('*/*/main.tf')):
    if {'_monolithic', 'modules', '.terraform'} & set(main.parts):
        continue
    text = main.read_text(encoding='utf-8')
    for call in re.finditer(r'^module "([^"]+)" \{(.*?)^\}', text, re.M | re.S):
        body = call.group(2)
        source = re.search(r'source\s*=\s*"\./modules/([^"]+)"', body)
        if 'depends_on' not in body or source is None:
            continue
        module_dir = main.parent / 'modules' / source.group(1)
        blob = '\n'.join(p.read_text(encoding='utf-8') for p in sorted(module_dir.glob('*.tf')))
        if re.search(r'^data "', blob, re.M) and re.search(r'^\s*(?:for_each|count)\s*=', blob, re.M):
            print(f'{main.parent} -> {module_dir}')
PY
```

각 후보는 다음 순서로 판정합니다.

1. 자식의 `count`/`for_each`와 리소스 이름 식에서 참조하는 symbol을 적습니다.
2. `local`과 module input을 재귀적으로 따라가 실제로 자식 `data.*`에서 유래하는지 확인합니다. 같은 파일에 존재한다는 사실은 간선이 아닙니다.
3. 그 결과가 **인스턴스 주소의 키·개수**를 정하는지 확인합니다. 정적 키를 가진 map의 unknown value처럼 주소를 바꾸지 않는 값은 B-8번에 따라 허용됩니다.
4. 실제 루트에서 `terraform plan`을 실행합니다. `terraform validate`는 읽기 지연으로 생긴 unknown 주소를 잡지 못합니다.

plan에서 `known only after apply`가 `count`/`for_each`를 막으면 plan 시점 읽기가 필요한 `data`를 루트로 옮겨 값으로 넘깁니다. D-4번의 런타임 수명 순서를 없애기 위해 모듈 `depends_on`을 떼지 않습니다.

### D-7. 컨트롤러가 finalizer를 붙이는 오브젝트는 `kubectl_manifest`에 `wait = true`를 설정한다 — `depends_on`은 DELETE를 **보내는** 시점만 정하고 끝나는 시점은 정하지 않는다

D-4번은 매니페스트를 컨트롤러보다 먼저 지우도록 순서를 잡습니다. 그것으로 충분하다고 읽히지만, **finalizer가 걸린 오브젝트에는 충분하지 않습니다.**

`kubectl_manifest`의 `wait`는 기본값이 `false`이고, 그 상태에서 삭제는 DELETE를 보내고 **즉시 반환합니다.** finalizer가 있는 오브젝트의 DELETE는 삭제가 아니라 `deletionTimestamp`를 찍는 것뿐이므로, 오브젝트는 `Terminating`으로 남은 채 Terraform은 그 리소스를 지웠다고 판단하고 다음으로 넘어갑니다. 몇 초 뒤 컨트롤러가 uninstall되고, finalizer를 떼어줄 주체가 사라집니다.

`070_eks_vpc_lattice`의 destroy가 이 순서로 실패했습니다. 간격은 **8초**였습니다.

| 시각 | 무엇이 | 결과 |
| --- | --- | --- |
| 06:58:14 | HTTPRoute 2개 DELETE | `Terminating`, `httproute.k8s.aws/resources` 남음 |
| 06:58:16 | Gateway DELETE | `Terminating`, `gateway.k8s.aws/resources` 남음 |
| (직후) | 컨트롤러 helm uninstall | finalizer를 뗄 주체가 사라짐 |
| 06:58:22 | CRD 2개 DELETE | `customresourcecleanup`에서 **영구 정지** |

드러난 에러는 CRD 쪽입니다.

```
Error: gateways.gateway.networking.k8s.io failed to delete resource
Error: httproutes.gateway.networking.k8s.io failed to delete resource
```

**에러가 가리키는 리소스가 원인이 아닙니다.** CRD는 자기 kind의 인스턴스가 하나라도 남아 있으면 `customresourcecleanup.apiextensions.k8s.io` finalizer에 걸려 삭제되지 않습니다. 멈춘 것은 CRD이고, 멈춘 이유는 세 개의 인스턴스이며, 그 인스턴스가 남은 이유는 컨트롤러가 먼저 사라진 것입니다. CRD 모듈을 들여다보는 동안 원인은 세 모듈 밖에 있습니다.

#### `wait = true`를 어디에 붙이는가

판정 기준은 하나입니다: **그 오브젝트에 finalizer를 붙이는 컨트롤러가 있는가.** 있으면 붙이고, 없으면 붙이지 않습니다.

```hcl
resource "kubectl_manifest" "http_route" {
  yaml_body = yamlencode({ ... })

  # 컨트롤러가 httproute.k8s.aws/resources finalizer를 붙이고, 그것을 떼는 일이 곧 Lattice 서비스와
  # 타깃그룹을 지우는 일입니다. wait 없이는 오브젝트가 Terminating인 상태로 destroy가 진행되고,
  # 컨트롤러가 사라진 뒤에는 떼어줄 주체가 없습니다 (rules.md D-7).
  wait = true
}
```

- **`wait`는 삭제 전용 플래그입니다.** 프로바이더의 스키마 설명이 `Set this flag to wait or not for any deleted resources to be gone. This waits for finalizers.`이고, 문서도 `wait for finalizers to complete on deleted objects before returning`으로 같은 말을 합니다. **생성에는 아무 영향이 없습니다** — 생성 쪽을 기다리는 것은 `wait_for`와 `wait_for_rollout`입니다. `wait = true`에 "CRD가 serving을 시작할 때까지 기다린다" 같은 주석을 달지 않습니다. `070`에 그 주석이 있었고 틀린 것이었습니다.
- `wait = true`는 `delete_cascade`의 기본값을 `Background`에서 `Foreground`로 바꿉니다. `kubectl`과 같은 동작이 필요하면 `Background`를 명시합니다.
- 기다림은 `timeouts`의 `delete`(기본 10분)가 제한합니다. 그래서 영구 정지가 아니라 **그 오브젝트를 지목하는 실패**가 됩니다. 이것이 이 플래그의 두 번째 값입니다: 고치지 못하는 상황이어도 어디가 문제인지는 알려줍니다.
- **반대로, 떼어줄 컨트롤러가 이미 없는 상태에서 `wait = true`는 10분을 기다린 뒤 실패합니다.** 그 상황은 이 플래그가 만든 것이 아니라 이 플래그가 드러낸 것입니다. 복구는 아래 "이미 멈췄다면" 절입니다.

#### `wait = true`만으로는 부족하고 순서가 함께 필요하다

`wait = true`는 "finalizer가 떨어질 때까지 기다린다"이지 "컨트롤러를 살려둔다"가 아닙니다. 컨트롤러가 먼저 지워지는 순서라면 기다림이 타임아웃으로 끝날 뿐입니다. **그 오브젝트를 처리하는 컨트롤러를 `depends_on`에 명시하는 것이 짝입니다**(D-4번).

이 짝이 깨지기 쉬운 지점은 **오브젝트가 컨트롤러를 언급하지 않는 경우**입니다. `070`의 백엔드 Service가 그랬습니다 — 평범한 ClusterIP Service이고 매니페스트에 Lattice가 한 글자도 없지만, HTTPRoute가 그 Service를 `backendRef`로 가리키는 순간 컨트롤러가 거기서 타깃그룹을 만들고 finalizer를 붙입니다. 모듈은 컨트롤러의 output을 쓸 일이 없으니 값 참조로는 간선이 생기지 않고, 루트의 `depends_on`에도 컨트롤러가 없었습니다.

```hcl
module "backend_service" {
  source   = "./modules/http_echo_service"
  for_each = var.backend_services
  # ...

  # 생성에는 노드만 필요합니다. 컨트롤러가 목록에 있는 것은 destroy 때문입니다 - 라우트가 이 Service를
  # backendRef로 가리키면 컨트롤러가 finalizer를 갖게 되고, 그것을 떼는 일이 타깃그룹을 지우는
  # 일입니다 (rules.md D-4/D-7).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.vpc_lattice_gateway_controller,
  ]
}
```

- 결과는 조용합니다. 타깃그룹 3개가 계정에 남았고 `terraform destroy`는 그 부분에 대해 아무 에러도 내지 않았습니다. **CRD처럼 걸려 주는 것이 없는 내장 kind(Service, ConfigMap 등)에서는 이 실패가 에러 없이 끝납니다.**
- 주석에 "컨트롤러 뒤에 온다"고 적고 `depends_on`에는 넣지 않는 것이 실제로 있었던 형태입니다. 주석은 간선을 만들지 않습니다.

#### finalizer를 붙이는 주체는 컨트롤러 소스에서 확인한다

이름을 짐작하지 않습니다. `070`이 쓰는 컨트롤러 v1.1.5의 실제 값:

| 오브젝트 | finalizer | 떼어질 때 지워지는 AWS 리소스 |
| --- | --- | --- |
| `Gateway` | `gateway.k8s.aws/resources` | 서비스 네트워크, VPC association |
| `HTTPRoute` | `httproute.k8s.aws/resources` | Lattice 서비스, 리스너, 규칙 |
| `Service` | **`service.ki8s.aws/resources`** | 타깃그룹 |
| `GatewayClass` | (없음) | — |

**`Service`의 것은 업스트림 오타입니다**(`ki8s`). `service.k8s.aws`로 grep하면 0건이 나오고, finalizer가 없다고 오판하게 됩니다. `GatewayClass`에 finalizer가 없다는 것도 확인된 사실이고, 그래서 `gatewayclasses` CRD만 정상적으로 삭제되었습니다 — 어느 CRD가 멈췄는지가 어느 kind에 finalizer가 있는지를 알려줍니다.

```bash
# 짐작하지 말고 그 버전의 소스에서 읽습니다
for f in service_controller gateway_controller route_controller; do
  curl -fsSL "https://raw.githubusercontent.com/aws/aws-application-networking-k8s/v1.1.5/pkg/controllers/$f.go" \
    | grep -nE 'Finalizer\s*=|"[a-z]+\.k?i?8?s?\.aws/resources"'
done
```

#### 이미 멈췄다면

finalizer를 떼는 것이 복구이지만, **그 전에 AWS 쪽을 먼저 지웁니다.** finalizer는 "지울 것이 남아 있다"는 표시이고, 그것을 떼는 것은 지우는 것이 아니라 **잊는 것**입니다. 먼저 떼면 AWS 리소스가 고아로 남고 추적할 단서도 함께 사라집니다.

```bash
# 1. 무엇이 멈춰 있고 누가 붙인 finalizer인지
kubectl get crd <plural>.<group> -o jsonpath='{.metadata.deletionTimestamp}{"  "}{.metadata.finalizers}{"\n"}'
kubectl get <kind> -A -o json \
  | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)  \(.metadata.finalizers)"'

# 2. AWS 쪽을 의존 순서대로 지웁니다 (Lattice의 경우)
#    service-network-service association -> service -> deregister-targets -> target-group
#    -> service-network-vpc-association -> service-network

# 3. 그 다음에 finalizer를 뗍니다. CRD가 아니라 인스턴스에서 뗍니다 -
#    마지막 인스턴스가 사라지면 CRD는 스스로 종료됩니다
kubectl -n <ns> patch <kind> <name> --type merge -p '{"metadata":{"finalizers":null}}'

# 4. terraform destroy 재실행
```

- **CRD의 `customresourcecleanup` finalizer는 건드리지 않습니다.** 그것을 떼면 CRD는 사라지지만 인스턴스가 etcd에 남아 같은 CRD를 다시 설치했을 때 되살아납니다. 인스턴스를 먼저 비우면 CRD는 손댈 필요가 없습니다.
- 복구 뒤에는 **왜 멈췄는지를 코드에 반영합니다.** 손으로 finalizer를 뗀 것은 같은 destroy를 다음에도 똑같이 실패하게 둔 것입니다.

#### 확인하는 방법

컨트롤러가 reconcile하는 kind를 선언하면서 `wait`를 설정하지 않은 `kubectl_manifest`를 찾습니다. kind 목록은 프로젝트가 쓰는 컨트롤러에 따라 다르므로, 아래의 목록을 그 프로젝트의 것으로 바꿔서 씁니다.

```bash
python - <<'PY'
import pathlib, re
# finalizer가 붙는 kind. 내장 kind(Service)도 포함됩니다 - 에러를 내지 않는 쪽이 오히려 위험합니다
WATCHED = {'Gateway', 'HTTPRoute', 'GRPCRoute', 'TLSRoute', 'Service', 'TargetGroupPolicy'}
for tf in pathlib.Path('.').rglob('modules/*/main.tf'):
    if {'_monolithic', '.terraform'} & set(tf.parts):
        continue
    text = tf.read_text(encoding='utf-8')
    for m in re.finditer(r'resource "kubectl_manifest" "([^"]+)" \{', text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += (text[i] == '{') - (text[i] == '}')
            i += 1
        body = text[m.end():i]
        kind = re.search(r'kind\s*=\s*"([A-Za-z]+)"', body)
        if kind and kind.group(1) in WATCHED and not re.search(r'^\s*wait\s*=\s*true', body, re.M):
            print(f'{tf}: {m.group(1)} is a {kind.group(1)} with no wait = true')
PY
```

그리고 **apply 후의 destroy 리허설이 유일한 진짜 검증입니다.** `wait`가 빠진 것은 plan에도 validate에도 나타나지 않고, 성공한 apply에도 나타나지 않습니다. 드러나는 곳은 destroy 하나뿐이며, 그때는 이미 클러스터가 반쯤 사라진 상태입니다.

### D-8. 뒤 리소스가 **status**를 보고 동작하는 오브젝트는 `kubectl_manifest`에 `wait_for`를 설정한다 — `depends_on`은 CREATE를 **보내는** 시점만 정하고 준비된 시점은 정하지 않는다

D-7번과 같은 "요청 시점과 완료 시점은 다르다"는 문제를 생성·갱신 쪽에서 만나는 규칙입니다. 다만 `kubectl_manifest`가 **모든 kind에서 언제나 API 접수 즉시 반환한다**고 일반화하면 안 됩니다. `wait_for_rollout`이 적용되는 workload나 명시적 `wait_for`가 있는 객체는 프로바이더가 해당 조건을 기다릴 수 있습니다.

문제는 필요한 준비 조건에 맞는 대기가 없는 객체입니다. 특히 PVC는 생성 요청이 접수되어 `Pending`인 것만으로 매니페스트 apply가 끝날 수 있으며, 기본 동작이 `status.phase = Bound`를 기다려 주지 않습니다. 뒤 파드가 claim의 status를 필요로 하면 API 객체의 존재만으로는 충분하지 않습니다. `depends_on`은 PV → PVC → Pod의 **요청 순서**를 정하고, `wait_for`는 PVC가 Bound가 되는 **준비 간격**을 메웁니다.

`104_eks_fargate_efs_volume`의 apply가 이렇게 실패했습니다. PV·PVC·Pod 다섯 개가 **같은 초에** 만들어졌고, reader 파드만 Pending에 갇혔습니다.

```
Warning  FailedScheduling  14m  fargate-scheduler
  Pod not supported on Fargate: volumes not supported: efs-volume not supported because: PVC read-pvc not bound
```

#### 이 실패가 스스로 낫지 않는 이유

**`fargate-scheduler`는 재시도하지 않습니다.** 기본 `kube-scheduler`는 스케줄 실패한 파드를 큐에 되돌려놓고 PVC가 bound되면 다시 시도하므로, 같은 경합이 노드그룹 클러스터에서는 몇 초 뒤 저절로 해결됩니다. Fargate의 admission은 **일회성 판정**이라 한 번 "not supported"로 거부된 파드는 영원히 재검토되지 않습니다.

그래서 증상이 혼란스럽습니다 — 나중에 들어가서 보면 **PVC는 Bound이고 에러만 과거에 남아 있습니다.**

```bash
kubectl get pvc    # read-pvc   Bound   read-pv   5Gi   RWX
kubectl get pod    # read       0/1     Pending   14m
kubectl get events --field-selector involvedObject.name=read   # FailedScheduling 하나, 재시도 0회
```

**이벤트가 하나뿐이고 PVC가 이미 Bound이면 경합입니다.** 매니페스트를 고칠 것이 없으니 바인딩 조건(용량·접근모드·클래스)을 들여다보게 되는데, 거기에는 틀린 것이 없습니다.

#### `volumeName`으로 pre-bind하는 claim이 체계적으로 느립니다

같은 경합이 두 claim에 똑같이 걸렸는데 reader만 진 것이 우연이 아닙니다.

| claim | 바인딩 경로 | 첫 sync에서 |
| --- | --- | --- |
| `efs-pvc` (StorageClass 매칭) | 볼륨 컨트롤러가 클래스로 후보 PV를 찾음 | 보통 성공 |
| `read-pvc` (`volumeName` 지정) | `spec.volumeName`을 **PV 캐시에서 조회** | 방금 만든 PV가 캐시에 없어 포기, 다음 sync까지 대기 |

`volumeName` 경로는 조회할 대상이 하나 더 있고, 그래서 놓칠 것도 하나 더 많습니다. **pre-bind가 더 직접적이니 더 빠를 것이라는 직관과 반대입니다.**

#### 무엇을 하는가

판정 기준은 하나입니다: **뒤 리소스가 이 오브젝트의 `status`를 보는가.** 보면 붙이고, 이름만 참조하면 붙이지 않습니다.

```hcl
resource "kubectl_manifest" "read_persistent_volume_claim" {
  yaml_body = yamlencode({ ... })

  # depends_on은 API 호출의 순서만 정하고 phase는 정하지 않습니다. PVC는 Pending으로
  # 태어나 볼륨 컨트롤러가 PV를 붙인 뒤에 Bound가 되는데, kubectl_manifest는 접수
  # 시점에 반환하므로 아래 파드가 같은 초에 만들어집니다. fargate-scheduler는 claim이
  # Pending인 파드를 한 번 거부하고 다시 보지 않습니다 (rules.md D-8).
  wait_for {
    field {
      key   = "status.phase"
      value = "Bound"
    }
  }

  # This edge orders Kubernetes objects: the PVC request follows the PV request.
  # It is not the D-4 module-lifetime edge that keeps the API path, capacity,
  # and controllers alive through destroy.
  depends_on = [kubectl_manifest.read_persistent_volume]
}
```

- **`wait_for`는 생성·갱신 준비 조건이고 `wait`는 삭제 조건입니다.** 이름이 비슷하지만 D-7번의 `wait = true`는 finalizer가 떨어져 객체가 사라지기를 기다리며 생성 준비에는 영향을 주지 않습니다. 한 리소스가 두 조건을 모두 필요로 하면 둘 다 적습니다.
- `field`의 `key`는 루트부터의 경로입니다(`status.phase`). 정규식이 필요하면 `value_type = "regex"`를 씁니다. Condition을 보는 객체에는 `field` 대신 `condition { type = ..., status = ... }`를 씁니다.
- 기다림은 해당 create/update timeout이 제한합니다. 그래서 영구 Pending이 아니라 **그 claim을 지목하는 apply 실패**가 됩니다. 못 고치는 상황에서도 어느 준비 조건이 실패했는지를 알려줍니다.
- **경합에서 이긴 쪽에도 붙입니다.** `104`의 writer는 같은 경합을 통과했지만 그것은 운이고, 다음 apply에서 순서가 바뀝니다.
- **두 종류의 간선을 섞지 않습니다.** 예제의 `depends_on = [kubectl_manifest.read_persistent_volume]`은 같은 Kubernetes 객체 그래프 안의 PV → PVC 요청 순서입니다. D-4번은 루트 모듈 경계에서 API 경로·실행 용량·컨트롤러를 객체보다 오래 살리는 런타임 수명 간선입니다. 이 PVC가 그 런타임도 필요로 하면 모듈 호출의 D-4 `depends_on`을 별도로 유지합니다.

#### 이미 갇혔다면 파드를 다시 만듭니다

Fargate의 판정은 파드 단위로 한 번 내려지고 끝이므로, **PVC가 Bound가 되어도 그 파드는 살아나지 않습니다.** 고칠 대상은 PVC가 아니라 파드입니다.

```bash
terraform apply -replace='module.<module>.kubectl_manifest.<pod>'
```

- Deployment/StatefulSet이 소유한 파드도 스스로 낫지 않습니다. 스케줄 실패한 파드는 `Pending`으로 **존재하는** 상태라서 ReplicaSet은 대체 파드를 만들지 않습니다. `kubectl delete pod`로 컨트롤러가 다시 만들게 합니다.
- `volumeClaimTemplates`를 쓰는 StatefulSet은 이 문제에서 자유롭습니다. PVC를 StatefulSet 컨트롤러가 만들고 bound를 기다린 뒤에 파드를 만들기 때문입니다 — **Terraform이 PVC를 따로 선언했을 때만 경합이 생깁니다.**

#### 확인하는 방법

`claimName`으로 PVC를 참조하는 워크로드가 있는데 그 PVC에 `wait_for`가 없는 모듈을 찾습니다. Fargate 프로젝트에서는 위반이고, 노드그룹 프로젝트에서는 스케줄러가 재시도하므로 느려지기만 합니다.

```bash
python - <<'PY'
import pathlib, re
for tf in pathlib.Path('.').rglob('modules/*/main.tf'):
    if {'_monolithic', '.terraform'} & set(tf.parts):
        continue
    text = tf.read_text(encoding='utf-8')
    if 'claimName' not in text:
        continue
    for m in re.finditer(r'resource "kubectl_manifest" "([^"]+)" \{', text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += (text[i] == '{') - (text[i] == '}')
            i += 1
        body = text[m.end():i]
        if re.search(r'kind\s*=\s*"PersistentVolumeClaim"', body) and 'wait_for' not in body:
            print(f'{tf}: {m.group(1)} is a PVC with no wait_for')
PY
```

**apply가 성공해도 이것이 없다는 사실은 드러나지 않습니다.** 경합이므로 통과하는 apply가 대부분이고, 드러나는 것은 하필 진 쪽의 파드 하나입니다.

### D-9. `check` 블록은 루트에 둔다 — 모듈 안의 `check`는 그 모듈의 close를 검사 단계 뒤로 밀어서, 그 모듈을 `depends_on`으로 가리키는 다른 모듈과 순환을 만든다

`check` 블록 안에 중첩한 `data` 소스는 **검사 단계(`(execute checks)`)에서 평가되고, 그 단계는 모든 관리 리소스 뒤에 옵니다.** 그리고 모듈은 자기 `check`가 실행되기 전까지 close하지 않습니다. 둘을 합치면 `module.<name> (close)`가 "모든 리소스 이후"에 의존하게 되고, 그 모듈을 `depends_on`으로 기다리는 다른 모듈이 하나라도 있으면 순환이 닫힙니다.

`082_code_pipeline_eks/github_source`에서 실제로 닫힌 경로입니다.

```
module.pipeline (expand)
  -> module.pipeline_source (close)        # depends_on = [module.pipeline_source] (D-2)
    -> module.pipeline_source.check.connection_available
      -> (execute checks)                  # 모든 리소스 이후
        -> aws_ssm_association.vscode_readme
          -> local.readme_body -> local.outputs   # H-2의 출력 맵
            -> module.pipeline.output.*
              -> module.pipeline (close) -> module.pipeline (expand)
```

**진단의 단서는 `(execute checks)`입니다.** Terraform이 뱉는 `Error: Cycle:`은 그래프의 거의 전부를 한 줄로 나열하므로 어디가 원인인지 보이지 않습니다. 그 목록에서 `(execute checks)`와 `module.<name> (close)`가 함께 보이면 이 경우입니다 — 나열된 리소스들은 전부 지나가는 길이고, 원인은 `check`의 위치 하나입니다.

- **어느 쪽도 틀린 것이 아니라는 점이 함정입니다.** `depends_on`은 D-2번이 요구하는 것이고, `check`는 plan 시점에 상태를 드러내려고 둔 것입니다. 하나를 지워서 풀지 않고 **`check`를 루트로 옮깁니다.** 루트의 close에 의존하는 것은 아무것도 없으므로 같은 `check`가 루트에서는 간선을 만들지 않습니다.
- 옮긴 자리에는 **왜 주제가 다른 곳에 있는지 적습니다.** 모듈 쪽에도 한 줄 남겨야 다음 사람이 "이 검사는 왜 모듈에 없는가"를 다시 판정하지 않습니다.
- `check`에 `data`를 중첩하지 않고 리소스 속성만 단정하면 이 순환은 생기지 않습니다. 다만 중첩을 쓰는 이유가 따로 있습니다: 중첩한 `data`의 읽기 실패는 경고로 끝나고, 최상위 `data`의 실패는 plan을 중단시킵니다. 그리고 리소스 속성은 마지막 refresh가 기록한 값이라 `-refresh=false`에서는 낡은 값을 단정합니다. 그래서 중첩을 유지하고 위치를 옮기는 것이 맞습니다.
- **`validate`와 `plan`으로는 재현되지 않을 수 있습니다.** 순환은 그래프 생성 시점의 문제이지만, 프로바이더 구성이 먼저 실패하면 그 오류가 앞서 나옵니다. 자격증명이 틀린 상태로 돌린 plan이 `Bad credentials`만 내고 순환을 보여주지 않는 것이 그 경우입니다 — 순환을 확인하려면 프로바이더가 구성되는 환경에서 돌려야 합니다.
- 확인하는 방법: 모듈 안의 `check` 블록을 찾고, 그 모듈을 `depends_on`으로 가리키는 `module` 블록이 있는지 봅니다. 둘이 겹치면 순환입니다.

```bash
# 모듈이 소유한 check 블록
grep -rn '^check "' --include='*.tf' . | grep '/modules/' | grep -v '_monolithic'
# 그 모듈을 depends_on으로 기다리는 루트의 module 블록이 있으면 순환
grep -rn -B2 -A8 'depends_on' --include='main.tf' . | grep -v '_monolithic' | grep 'module\.'
```
