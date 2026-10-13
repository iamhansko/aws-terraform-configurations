---
inclusion: always
---

# AWS Load Balancer Controller Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-security-groups.md`](rules-security-groups.md) · **Next:** [`rules-ec2-workbench-and-outputs.md`](rules-ec2-workbench-and-outputs.md)
> 논리 인용 `rules.md G-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| G-1 | AWS Load Balancer Controller로 Ingress/Service를 외부에 노출 | controller 선택, target type, 포트, subnet, SG 소유권을 한 조합으로 설계 | C-2·F-2·G-2 |
| G-2 | 프론트엔드 SG 또는 backend rule 관리 주체를 선택 | 프론트엔드 SG 소유권 × effective manage 설정으로 backend feature와 규칙 소유자를 결정 | E-7·F-2 |
| G-3 | Terraform이 만든 ALB/NLB를 컨트롤러가 채택 | 필수 식별 태그와 호환 속성을 맞추고, pre-created LB 뒤에 워크로드를 생성 | B-5·D-2·G-1 |
| G-4 | 루트의 `type: LoadBalancer` Service 전체와 Service mutator 정책을 정함 | 모든 Service가 컨트롤러를 명시하면 mutator를 끄고, 하나라도 자동 주입에 의존하면 명시적으로 켜 위험을 수용 | E-7·G-1 |

## G. AWS Load Balancer Controller

**G-1번부터 읽습니다.** G-1번이 전체 구성, G-2번이 프론트엔드 SG와 backend rule 소유권 조합, G-3번이 로드밸런서를 미리 만드는 변형, G-4번이 Service mutator 정책을 정합니다.

### G-1. AWS Load Balancer Controller로 ALB(Ingress)와 NLB(Service)를 만드는 구성 규칙

Provider 분기에서는 C-2번대로 IRSA 역할과 `helm_release`를 한 모듈(`modules/aws_load_balancer_controller`)에 둡니다. `version`을 핀하고 `wait = true`로 Deployment가 Available이 될 때까지 apply를 기다립니다. runner는 API에 못 닿지만 VPC 관리 인스턴스는 닿는 SSM 분기에서는 C-2·E-9번대로 AWS 전용 IAM 모듈과 `helm upgrade --install --wait` 단계를 나눕니다. 두 분기 모두 `_monolithic`의 `kubectl rollout status -n kube-system deploy aws-load-balancer-controller`가 보장하던 준비 완료를 유지합니다.

#### 컨트롤러에게 넘기는 effective selector를 먼저 확인한다

가장 자주 틀리는 지점입니다. 판정 대상은 작성한 YAML만이 아니라 **admission 이후 실제 객체에 남은 selector**입니다. selector가 없으면 나머지 애노테이션이 조용히 무시될 수 있습니다.

| | 만들 것 | 필요한 effective selector | selector가 없으면 |
| --- | --- | --- | --- |
| ALB | `Ingress` | `spec.ingressClassName: alb` | Ingress를 처리할 컨트롤러가 없어 아무 일도 일어나지 않음 |
| NLB | `Service` (`type: LoadBalancer`) | `service.beta.kubernetes.io/aws-load-balancer-type: "external"` 또는 `spec.loadBalancerClass: service.k8s.aws/nlb` | mutator가 꺼져 있거나 주입하지 않으면 in-tree provider가 Classic Load Balancer를 만들 수 있음 |

NLB Service의 매니페스트에 selector가 없어도 G-4번의 Service mutator가 켜져 있고 Ready이면 admission이 `loadBalancerClass`를 주입하므로 AWS Load Balancer Controller가 처리합니다. 반대로 mutator가 켜졌지만 Ready endpoint가 없으면 `failurePolicy: Fail` 때문에 CLB 생성이 아니라 **Service CREATE 자체가 실패**합니다. mutator를 끈 상태에서 selector도 없을 때가 CLB로 빠지는 위험 경로입니다.

따라서 매니페스트만 보고 판정하지 않습니다. 렌더된 YAML, live Service의 annotation/`spec.loadBalancerClass`, mutator 정책을 함께 확인합니다. CLB가 실제로 만들어졌다면 컨트롤러가 그 Service를 처리하지 않은 것입니다.

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

`target-type = ip`는 VPC CNI가 파드 IP를 VPC에서 라우팅 가능하게 만들어 주기 때문에 동작하므로, `eks_vpc_cni_addon`이 노드보다 먼저 있어야 합니다(C-4번 패턴). 다만 `ip` target이라는 사실만으로 클라이언트 소스 주소 보존이 보장되지는 않습니다. listener/target-group protocol과 `preserve_client_ip.enabled` 속성에 따라 동작이 달라집니다. 소스 IP가 요구사항이면 지원되는 조합에서 `service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "preserve_client_ip.enabled=true"`를 명시하고 실제 target group 속성을 확인합니다. 지원되지 않는 조합에서는 Proxy Protocol v2와 애플리케이션 측 파싱을 설계하며, 검증 전에는 파드 SG allow-list나 감사 로그가 원래 client IP를 본다고 가정하지 않습니다.

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

- 커스텀 프론트엔드 SG + effective `manage-backend-security-group-rules = true`이면 컨트롤러가 노드 규칙을 쓰며 `--enable-backend-security-group=true`가 **필수**입니다.
- 커스텀 프론트엔드 SG + effective manage=false이면 컨트롤러가 backend ingress를 만들지 않으므로 Terraform 같은 외부 소유자가 규칙을 직접 선언해야 합니다. 이 저장소의 일부 변형은 `target-type: ip`에서 이 경로와 `enable_backend_security_group = false`를 선택하지만, 모든 변형의 기본이라고 단정하지 않습니다.
- 컨트롤러가 규칙을 추가하는 **대상 보안그룹**에는 인라인 `ingress`/`egress`를 쓰지 않고 독립 규칙 리소스를 씁니다. `revoke_rules_on_delete`는 외부 주체가 바로 그 그룹에 attached rule을 쓰는 경우에만 적용하며, 다른 그룹이 소유한 참조를 지우는 보편적 해결책은 아닙니다(**F-2번 패턴**).

#### 보안그룹은 Service가 발행하는 포트 **전부**를 열어야 한다

Service가 발행하는 포트마다 컨트롤러가 리스너를 하나씩 만듭니다. 열어야 할 곳이 두 군데이고, 빠뜨렸을 때의 증상이 서로 다릅니다.

| 열 곳 | 무엇을 | 빠뜨리면 |
| --- | --- | --- |
| 프론트엔드 SG | 클라이언트 → 리스너 포트 | 그 포트는 **거부가 아니라 타임아웃**이 됩니다 |
| 파드 쪽 SG(보통 클러스터 SG) | 로드밸런서 → 컨테이너 포트 | 리스너는 붙지만 타깃이 전부 unhealthy |

`ingress-nginx` 차트가 대표적입니다. 현재 저장소가 핀한 차트 버전을 기본 포트 값으로 렌더하면 `controller.service.ports.http = 80`과 `controller.service.ports.https = 443`이 나와 Service와 로드밸런서에 두 포트가 생깁니다. 차트 버전이나 값을 바꾸면 결과도 달라질 수 있으므로, 80/443을 불변값으로 가정하지 말고 실제 렌더된 Service의 모든 포트를 엽니다. 현재 값에서 80만 열면 https가 조용히 막힙니다.

**워크로드가 https로 리다이렉트하면 증상이 한 단계 뒤로 밀립니다.** `http://host`는 80으로 들어가 정상적으로 308을 받고, 브라우저가 그 `Location`(443)으로 이동하면서 비로소 멈춥니다. 80이 열려 있다는 사실이 "로드밸런서는 살아 있다"는 오해를 만들기 때문에, 포트가 아니라 인증서나 워크로드를 먼저 의심하게 됩니다.

그래서 포트는 한 곳에서 정의해 **Service·프론트엔드 SG·파드 쪽 규칙 세 군데에 같은 값을 전달합니다**(B-5번 패턴). 셋이 따로 있으면 어긋나고, 어긋난 것을 apply는 알려주지 않습니다. 맵으로 두면 `for_each`의 키가 규칙 설명에 그대로 드러납니다.

```hcl
# 루트 variables.tf - 차트가 쓰는 이름을 키로 씁니다
variable "load_balancer_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }

  validation {
    # 제약이 값의 모양이 아니라 워크로드가 필요로 하는 것에 관한 것이면 validation에 둡니다 (B-1번)
    condition     = contains(keys(var.load_balancer_ports), "https")
    error_message = "load_balancer_ports must include https, because the dashboard URL this project outputs is https and apply succeeds either way."
  }
}
```

```hcl
# 루트 main.tf - 같은 맵이 세 곳으로 갑니다
module "load_balancer_security_group" { ports         = var.load_balancer_ports }
module "ingress_nginx"                 { service_ports = var.load_balancer_ports }

resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  for_each          = var.load_balancer_ports
  security_group_id = module.eks_cluster.cluster_security_group_id
  description       = "Ingress controller ${each.key} port from the NLB"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  ...
}
```

- **`controller.service.port`는 그 차트에 없는 값입니다.** helm은 모르는 값을 거부하지 않으므로 `--set`이 성공하고 Service는 차트 기본값을 그대로 씁니다. 즉 포트를 바꾼 줄 알았는데 아무 일도 일어나지 않고, 보안그룹만 그 값에 맞춰 좁혀집니다. 올바른 경로는 `controller.service.ports.<name>`입니다.

값 이름이 맞는지는 `values.yaml`을 읽는 것보다 **렌더된 Service를 보는 쪽이 확실합니다.** 오타 난 값은 조용히 버려지므로 `--set`을 준 채로 렌더해서, 나온 포트가 의도한 것인지 확인합니다. 그것이 보안그룹이 열어야 하는 목록입니다.

```bash
helm template <release> <repo>/<chart> --version <v> --kube-version 1.33.0 \
  --set controller.service.type=LoadBalancer \
  | awk '/^kind: Service$/,/^---$/' | grep -E '^  name:|^    - name:|      port:'
#   name: ingress-nginx-controller
#     - name: http
#       port: 80
#     - name: https
#       port: 443
```

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

로드밸런서를 Terraform으로 미리 만들고 컨트롤러가 그것을 재사용하게 하는 구성은 **G-3번 패턴**에 정리되어 있습니다. 세 태그(`elbv2.k8s.aws/cluster`, `<prefix>.k8s.aws/resource`, `<prefix>.k8s.aws/stack`)는 후보를 찾는 데 필요한 식별자일 뿐 충분조건은 아닙니다. 타입·scheme·서브넷 같은 생성 시 속성도 워크로드 모델과 맞아야 하며, 워크로드가 그 pre-created LB를 명시적으로 기다리는 그래프 간선이 있어야 첫 reconcile 전에 후보가 존재합니다. 어느 하나라도 어긋나면 에러 대신 같은 stack의 두 번째 로드밸런서가 생길 수 있습니다.

#### 진단 순서

주소가 채워지지 않을 때 볼 곳은 정해져 있습니다.

```bash
kubectl -n <ns> describe ingress <name>     # 또는 describe service - 컨트롤러 이벤트가 여기 붙습니다
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail 100
```

- 이벤트/로그가 아예 없으면 컨트롤러가 그 오브젝트를 보고 있지 않은 것입니다 → 위의 "넘기는 스위치"를 확인합니다.
- `couldn't auto-discover subnets` → 서브넷 태그와 `scheme` 불일치.
- `backendSG feature is required ...` → G-2번 패턴.

### G-2. 프론트엔드 SG 소유권과 effective backend-rule 관리 설정으로 `--enable-backend-security-group`을 결정한다

판정 축은 하나가 아니라 **프론트엔드 SG를 누가 만드는가 × effective `manage-backend-security-group-rules` 값**입니다. 여기서 effective 값은 개별 Ingress/Service 애노테이션이 있으면 그 값이고, 없으면 컨트롤러의 전역 `--enable-manage-backend-security-group-rules` 값입니다. 개별 애노테이션이 전역값보다 우선하므로, "애노테이션 없음"을 언제나 false로 읽으면 안 됩니다.

| 프론트엔드 SG | effective manage | `enableBackendSecurityGroup` | backend ingress 소유자·소스 | 결과 |
| --- | --- | --- | --- | --- |
| 컨트롤러 자동 생성 | 명시 관리 불필요 | `true` | 컨트롤러가 공유 backend SG를 소스로 규칙 관리 | 유효한 upstream 기본 경로 |
| 컨트롤러 자동 생성 | 명시 관리 불필요 | `false` | 컨트롤러가 로드밸런서별 프론트엔드 SG 경로 사용 | 유효하지만 공유 SG의 규칙 수 절감 효과를 잃음 |
| 커스텀 SG | `true` | `true` | 컨트롤러가 공유 backend SG를 소스로 규칙 관리 | 유효; 이 조합에서는 `true` 필수 |
| 커스텀 SG | `true` | `false` | 소유자를 구성할 수 없음 | **금지**; reconcile의 모델 생성이 실패해 LB와 ADDRESS/EXTERNAL-IP가 생기지 않음 |
| 커스텀 SG | `false` | `true` 또는 `false` | Terraform 등 외부 소유자가 커스텀 SG를 소스로 직접 규칙 선언 | 직접 규칙이 있을 때만 유효; 없으면 LB는 생길 수 있지만 타깃이 전부 unhealthy |

마지막 행에서 `enableBackendSecurityGroup = true`만 설정해도 backend 규칙 관리가 켜지는 것은 아닙니다. 커스텀 SG를 지정한 상태에서 effective manage=false이면 컨트롤러는 그 규칙을 소유하지 않으므로, Terraform이 독립 규칙 리소스로 정확한 파드/노드 포트를 열어야 합니다.

#### upstream·차트·재사용 모듈·루트 기본값을 구분한다

- 컨트롤러 CLI의 `--enable-backend-security-group` 기본값은 `true`입니다.
- 차트의 `enableBackendSecurityGroup` 기본값은 비어 있으며, 값을 생략하면 CLI 인수를 렌더링하지 않아 upstream의 `true`를 상속합니다.
- 재사용 모듈은 특별한 이유 없이 이 동작을 `false`로 뒤집지 않습니다. 기본 `true`를 유지하거나 nullable 값으로 생략을 표현합니다.
- 루트 변형은 위 표를 보고 명시적으로 선택합니다. Terraform 직접 규칙 패턴이면 `false`, 컨트롤러 관리 패턴이면 `true`를 넘기고 잘못된 조합을 교차 변수 `validation`으로 막습니다.

```hcl
# Reusable module: preserve the controller's upstream behavior.
variable "enable_backend_security_group" {
  type        = bool
  default     = true
  description = "Whether the controller uses its shared backend security group"
}
```

`008_eks_aws_load_balancer_controller`의 `sync_alb`·`sync_nlb`처럼 확인된 변형은 커스텀 프론트엔드 SG, effective manage=false, `enable_backend_security_group = false`, Terraform의 `load_balancer_to_pods` 규칙 조합을 보여줍니다. 반대로 `056_eks_cross_region_velero_dr`에서 확인된 컨트롤러 모듈 사본은 기본 `true`를 유지해 자동 생성 SG 경로를 보여줍니다. 이 이름들은 **예시이지 프로젝트 전체나 미래 inventory에 대한 보증이 아닙니다.** 각 루트의 모듈 인수, 전역 플래그, 렌더된 Ingress/Service 애노테이션, 실제 backend 규칙을 함께 감사해야 하며, 현재 코드가 모두 표와 일치한다고 이 문서만으로 단정하지 않습니다.

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

#### 커스텀 프론트엔드 SG + effective manage=true에서는 끌 수 없다

Ingress/Service에 프론트엔드 보안그룹을 직접 지정하면(`alb.ingress.kubernetes.io/security-groups`, `service.beta.kubernetes.io/aws-load-balancer-security-groups`) 컨트롤러는 기본적으로 노드 측 규칙을 건드리지 않습니다. 이 커스텀 SG 경로에서 effective `manage-backend-security-group-rules = true`로 규칙 관리를 다시 켜면, **`--enable-backend-security-group=false`는 허용되지 않습니다.** 커스텀 SG 자체만으로 금지되는 것이 아니라 두 축의 이 조합이 금지됩니다.

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

- 따라서 끄기 전에는 **프론트엔드 SG의 소유권과 effective manage 값 둘 다** 확인합니다. 소스를 보면 커스텀 프론트엔드 SG는 `if manageBackendSGRules` 밖에서 이미 `lbSGTokens`에 추가되고, 금지 오류는 그 블록 안에만 있습니다. 즉 커스텀 SG를 쓰더라도 effective manage=false이면 `false`가 가능하지만, 그때 backend ingress는 컨트롤러가 아니라 Terraform 같은 외부 소유자의 책임입니다.

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

이 소스의 `manageBackendSGRules`는 앞의 표에서 말한 effective 값입니다. 개별 애노테이션이 전역 `--enable-manage-backend-security-group-rules`보다 우선하며, 커스텀 SG + effective manage=true + backend feature=false에서만 위 오류 분기가 닫힙니다.

#### 커스텀 SG + effective manage=false이면 backend 규칙을 직접 선언한다

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
  for_each = var.load_balancer_ports

  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Load balancer ${each.key} port to pods"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = module.frontend_security_group.security_group_id
}
```

ALB/Ingress와 NLB/Service 모두 이 소유권 규칙의 대상입니다. 리소스 존재를 Service 타입 하나로 제한하지 말고, G-1번의 단일 포트 맵을 Service·프론트엔드 SG·파드 쪽 규칙에 함께 전달합니다.

- **`target-type: instance`에서는 이 방식을 쓸 수 없습니다.** NodePort는 쿠버네티스가 30000-32767에서 임의로 배정하므로 Terraform이 포트를 알 수 없고, 표현 가능한 규칙은 그 범위 전체를 여는 것뿐입니다. 이 조합을 쓰는 변형에서는 `target_type` 변수를 `ip`로 제한하는 `validation`을 걸어 apply 전에 막습니다.
- 이 경로를 택할 때 **`aws-load-balancer-type = "external"`(또는 `spec.loadBalancerClass`)이 붙어 있는지 먼저 확인합니다.** 둘 중 아무것도 없으면 in-tree 클라우드 프로바이더가 Service를 처리해 Classic Load Balancer를 만들고, 프론트엔드 SG 애노테이션과 타깃 타입을 통째로 무시합니다. 컨트롤러가 Service를 아예 reconcile하지 않으므로 위의 모든 이야기가 적용되지 않습니다.
- 기존에 붙어 있는 프론트엔드 SG의 `description`을 손보고 싶어도 참으십시오. 보안그룹은 `description` 변경 시 **교체**되고(F-1번 패턴), 로드밸런서가 그 그룹을 참조하는 동안 AWS는 삭제를 거부하므로 `DependencyViolation`으로 막힙니다. 문구 수정은 API 값이 아니라 주석에서 합니다.

#### 루트가 선택한 소유권 조합은 `validation`으로 고정한다

재사용 모듈의 변수는 upstream 동작을 보존하지만, 루트 변형은 자기 워크로드의 프론트엔드 SG와 effective manage 설정을 알고 있습니다. 커스텀 SG + effective manage=true를 선택한 루트가 `false`를 받을 수 있게 두면 `terraform plan`과 Helm/manifest apply는 통과하고, 컨트롤러 reconcile만 실패해 **로드밸런서와 주소가 생기지 않습니다.** B-1번 패턴대로 그 조합을 plan 단계에서 막습니다.

```hcl
variable "enable_backend_security_group" {
  type    = bool
  default = true

  validation {
    # This root uses a custom frontend security group and sets effective
    # manage-backend-security-group-rules to true.
    condition     = var.enable_backend_security_group
    error_message = "enable_backend_security_group must be true in this variant because its custom frontend security group is paired with manage-backend-security-group-rules=true. To use false, remove that management request and declare every node-side rule in Terraform."
  }
}
```

반대로 커스텀 SG + effective manage=false인 루트는 컨트롤러가 backend ingress를 만들지 않는다는 사실을 고정하고, 필요한 독립 규칙이 포트 맵 전체에 존재하는지 함께 감사합니다. 이 규칙을 빠뜨린 결과는 위 금지 조합과 다릅니다. **로드밸런서와 주소는 생길 수 있지만 타깃이 모두 unhealthy**이고 Terraform 오류는 없을 수 있습니다. `manage-backend-security-group-rules` 자체를 변수로 노출했다면 `enable_backend_security_group`과 외부 규칙 소유권의 조합을 교차 검증하고, 유효한 대안을 오류 메시지에 적습니다.

공유 backend SG를 끄면 계정의 SG 하나를 줄이고 데이터 경로를 프론트엔드 SG 참조로 직접 보이게 할 수 있지만, 로드밸런서마다 노드 SG 규칙이 쌓여 그룹당 규칙 한도에 가까워집니다. 이것이 upstream과 재사용 모듈이 `true`를 보존하고, 직접 규칙을 소유하는 특정 루트만 `false`를 명시적으로 선택해야 하는 이유입니다. 전역 `--enable-manage-backend-security-group-rules`도 effective manage 값에 포함되며, 개별 애노테이션이 그 값을 덮습니다.

### G-3. AWS Load Balancer Controller가 만들 ALB/NLB는 Terraform이 미리 만들고 컨트롤러가 채택(adopt)하게 한다

G-1번 패턴의 기본형에서는 로드밸런서가 Terraform 리소스가 아닙니다. 컨트롤러가 Ingress/Service를 reconcile하면서 만들기 때문에 ARN도 DNS 이름도 `terraform plan`에 없고, `apply`가 끝난 뒤 클러스터를 조회해야 비로소 알 수 있습니다.

이 패턴은 그 순서를 뒤집습니다. **`aws_lb`를 Terraform이 먼저 만들고, 컨트롤러가 자기 소유물에 붙이는 태그를 그 로드밸런서에 미리 심어둡니다.** 그러면 컨트롤러가 Ingress/Service를 reconcile할 때 Resource Groups Tagging API로 자기 스택의 리소스를 찾다가 이 로드밸런서를 발견하고, 새로 만드는 대신 **그것을 채택해서** 리스너와 타깃그룹을 붙입니다. 리스너·타깃그룹·타깃 등록은 계속 컨트롤러의 일이고, 로드밸런서 껍데기만 Terraform이 소유합니다.

`008_eks_aws_load_balancer_controller`의 `sync_alb`(Ingress→ALB)와 `sync_nlb`(Service→NLB)가 이 패턴이며, 두 변형 모두 `modules/synced_load_balancer` 하나로 양쪽 모양을 덮습니다.

#### 이 패턴을 쓰는 이유

- **주소를 Terraform이 안다.** ARN·DNS 이름·`zone_id`가 state에 있으므로 output으로 낼 수 있고, Route 53 alias 레코드나 CloudFront origin처럼 로드밸런서를 참조하는 다른 Terraform 리소스를 같은 `apply` 안에서 만들 수 있습니다. 컨트롤러가 만든 로드밸런서로는 이것이 불가능합니다.
- **구성이 plan에 보인다.** 서브넷, 보안그룹, scheme이 애노테이션 문자열이 아니라 리소스 속성으로 리뷰됩니다.
- **NLB의 보안그룹은 생성 시점에만 붙일 수 있다.** AWS 문서가 명시하는 제약입니다 — 보안그룹 없이 만들어진 NLB에는 나중에 붙일 수 없고(`SetSecurityGroups`가 거부), 그래서 `sync_nlb`처럼 프론트엔드 보안그룹을 Terraform이 통제해야 하는 구성에서는 로드밸런서를 미리 만드는 것이 가장 확실한 방법입니다.

#### 태그 3개는 필요한 식별자이지만 충분조건은 아니다

세 태그는 컨트롤러가 특정 stack의 후보 로드밸런서를 찾는 **필수 discovery key**입니다. 모두 맞아도 타입·scheme·서브넷 같은 생성 시 속성이 컨트롤러 모델과 호환되지 않거나 후보가 첫 reconcile 전에 존재하지 않으면 채택되지 않습니다.

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

  # Caller tags are merged first so the controller's reserved discovery keys
  # always win even if a caller repeats one. Validation below rejects repeats
  # as a clearer plan-time error.
  tags = merge(var.additional_tags, local.controller_tags)

  lifecycle {
    # These inputs are honored when aws_lb is created, then treated as a
    # create-time contract because the controller can mutate them after adoption.
    # Listeners and target groups are separate controller-owned resources and are
    # deliberately not declared by Terraform.
    ignore_changes = [security_groups, subnets, tags, tags_all]
  }
}

variable "additional_tags" {
  type    = map(string)
  default = {}

  validation {
    condition = alltrue([for key in keys(var.additional_tags) : !contains([
      "elbv2.k8s.aws/cluster",
      "${var.resource_tag_prefix}.k8s.aws/resource",
      "${var.resource_tag_prefix}.k8s.aws/stack",
    ], key)])
    error_message = "additional_tags must not set the controller-reserved cluster, resource, or stack tag keys. Set their dedicated module inputs instead."
  }
}
```

필수 태그는 호출자 태그보다 개념적으로 우선해야 합니다. `merge(var.additional_tags, local.controller_tags)`가 그 우선순위를 구현하고, validation은 충돌을 조용히 덮는 대신 plan에서 설명합니다. 기존 모듈이 반대 순서로 merge한다면 문서와 일치한다고 가정하지 말고 감사·교정합니다.

| 태그 | 값 | Ingress(ALB) | Service(NLB) |
| --- | --- | --- | --- |
| `elbv2.k8s.aws/cluster` | 클러스터 이름 | 동일 | 동일 |
| `<prefix>.k8s.aws/resource` | `LoadBalancer` (리터럴) | `ingress.k8s.aws/resource` | `service.k8s.aws/resource` |
| `<prefix>.k8s.aws/stack` | `<namespace>/<이름>` | `ingress.k8s.aws/stack` | `service.k8s.aws/stack` |

- **접두사를 틀리는 것이 가장 흔한 실수입니다.** Service에서 오는 NLB에 `ingress.k8s.aws/*`를 붙이면 채택되지 않습니다(업스트림 [#3576](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/3576)이 정확히 이 사례). G-1번 패턴의 애노테이션 접두사 표와 같은 종류의 함정이며, 마찬가지로 **오류가 아니라 무시**됩니다.
- `resource` 태그의 값은 `LoadBalancer` 고정입니다. 컨트롤러 모델에서 로드밸런서의 리소스 ID가 그 문자열이고, 타깃그룹은 `<svc>/<port>` 같은 다른 값을 받습니다. 타깃그룹은 Terraform이 만들지 않으므로 이 값은 항상 `LoadBalancer`입니다.

#### `stack` identity를 한 곳에서 파생하고 workload가 pre-created LB를 기다린다

`stack`은 보통 `<namespace>/<Ingress 또는 Service 이름>`이고, 명시적 `alb.ingress.kubernetes.io/group.name`이 있으면 그룹 이름 하나입니다. 이 값을 루트에 서로 다른 리터럴로 다시 적으면 조용히 어긋나지만, 해결책으로 **리소스를 만드는 workload 모듈의 output을 LB 모듈 입력으로 연결해서는 안 됩니다.** 그 참조는 LB를 workload 뒤에 두거나 최소한 workload가 LB를 기다리는 간선을 만들지 못해, 첫 reconcile이 먼저 두 번째 LB를 만들 수 있습니다. HCL 블록의 소스 순서와 이름만 계산하는 output도 pre-creation을 보장하지 않습니다.

이름 계약을 root local 또는 공통 입력 한 곳에서 파생해 두 모듈에 넘기고, workload 모듈에 pre-created LB를 향한 명시적 `depends_on`을 둡니다. 차트가 이름을 만들면 아래 절처럼 `fullnameOverride`로 계약을 고정합니다.

```hcl
locals {
  workload_object_name = var.create_ingress ? var.ingress_name : var.service_name
  workload_stack       = var.ingress_group_name != null ? var.ingress_group_name : "${var.namespace}/${local.workload_object_name}"
}

module "synced_alb" {
  source = "./modules/synced_load_balancer"

  cluster_name        = module.eks_cluster.cluster_name
  resource_tag_prefix = "ingress"
  stack               = local.workload_stack
  subnet_ids          = module.network.public_subnet_ids
  security_group_ids  = [module.alb_security_group.security_group_id]

  depends_on = [module.network]
}

module "game_2048" {
  source = "./modules/game_2048"

  namespace    = var.namespace
  ingress_name = var.ingress_name
  # The pre-created LB must exist before this module creates the Ingress.
  depends_on = [
    module.network,
    module.eks_node_group,
    module.aws_load_balancer_controller,
    module.synced_alb,
  ]
}
```

필요한 그래프는 `network/SG → pre-created LB`와 `cluster → add-ons/nodes → controller`가 병렬로 진행된 뒤, **`{pre-created LB, controller, 필요한 노드} → workload`**로 합쳐지는 형태입니다. 기존 sync 변형이 workload output을 LB 입력으로 쓰거나 이 역방향 간선이 없다면 현재 코드가 이미 안전하다고 주장하지 말고 순환 없이 공통 identity로 옮기는 remediation을 계획합니다.

- **`alb.ingress.kubernetes.io/group.name`을 쓰면 `stack` 값이 달라집니다.** 명시적 IngressGroup의 스택 ID는 `<namespace>/<name>`이 아니라 그룹 이름 하나입니다. 기존 Ingress에 이 애노테이션을 추가하면 컨트롤러가 로드밸런서를 새로 만드는 이유가 이것입니다(업스트림 [#2271](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2271)). 같은 root identity를 태그와 애노테이션 양쪽에 전달하고 렌더 결과로 확인합니다.

#### 이름 부분은 차트의 naming 템플릿에서 유도한다 (릴리스 이름에 차트 이름을 붙여 쓰지 않는다)

`stack`의 뒷부분은 Service나 Ingress의 이름이고, 그 오브젝트를 차트가 만든다면 **이름을 정하는 것도 차트입니다.** 릴리스 이름 뒤에 차트 이름을 붙이는 식으로 짐작하면 틀립니다. `ingress-nginx`의 `_helpers.tpl`이 그 예입니다.

```gotemplate
{{- define "ingress-nginx.fullname" -}}
{{- if .Values.fullnameOverride -}}{{- .Values.fullnameOverride -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}{{- .Release.Name -}}
{{- else -}}{{- printf "%s-%s" .Release.Name $name -}}
```

릴리스 이름이 차트 이름을 **포함하면 중복이 접힙니다.** 그래서 같은 규칙이 릴리스 이름에 따라 다른 답을 냅니다.

| 릴리스 이름 | 컨트롤러 Service 이름 |
| --- | --- |
| `ingress-nginx` | `ingress-nginx-controller` |
| `foo` | `foo-ingress-nginx-controller` |

`"${release}-ingress-nginx-controller"`로 적어두면 기본 릴리스 이름에서 `ingress-nginx-ingress-nginx-controller`가 됩니다. 그런 Service는 존재하지 않으므로 태그는 아무것과도 매칭되지 않고, **컨트롤러는 자기 로드밸런서를 따로 만듭니다.** 미리 만든 쪽에는 리스너가 하나도 붙지 않는데 하필 output과 워크로드의 hostname이 가리키는 것이 그쪽이어서, 증상은 "apply는 성공했는데 주소가 아무 응답도 하지 않는다"가 됩니다.

`contains` 판정을 Terraform에서 재현하지 않습니다. **`fullnameOverride`로 이름을 고정하면** 추론이 사라지고 Service 이름이 릴리스 이름의 순수 함수가 됩니다. 기본 릴리스 이름에서는 결과가 같으므로 기존 리소스가 개명되지도 않습니다.

```hcl
# 차트를 설치하는 모듈
set = concat([
  {
    name  = "fullnameOverride"
    value = var.release_name
    # 전부 숫자인 릴리스 이름은 number로 추론되어 차트의 trunc가 렌더에 실패합니다 (E-7번).
    type = "string"
  },
  ...
```

```hcl
# 루트 - 짐작이 아니라 규칙입니다
ingress_service_name = "${var.ingress_release_name}-controller"
ingress_stack_tag    = "${var.ingress_namespace}/${local.ingress_service_name}"
```

그리고 호출자가 넘긴 이름이 릴리스 이름과 어긋나는 것을 `validation`으로 세웁니다. 이 어긋남은 아무 에러도 내지 않으므로, plan에서 잡지 않으면 드러나는 곳이 "로드밸런서가 2개"뿐입니다(B-1번).

```hcl
variable "service_name" {
  # 조합에 관한 제약이므로 교차 참조가 맞는 표현입니다
  validation {
    condition     = var.service_name == "${var.release_name}-controller"
    error_message = "service_name must be \"<release_name>-controller\" - the chart names the controller Service after its fullname, which this release pins to release_name via fullnameOverride. Passing anything else silently breaks load balancer adoption rather than failing (rules.md G-3)."
  }
}
```

- **`ingress-nginx`에 한정된 이야기가 아닙니다.** 차트가 만드는 오브젝트의 이름을 Terraform 쪽에서 맞춰야 할 때는 이름을 짐작하지 말고 렌더해서 확인합니다.

```bash
helm template <release> <repo>/<chart> --version <v> --kube-version 1.33.0 \
  | grep -E '^kind:|^  name:' | paste - - | grep Service
```

#### 태그 외에 반드시 일치해야 하는 것

태그가 맞아 채택 대상이 되더라도, 컨트롤러가 계산한 로드밸런서 명세와 실제 로드밸런서가 **재생성 없이는 맞출 수 없는 항목**에서 어긋나면 채택이 성립하지 않습니다.

| 항목 | Terraform | 워크로드 쪽 |
| --- | --- | --- |
| 타입 | `load_balancer_type = "application" \| "network"` | Ingress(ALB) / `type: LoadBalancer` Service(NLB) |
| scheme | `internal = false \| true` | `scheme` 애노테이션(`internet-facing` / `internal`) |
| 서브넷 | `subnet_ids` | `scheme`이 요구하는 쪽(public / private) + G-1번 패턴의 서브넷 태그 |

- `internal`과 `scheme`이 어긋나는 것은 에러가 아니라 **두 번째 로드밸런서**입니다. 이 패턴의 실패는 거의 전부 이 모양으로 나타납니다.
- AWS의 최소조건은 타입별로 다릅니다. ALB는 최소 2개 AZ가 필요하지만 NLB는 단일 AZ/subnet도 지원합니다. 다만 이 저장소의 공용 `synced_load_balancer` 모듈은 두 타입 모두에 **최소 2개 AZ를 사용하는 HA 정책**을 적용하고, 채택 후 `subnets`를 `ignore_changes`로 취급하므로 최초 생성 입력이 계약이 됩니다. 아래 변수 검증은 서로 다른 subnet ID가 두 개 이상이고 형식이 유효한지까지만 확인하며, ID 문자열만으로 AZ를 판정할 수는 없습니다. 호출자는 C-3번의 topology-known network output처럼 서로 다른 최소 2개 AZ를 보장하는 목록을 넘깁니다. 단일 AZ NLB가 꼭 필요하면 이 공용 계약을 조용히 약화하지 말고, 별도 변형에서 가용성 차이와 검증을 명시합니다. 임의의 subnet ID를 허용하는 인터페이스라면 plan-known zone key의 map을 사용하거나 루트에서 `data.aws_subnet`과 blocking precondition으로 실제 `availability_zone` 집합을 별도 검증합니다.

```hcl
variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the load balancer; this module's HA policy requires distinct IDs spanning at least two availability zones"

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least two distinct, syntactically valid subnet IDs. This module's HA policy also requires the caller to ensure those subnets span at least two availability zones."
  }
}
```

#### 이름은 비워둔다 (`name = null` + `name_prefix`)

후보 discovery는 이름이 아니라 필수 태그로 이루어지므로 로드밸런서 이름은 채택 식별자로 쓰지 않습니다. 그러나 태그만으로 충분하다는 뜻은 아니며 타입·scheme·서브넷과 생성 순서도 함께 맞아야 합니다. 반대로 이름을 고정하면 **채택 조건이 어긋났을 때의 실패 모양이 나빠집니다.** 워크로드에도 `aws-load-balancer-name` 애노테이션이 있고 그 이름이 같다면, 채택에 실패한 컨트롤러가 같은 이름으로 새 로드밸런서를 만들려다 AWS에게 거부당합니다.

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

#### 리스너·타깃그룹은 Terraform이 선언하지 않고, ignored 입력은 생성 시 계약이다

`aws_lb`만 만들고 `aws_lb_listener`/`aws_lb_target_group`/`aws_lb_listener_rule`은 **선언하지 않습니다.** 리스너·타깃그룹·타깃 등록은 `aws_lb`의 ignored attribute가 아니라 별도의 컨트롤러 소유 리소스입니다. Terraform이 같은 것을 선언하면 두 소유자가 싸웁니다.

```hcl
lifecycle {
  ignore_changes = [security_groups, subnets, tags, tags_all]
}
```

이 넓은 `ignore_changes`는 controller drift만 숨기는 편의 설정이 아니라 **create-time-only 계약**을 만듭니다.

- `security_groups`와 `subnets` 입력은 최초 생성에는 적용되지만 이후 변수를 바꿔도 plan이 기존 LB를 교정하지 않습니다.
- `tags`와 `tags_all`을 무시하면 컨트롤러가 추가한 태그를 Terraform이 지우지 않는 대신, 필수 discovery tag나 `additional_tags`의 이후 변경도 plan에 나타나지 않습니다.
- 따라서 잘못된 stack/prefix/cluster 태그나 생성 시 SG·서브넷을 고치려면 변수만 바꾸지 말고, 관찰된 AWS 값을 확인한 뒤 별도의 replacement/마이그레이션을 계획해야 합니다. populated LB의 교체와 컨트롤러 수명주기 영향은 plan과 격리 리허설로 확인합니다.

기존 sync 모듈이 이 목록을 사용한다는 사실만으로 안전하다고 보지 않습니다. 생성 시 입력과 현재 AWS 속성이 일치하는지 감사하고, 불일치는 `ignore_changes` 아래에서 자동 복구되지 않는 remediation 항목으로 기록합니다. NLB를 SG 없이 만든 뒤에는 나중에 SG를 붙일 수 없다는 다음 절의 AWS 제약은 이 Terraform create-time 계약보다 더 강한 별도 제약입니다.

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

확인된 `sync_alb`/`sync_nlb` 구성은 G-2 표의 커스텀 SG + effective manage=false 경로를 의도해 Terraform이 노드/파드 측 규칙을 선언합니다. 이는 두 변형의 감사 결과일 뿐 다른 sync 구성의 보증이 아니며, 실제 포트·target type·규칙 소유권을 각 stack에서 다시 대조합니다. `target-type: ip`인 단일 포트 workload라면 다음처럼 한 규칙으로 덮을 수 있습니다.

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

#### configured input과 관찰된 채택 결과를 따로 출력한다

이 패턴에서는 Terraform이 소유한 `aws_lb`의 ARN·DNS 이름을 output으로 낼 수 있습니다. 그러나 그 값이 있다는 사실은 컨트롤러가 그 LB를 채택했다는 증거가 아닙니다. `value = var.stack`도 **요청한 input**을 되돌릴 뿐, AWS에 현재 저장된 태그를 관찰하지 않습니다. merge 우선순위 오류, 생성 이후 drift, `ignore_changes` 아래의 오래된 태그를 발견할 수 없습니다.

H-2번의 output/README에는 최소한 다음 세 정체성을 나란히 둡니다.

1. Terraform이 만든 LB의 ARN/DNS와 **configured/requested stack**.
2. 그 ARN을 `aws elbv2 describe-tags`로 조회하는 명령과 실제 reserved tag 세 개.
3. Ingress/Service의 `status.loadBalancer` hostname을 조회하는 명령.

```hcl
locals {
  outputs = {
    precreated_load_balancer_arn = {
      order       = 6
      title       = "Pre-created load balancer ARN"
      description = "ARN of the Terraform-owned candidate; this alone does not prove adoption"
      value       = module.synced_alb.arn
    }
    configured_stack = {
      order       = 7
      title       = "Configured adoption stack"
      description = "Requested stack identity, not an observation of the current AWS tag"
      value       = module.synced_alb.requested_stack
    }
    observed_tags_command = {
      order       = 8
      title       = "Read tags on the pre-created load balancer"
      description = "Verify the cluster, resource and stack tags actually stored on this ARN"
      value       = "aws elbv2 describe-tags --resource-arns ${module.synced_alb.arn}"
    }
    ingress_endpoint_command = {
      order       = 9
      title       = "Read the controller-observed ALB DNS name"
      description = "Compare this hostname with the Terraform-owned load balancer DNS name"
      value       = module.game_2048.load_balancer_hostname_command
    }
  }
}
```

```hcl
# modules/synced_load_balancer/outputs.tf
output "requested_stack" {
  value       = var.stack
  description = "Stack identity requested at create time; use describe-tags to observe the current AWS tag"
}
```

채택 검증은 세 값이 같은 stack을 가리키는지 확인해야 끝납니다. Terraform ARN의 실제 reserved tag가 configured identity와 같고, Kubernetes status hostname이 그 ARN의 DNS와 같아야 합니다. 기존 `stack = var.stack` output을 observed tag라고 설명하는 구성은 감사·이름 변경 대상이지, 현재 적합성의 증거가 아닙니다.

#### 채택 후 수명주기는 컨트롤러와 공유된다

채택된 로드밸런서는 컨트롤러의 스택에 속하므로, **Ingress/Service가 사라지면 컨트롤러가 그 로드밸런서를 지웁니다.** 자기가 만들지 않았어도 마찬가지입니다(업스트림 [#2493](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2493): "Controller deletes an ALB it didn't create when there are no ingresses left"). 결과적으로:

- `terraform destroy`에서 워크로드 매니페스트가 먼저 지워지면(D-4번 패턴의 순서) 컨트롤러가 로드밸런서를 먼저 삭제하고, Terraform의 `aws_lb` 삭제는 이미 없는 리소스를 지우는 것이 됩니다. 이 순서 자체는 문제가 아니지만, 미리 만든 로드밸런서가 Terraform만의 소유물이 아니라는 뜻입니다.
- 워크로드만 지우고(`kubectl delete ingress`) 인프라를 남겨두면 다음 `terraform plan`이 로드밸런서를 다시 만들자고 제안합니다. 이는 drift가 아니라 이 패턴의 정상적인 결과입니다.
- 따라서 이 로드밸런서를 참조하는 Route 53 레코드처럼 **로드밸런서보다 오래 살아야 하는 리소스**를 붙일 때는, 워크로드를 지우면 그 참조가 끊어진다는 점을 전제로 설계합니다. `enable_deletion_protection`은 이 상황을 막아주지 못합니다(컨트롤러의 삭제는 막지만, 그러면 컨트롤러가 에러 루프에 빠집니다). 데모 구성에서는 `false`로 둡니다.

#### 필수 의존 그래프

```
network/SG ───────────────→ pre-created load balancer ─┐
cluster → add-ons/nodes → controller ──────────────────┼→ workload Ingress/Service
required nodes ────────────────────────────────────────┘
```

- HCL 블록을 위에 적거나 이름만 담은 output을 참조하는 것으로는 이 간선이 생기지 않습니다.
- `synced_load_balancer`는 network와 프론트엔드 SG만 기다리면 되고, 컨트롤러나 노드그룹을 기다릴 필요는 없습니다.
- workload 모듈은 컨트롤러·실제 노드 리소스뿐 아니라 `module.synced_load_balancer`를 명시적으로 기다립니다. 그러면 destroy는 역순으로 workload를 먼저 지워 컨트롤러가 정리할 시간을 줍니다(D-4).
- 이 간선을 추가할 때 workload output을 LB input으로 받던 역방향 참조가 있으면 순환이 생깁니다. 앞 절의 공통 root identity로 그 참조를 먼저 끊습니다.

기존 sync 변형은 이 도달 관계를 정적으로 감사하고 실제 apply에서 같은 stack의 후보가 workload보다 먼저 생성되는지 확인합니다. 문서의 원하는 그래프를 현재 코드가 이미 만족한다고 가정하지 않습니다.

#### stack 단위 진단

클러스터 전체의 로드밸런서 수를 세지 않습니다. 클러스터에는 여러 정상 stack이 있을 수 있으므로, **cluster + 정확한 prefix의 resource + stack** 세 태그로 후보를 좁힙니다.

```bash
# Ingress/ALB. IngressGroup이면 STACK은 namespace/name이 아니라 group.name입니다.
CLUSTER=<cluster>
PREFIX=ingress
STACK=<namespace>/<ingress-name>
aws resourcegroupstaggingapi get-resources \
  --tag-filters \
    "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
    "Key=${PREFIX}.k8s.aws/resource,Values=LoadBalancer" \
    "Key=${PREFIX}.k8s.aws/stack,Values=$STACK" \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --query 'ResourceTagMappingList[].ResourceARN' --output table

# Service/NLB uses the Service prefix and Service identity.
PREFIX=service
STACK=<namespace>/<service-name>
aws resourcegroupstaggingapi get-resources \
  --tag-filters \
    "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
    "Key=${PREFIX}.k8s.aws/resource,Values=LoadBalancer" \
    "Key=${PREFIX}.k8s.aws/stack,Values=$STACK" \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
```

reconcile이 끝난 뒤에는 **그 stack에 ARN 하나**가 있어야 하고, 그 ARN이 Terraform의 pre-created ARN과 같아야 합니다. 0개면 아직 reconcile되지 않았을 수 있으므로 곧바로 채택 실패로 단정하지 말고 object event와 controller log를 봅니다. 같은 stack에 2개면 duplicate/adoption 실패입니다.

```bash
TF_ARN="$(terraform output -raw precreated_load_balancer_arn)"
aws elbv2 describe-tags --resource-arns "$TF_ARN" \
  --query 'TagDescriptions[0].Tags[?Key==`elbv2.k8s.aws/cluster` || Key==`ingress.k8s.aws/resource` || Key==`ingress.k8s.aws/stack`]'
aws elbv2 describe-load-balancers --load-balancer-arns "$TF_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text

# Ingress stack
kubectl -n <namespace> get ingress <name> \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Service stack
kubectl -n <namespace> get service <name> \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

ARN이나 hostname이 다르면 순서대로 (1) prefix, (2) 실제 AWS stack/resource/cluster 태그, (3) `group.name`, (4) 타입·scheme·서브넷, (5) workload가 pre-created LB를 기다리는 그래프 간선을 확인합니다. `A load balancer with the same name ... exists, but with different settings`는 이름 자체가 아니라 이 조건 중 하나가 어긋난 상태에서 이름까지 충돌했다는 기존 incident evidence입니다.

```bash
kubectl -n <namespace> describe ingress <name>   # Service stack이면 describe service
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail 100
```

### G-4. Service mutator는 Ready endpoint가 없을 때 Service CREATE를 막는다 — 명시적 controller selection을 기본 정책으로 한다

`aws-load-balancer-controller` 차트는 Service를 가로채는 mutating 웹훅을 기본으로 설치합니다. 하는 일은 하나입니다 — `type: LoadBalancer` Service에 `spec.loadBalancerClass`를 주입해서 이 컨트롤러가 기본 처리자가 되게 하는 것. 그런데 **그 대상 범위가 클러스터 전체입니다.**

```yaml
failurePolicy: Fail
name: mservice.elbv2.k8s.aws
rules:
- apiGroups: [""]
  apiVersions: [v1]
  operations: [CREATE]
  resources: [services]
```

`namespaceSelector`가 아예 없고, `objectSelector`의 유일한 제외 조건은 컨트롤러 자신의 `app.kubernetes.io/name` 라벨입니다(차트가 자기 Service에서 교착되지 않으려고 넣은 것). 따라서 MutatingWebhookConfiguration이 활성화된 상태에서 `aws-load-balancer-webhook-service`에 **Ready endpoint가 하나도 없고 새 Service CREATE가 겹치면**, 어느 네임스페이스에서든 그 CREATE가 실패합니다. 규칙의 operation이 `CREATE`이므로 이미 존재하는 Service가 endpoint 공백만으로 중단되는 것은 아닙니다.

```
Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws": failed to call webhook:
Post "https://aws-load-balancer-webhook-service.kube-system.svc:443/mutate-v1-service?timeout=10s":
no endpoints available for service "aws-load-balancer-webhook-service"
```

이 위험 구간은 초기 설치에서 웹훅 구성이 등록된 뒤 Deployment가 Available이 되기 전 발생하기 쉽고, 이후 롤아웃·장애·노드 교체가 모든 Ready endpoint를 없앨 때 재발할 수 있습니다. 그러나 준비된 기존 replica가 계속 서비스하는 평범한 no-op apply마다 반드시 구간이 열린다고 말해서는 안 됩니다. **zero-ready endpoint 구간과 새 Service CREATE가 동시에 일어날 때** 다른 차트가 실패하며, 에러는 그 차트가 아니라 이 웹훅의 이름을 답니다 — 원인에서 한참 먼 곳을 가리킵니다.

#### 원하는 정책과 현재 inventory를 구분한다

이 저장소의 **정책**은 모든 `type: LoadBalancer` Service가 `service.beta.kubernetes.io/aws-load-balancer-type: "external"` 또는 `spec.loadBalancerClass: service.k8s.aws/nlb`로 처리자를 명시하는 것입니다. 그 계약을 만족하는 루트는 `enableServiceMutatorWebhook = false`를 명시해 cluster-wide mutator를 끕니다. 반대로 mutator의 자동 주입에 의도적으로 의존하는 루트라면 `true`를 명시하고 zero-ready endpoint 동안 Service CREATE가 fail-closed된다는 가용성 비용을 받아들입니다.

"현재 그런 Service가 없다"거나 특정 grep 결과가 0이라는 것은 시점별 inventory일 뿐 정책의 근거가 아닙니다. 끄기 전에는 Terraform 리터럴뿐 아니라 computed annotation key와 Helm이 렌더하는 Service까지 감사합니다. 처리자 표식이 없는 LoadBalancer Service를 발견하면 mutator를 계속 켜서 우연에 의존하지 말고 표식부터 추가합니다. 그렇지 않으면 in-tree cloud provider가 Classic Load Balancer를 만들고 프론트엔드 SG·target type 애노테이션을 무시할 수 있습니다(G-1). 현재 코드가 이 정책을 모두 만족한다고 문서가 보증하지 않으며, 아래 감사 결과로 위반을 찾아 remediation합니다.

#### bool로 렌더링되어야 한다

차트의 가드가 `{{- if .Values.enableServiceMutatorWebhook }}`로 **단순 truthiness**입니다. Go 템플릿에서 비어 있지 않은 문자열은 참이므로, 문자열 `"false"`는 웹훅을 **그대로 남기면서** 끈 것처럼 보입니다. `type = "string"`을 붙이지 않습니다(E-7번).

```hcl
{
  name  = "enableServiceMutatorWebhook"
  value = tostring(var.enable_service_mutator_webhook)
  # type을 지정하지 않습니다 - auto 추론이 bool을 만들어야 합니다
},
```

```bash
if helm template alb eks/aws-load-balancer-controller \
  --set clusterName=x \
  --set enableServiceMutatorWebhook=false \
  | grep -q 'name: mservice.elbv2.k8s.aws'; then
  echo 'Service mutator is still rendered' >&2
  exit 1
fi
# --set-string enableServiceMutatorWebhook=false였다면 이름이 발견되어 실패합니다.
```

#### 재사용 모듈은 차트를 따르고, 루트가 정책을 명시한다

재사용 모듈은 호출자의 Service inventory를 볼 수 없으므로 차트 기본값인 `true`를 보존합니다. 루트는 생략하지 않습니다. 모든 LoadBalancer Service가 처리자를 명시한다는 감사를 통과한 변형은 `false`를 넘기고 false로 고정하며, mutator에 의도적으로 의존하는 변형은 `true`를 넘기고 그 위험을 문서화합니다. 어떤 값도 저장소 전체의 보편적 root 기본값으로 선언하지 않습니다(B-1).

```hcl
# 루트 variables.tf
variable "enable_service_mutator_webhook" {
  type    = bool
  default = false

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant because every LoadBalancer Service must explicitly select the AWS Load Balancer Controller. To rely on automatic loadBalancerClass injection instead, use a variant that explicitly sets this true and documents the cluster-wide fail-closed Service CREATE risk while the webhook has no Ready endpoint (rules.md G-4)."
  }
}
```

#### `depends_on`은 정책 대체물이 아니다

Service를 만드는 모듈을 `module.aws_load_balancer_controller` 뒤에 두면 초기 apply의 동시 CREATE 경합은 줄일 수 있습니다. 그러나 이것을 mutator 정책의 해결책으로 쓰지 않습니다.

- 컨트롤러가 나중에 롤아웃·장애·노드 교체로 zero-ready가 되거나 사람이 새 Service를 만들 때는 그 Terraform 간선이 아무 보호도 하지 않습니다.
- 관계없는 모듈까지 직렬화하고, 다른 이유로 우연히 생긴 전이 의존성이 없어질 때 문제가 돌아옵니다.
- 따라서 명시적 controller selection 또는 의도적 mutator opt-in이 지속 가능한 결정이고, `depends_on`은 실제 runtime 선행조건에만 둡니다.

Ingress를 만드는 모듈은 `vingress`/`mingress` 웹훅과 reconcile을 위해 계속 컨트롤러 뒤에 둡니다(G-1). 이 규칙이 제거하려는 것은 Service CREATE 전체에 걸린 불필요한 fail-closed 게이트이지, Ingress의 실제 의존 순서가 아닙니다.

#### 남는 웹훅

끈 뒤에도 컨트롤러의 나머지 웹훅은 그대로입니다. Ingress reconcile에는 영향이 없습니다.

| 웹훅 | 대상 | `failurePolicy` |
| --- | --- | --- |
| `mpod.elbv2.k8s.aws` | pods | `Ignore`, 그리고 `elbv2.k8s.aws/pod-readiness-gate-inject=enabled` 네임스페이스 한정 |
| `mservice.elbv2.k8s.aws` | **services (전체)** | `Fail` → 이 규칙이 끄는 대상 |
| `mtargetgroupbinding` / `vtargetgroupbinding` | targetgroupbindings | `Fail` |
| `mingress` / `vingress` | ingresses | `Fail` |

#### 확인하는 방법

먼저 **모든 루트 module call이 정책 값을 명시하는지** 확인합니다. 문자열이 존재하는 곳만 찾는 grep은 생략된 호출을 보여주지 못하므로 block 단위로 열거합니다.

```bash
python - <<'PY'
import pathlib, re

for tf in pathlib.Path('.').rglob('main.tf'):
    if {'_monolithic', '.terraform', 'modules'} & set(tf.parts):
        continue
    text = tf.read_text(encoding='utf-8')
    for match in re.finditer(r'^module "([^"]+)" \{$', text, re.M):
        depth, i = 1, match.end()
        while depth and i < len(text):
            depth += (text[i] == '{') - (text[i] == '}')
            i += 1
        body = text[match.end():i]
        source = re.search(r'source\s*=\s*"([^"]+)"', body)
        if not source or not source.group(1).rstrip('/').endswith('/aws_load_balancer_controller'):
            continue
        if not re.search(r'^\s*enable_service_mutator_webhook\s*=', body, re.M):
            print(f'OMITTED root setting: {tf.parent} module.{match.group(1)}')
PY
```

그 다음 각 모듈 사본이 root 값을 Helm에 실제로 전달하는지 확인합니다. 결과가 없다는 사실만으로 올바른 bool 렌더링까지 증명되지는 않으므로, 앞의 `helm template` 부재 assertion도 실행합니다.

```bash
python - <<'PY'
import pathlib, re

for tf in pathlib.Path('.').rglob('modules/aws_load_balancer_controller/main.tf'):
    if {'_monolithic', '.terraform'} & set(tf.parts):
        continue
    text = tf.read_text(encoding='utf-8')
    entry = re.search(
        r'\{[^{}]*name\s*=\s*"enableServiceMutatorWebhook"[^{}]*\}',
        text,
        re.S,
    )
    if not entry:
        print(f'OMITTED Helm setting: {tf}')
    elif 'tostring(var.enable_service_mutator_webhook)' not in entry.group(0):
        print(f'CHECK Helm value wiring: {tf}')
    elif re.search(r'^\s*type\s*=\s*"string"', entry.group(0), re.M):
        print(f'WRONG string type: {tf}')
PY
```

마지막으로 LoadBalancer Service inventory를 정적 HCL 문자열만으로 판정하지 않습니다. 각 Helm 릴리스는 핀한 버전과 실제 `set` 값으로 렌더해 `spec.type: LoadBalancer`인 Service마다 external 애노테이션 또는 `loadBalancerClass`가 있는지 확인하고, live cluster도 함께 조회합니다. computed annotation key는 렌더 결과에서만 확정됩니다.

```bash
kubectl get service -A -o json | jq -r '
  .items[]
  | select(.spec.type == "LoadBalancer")
  | [.metadata.namespace, .metadata.name,
     (.metadata.annotations["service.beta.kubernetes.io/aws-load-balancer-type"] // "<none>"),
     (.spec.loadBalancerClass // "<none>")]
  | @tsv'

kubectl get mutatingwebhookconfiguration aws-load-balancer-webhook \
  -o jsonpath='{range .webhooks[*]}{.name}{"  "}{.failurePolicy}{"\n"}{end}'
```

false 정책인데 `mservice.elbv2.k8s.aws`가 남아 있거나 LoadBalancer Service에 두 처리자 표식이 모두 없으면 감사 실패입니다. 실패한 Helm 릴리스의 실제 원인은 Terraform state가 아니라 릴리스 히스토리에서 확인합니다(E-7).

```bash
helm history <release> -n <namespace>   # STATUS=failed, DESCRIPTION에 웹훅 이름이 그대로 나옵니다
```
