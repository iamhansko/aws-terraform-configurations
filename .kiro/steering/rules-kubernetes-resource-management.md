---
inclusion: always
---

# Kubernetes Resource Management Rules

> **Index:** [`rules-common-guidelines.md`](rules-common-guidelines.md) · **Previous:** [`rules-resource-ordering-and-destruction.md`](rules-resource-ordering-and-destruction.md) · **Next:** [`rules-security-groups.md`](rules-security-groups.md)
> 논리 인용 `rules.md E-N`은 이 파트의 규칙을 가리킵니다.

## 빠른 참조

| 규칙 | 적용 조건 | 핵심 결정 | 관계 |
| --- | --- | --- | --- |
| E-1 | 실행기가 API 서버에 도달하고 클러스터 내부 객체를 관리 | `alekc/kubectl`의 `kubectl_manifest`와 `hashicorp/helm`의 `helm_release` 사용 | E-2·E-9 |
| E-2 | 새 EKS 클러스터와 Kubernetes 객체를 한 번의 apply로 생성 | `lazy_load = true`인 `alekc/kubectl` 사용 | E-1·E-3 |
| E-3 | CRD가 정의한 커스텀 리소스(CR)를 선언 | HCL 객체를 `yamlencode`한 `kubectl_manifest` 사용 | E-2·D-4 |
| E-4 | 기존 Deployment가 Fargate profile보다 먼저 존재하는 레거시·마이그레이션 | pod template annotation patch로 1회 rollout | E-2·E-8 |
| E-5 | EKS 관리형 Add-on 값을 설정 | Add-on 스키마 타입에 맞춘 `configuration_values` 사용 | C-4·E-7과 타입 규칙 구분 |
| E-6 | AWS 서비스 principal에 EKS 접근을 부여 | 서비스 연결 역할 여부에 따라 Access Entry 또는 `aws-auth` 선택 | C-1·E-2 |
| E-7 | Helm `set`에 annotation·label 또는 bool/number 전달 | entry별 `type`으로 렌더 타입 통제 | G-2·G-4 |
| E-8 | 컨트롤러가 매니페스트의 특정 필드를 변경 | 가장 좁은 `ignore_fields` 경로만 제외 | E-4의 1회 전체 동결과 구분 |
| E-9 | 내부 객체가 있고 runner는 API에 못 닿지만 VPC 관리 인스턴스는 도달 | SSM으로 전환; 관리 인스턴스도 못 닿으면 먼저 경로를 확보하고, 객체가 없으면 두 방식 모두 생략 | E-1·D-5 |
| E-10 | Helm 차트를 설치 | 버전 핀과 필요한 호환 상한을 검증 | E-7 |

## E. Kubernetes 리소스를 만드는 방법

먼저 **클러스터 내부 객체가 있는지**, 다음으로 **Terraform runner가 EKS API 서버에 실제로 도달할 수 있는지**를 판정합니다. runner가 도달하지 못하면 **지정한 VPC 관리 인스턴스가 도달할 수 있는지**도 확인합니다. `endpoint_public_access` 하나만으로 구현을 고르지 않습니다. private endpoint도 runner가 같은 VPC, VPN, Direct Connect, 피어링 또는 적절한 라우팅·DNS 경로 안에 있으면 도달할 수 있고, public endpoint도 runner의 방화벽·proxy·허용 CIDR 때문에 도달하지 못할 수 있습니다.

| 분기 | 내부 객체 | runner의 API 도달성 | VPC 관리 인스턴스의 API 도달성 | 구현 |
| --- | --- | --- | --- | --- |
| 1. Provider | 있음 | 도달 | 관계없음 | `alekc/kubectl`의 `kubectl_manifest`와 `hashicorp/helm`의 `helm_release` (E-1·E-2) |
| 2. SSM | 있음 | 도달하지 못함 | 도달 | 관리 인스턴스의 SSM Association에서 `kubectl`/`helm` 실행 (E-9) |
| 3. Blocked | 있음 | 도달하지 못함 | 도달하지 못함 | 유효한 적용 경로가 없으므로 provider나 SSM을 선언하기 전에 DNS·네트워크 경로를 확보 |
| 4. AWS-only | 없음 | 관계없음 | 관계없음 | `kubectl`/`helm` provider와 SSM 적용 단계를 모두 생략 (E-9의 `108` 사례) |

Provider 분기가 기본입니다. SSM 분기는 runner가 넘지 못하는 네트워크 경계를 도달 가능한 관리 인스턴스로 넘기는 예외이며, 현재 `041_eks_private_cluster`, `106`, `124`가 이 형태입니다. 이 세 루트는 private endpoint 사례지만 private/public 자체가 판정 기준은 아닙니다. `108`처럼 내부 객체를 전혀 만들지 않으면 endpoint 종류와 무관하게 AWS-only 분기입니다.

E-1번은 무엇을 provider 리소스로 소유할지를, E-2번은 같은 apply에서 새 클러스터를 다루는 현재 provider 선택을 정합니다. E-3·E-4도 그 리소스 타입을 그대로 사용합니다. E-7·E-10의 Helm 값 타입과 버전 핀은 Helm을 provider에서 실행하든 SSM에서 실행하든 동일한 차트에 적용되지만, AWS-only 분기에는 설치할 차트 자체가 없습니다.

### E-1. runner가 API 서버에 도달하면 Kubernetes 객체는 `kubectl_manifest`/`helm_release`로 선언한다

runner가 API 서버에 도달할 수 있고 Terraform이 클러스터 내부 객체를 관리한다면, userdata나 `aws_ssm_association`에서 `kubectl apply`/`helm install`을 실행하지 않습니다. Kubernetes 객체는 `alekc/kubectl`의 `kubectl_manifest`, Helm 차트는 `hashicorp/helm`의 `helm_release`로 선언합니다. runner가 도달하지 못하면 E-9번대로 VPC 관리 인스턴스의 도달성을 확인해 SSM 분기를 선택하며, 어느 실행 위치도 도달하지 못하면 먼저 경로를 확보합니다.

```hcl
# 루트 providers.tf
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

이를 위해 `eks_cluster` 모듈은 `cluster_endpoint`와 `certificate_authority_data`(`aws_eks_cluster.eks_cluster.certificate_authority[0].data`)를 output으로 노출합니다. Namespace, RBAC, workload, CRD와 CR 모두 Kubernetes API 필드명을 유지한 HCL 객체를 `yamlencode()`해 선언합니다.

```hcl
resource "kubectl_manifest" "batch_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.namespace }
  })
}

resource "kubectl_manifest" "batch_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata   = { name = var.role_name, namespace = var.namespace }
    rules = [{
      apiGroups = [""]
      resources = ["pods"]
      verbs     = ["get", "list"]
    }]
  })

  depends_on = [kubectl_manifest.batch_namespace]
}

resource "kubectl_manifest" "batch_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata   = { name = var.binding_name, namespace = var.namespace }
    roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "Role", name = var.role_name }
    subjects   = [{ apiGroup = "rbac.authorization.k8s.io", kind = "User", name = var.user_name }]
  })

  # Literal metadata names do not create graph edges by themselves.
  depends_on = [kubectl_manifest.batch_namespace, kubectl_manifest.batch_role]
}
```

Helm 차트는 핀한 버전과 readiness 대기를 가진 `helm_release`로 선언합니다.

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

- 이름을 문자열로만 맞춘 관계는 Terraform이 추론하지 못하므로 객체 간 `depends_on`을 명시합니다. 클러스터 API 경로·용량·컨트롤러 수명은 D-4번대로 루트 모듈 경계에서 표현합니다.
- provider가 소유한 객체는 state와 plan diff에 들어갑니다. 다만 기존 객체 refresh는 plan에서도 API 접속을 요구할 수 있고, chart 렌더링·readiness·controller 결과처럼 클러스터에서만 판정되는 실패는 apply 또는 이후 상태 확인에서 드러날 수 있습니다. "provider 리소스이므로 모든 오류가 plan에서 잡힌다"고 해석하지 않습니다.
- 이 분기에서는 객체 적용용 SSM 마커, `until` 사슬, 원격 `kubectl`/`helm` 설치 검증이 필요 없습니다. H-1번의 workbench 도구는 사람이 조사하는 용도이며 리소스 생성 경로가 아닙니다.

### E-2. 단일 `terraform apply`가 필요하면 Kubernetes 리소스는 `hashicorp/kubernetes` 대신 `alekc/kubectl`의 `kubectl_manifest`로 선언

이 저장소의 현재 Kubernetes 리소스 타입은 처음부터 `kubectl_manifest`입니다. 역사적 이유는 간단합니다. `hashicorp/kubernetes`의 타입드 리소스와 `kubernetes_manifest`는 새 EKS 클러스터를 같은 root/state에서 같은 apply로 만들 때 plan 단계의 unknown endpoint 때문에 provider 구성이 실패할 수 있었고, 그 형태는 별도 root/state를 요구했습니다.

단일 apply를 유지하기 위해 `alekc/kubectl`의 `lazy_load = true`로 실제 클라이언트 초기화를 리소스가 사용되는 시점까지 미룹니다. 이것은 runner의 네트워크 접근을 만들어 주는 기능이 아닙니다. apply 시점에 runner가 API 서버에 도달할 수 있어야 합니다. 도달하지 못하면 E-9번대로 VPC 관리 인스턴스가 도달할 때만 SSM 분기를 사용하고, 그 인스턴스도 도달하지 못하면 네트워크 경로를 먼저 확보합니다.

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

HCL 객체를 `yamlencode()`해 `yaml_body`에 넣고 Kubernetes API 필드명(camelCase: `apiGroups`, `roleRef`, `apiGroup`, `subjects`)을 그대로 씁니다. provider 전용 HCL 중첩 블록 문법으로 번역하지 않습니다.

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
- E-4번의 rollout trigger도 `kubectl_manifest`에서 `spec.template.metadata.annotations`만 가진 부분 매니페스트로 구현합니다. `timestamp()`가 매 plan 바뀌므로 그 레거시 1회 트리거에 한해서만 `lifecycle.ignore_changes = [yaml_body]`를 사용합니다.
- `helm_release`는 `hashicorp/helm`을 유지합니다. 이 리소스는 새 릴리스의 일부 plan을 클러스터 연결 없이 계산할 수 있지만, 기존 릴리스 refresh, provider data source, provider 버전과 구성에 따라 **plan에서도** API 접속이 일어날 수 있습니다. install/upgrade와 `wait = true`의 readiness 판정은 apply 시점에 API 도달성이 필요합니다. 따라서 "Helm은 plan에서 절대 연결하지 않고 apply에서만 연결한다"고 가정하지 않습니다.
- `alekc/kubectl`은 `gavinbunney/kubectl`의 유지보수 포크입니다. 신규 provider는 `gavinbunney`가 아니라 `alekc`를 사용합니다.

### E-3. Kubernetes 커스텀 리소스(CR)는 매니페스트를 HCL 객체로 그대로 선언한다

`SecurityGroupPolicy`나 operator별 객체처럼 provider 전용 리소스 타입이 없는 **커스텀 리소스(Custom Resource, CR)**도 `kubectl_manifest`로 선언합니다. CR은 API를 확장하는 스키마 정의인 **CustomResourceDefinition(CRD)**의 인스턴스입니다. `SecurityGroupPolicy`를 CRD라고 부르지 않습니다.

```hcl
resource "kubectl_manifest" "default_sgp" {
  yaml_body = yamlencode({
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
  })
}
```

- `apiVersion`, `kind`, `metadata`, `spec`와 내부 camelCase 필드는 원본 Kubernetes API 매니페스트의 키를 그대로 사용합니다. YAML 문자열을 손으로 조립하지 않고 HCL 객체 하나를 `yamlencode()`합니다.
- CR이 참조하는 AWS 리소스 값은 같은 모듈의 리소스 참조나 호출자가 주입한 구체 타입의 ID/ARN으로 채웁니다. 셸의 문자열 치환으로 우회하지 않습니다.
- 해당 CRD를 Terraform이 별도 `kubectl_manifest`로 설치한다면 CR 생성 전에 CRD 객체가 API에 등록되어야 합니다. 같은 모듈에서는 CR이 CRD 리소스를 `depends_on`으로 가리키고, 별도 모듈에서는 호출자의 CR 모듈 블록이 CRD 모듈을 기다립니다. CRD bundle을 plan 시점에 읽는다면 D-6번도 함께 확인합니다.
- CR을 reconcile하는 controller, API 경로, 실행 용량은 D-4번대로 CR 모듈보다 오래 살리고, finalizer가 붙는 CR에는 D-7번의 `wait = true`도 설정합니다.

### E-4. Fargate profile보다 먼저 존재한 Deployment를 마이그레이션할 때만 annotation patch로 rollout한다

Fargate profile은 생성된 뒤 새로 스케줄되는 파드에 적용됩니다. 따라서 **이미 실행 중인 Deployment가 실제로 profile보다 먼저 존재했다는 사실이 확인된 레거시·import·마이그레이션**에서는 pod template을 한 번 바꿔 새 파드를 만들 수 있습니다.

신규 구성의 일반 순서에는 이 패턴을 넣지 않습니다. 현재 관리형 Add-on 순서는 `eks_cluster` → `eks_vpc_cni_addon`/`eks_kube_proxy_addon` → `eks_fargate_profile` → `eks_coredns_addon`이므로 CoreDNS Deployment 자체가 profile 뒤에 생성됩니다(C-4). 이 경우 재스케줄할 선행 Deployment가 없으며 별도 rollout trigger는 중복입니다.

과거 bootstrap 또는 `_monolithic` 흐름이 profile 전에 만든 Deployment를 `kubectl rollout restart`하던 경우, 마이그레이션한 구성에서는 같은 1회 동작을 부분 `kubectl_manifest`로 표현합니다.

```hcl
# Legacy/migration-only module: the target Deployment is known to predate the
# Fargate profile. New managed-CoreDNS roots do not need this resource.
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

  wait_for_rollout = true
  depends_on       = [aws_eks_fargate_profile.fargate_profile]

  lifecycle {
    # This is intentionally a one-time migration trigger. Without this, the
    # timestamp would restart the Deployment on every apply.
    ignore_changes = [yaml_body]
  }
}
```

- 적용 전에 대상 Deployment와 파드가 profile보다 먼저 존재하는지 확인합니다. 단지 "Fargate를 쓴다"는 이유로 이 리소스를 추가하지 않습니다.
- **부분 매니페스트만 씁니다.** `metadata.name`/`namespace`와 `spec.template.metadata.annotations`만 설정해 기존 컨테이너, replicas, selector의 소유권을 가져오지 않습니다.
- `timestamp()`는 매 plan 바뀌므로 이 1회 마이그레이션 리소스에 한해서 `ignore_changes = [yaml_body]`가 맞습니다. 일반 drift를 숨기는 패턴으로 확장하지 않습니다.
- `wait_for_rollout`은 annotation 변경 뒤 Deployment rollout 완료를 기다립니다. profile을 먼저 두는 요청 순서는 `depends_on`이 담당하며 둘은 서로 대체하지 않습니다.
- controller가 런타임에 바꾸는 특정 필드만 제외하려는 경우에는 전체 `yaml_body`를 동결하지 않고 E-8번의 `ignore_fields`를 사용합니다.
- 선택적 입력은 `null`을 허용하고 검증하는 B-4번 패턴을 따릅니다. 모듈의 API 경로와 실행 용량 수명은 D-4번대로 호출자가 유지합니다.

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

#### 스키마의 타입을 확인하고 넣습니다 — bool로 보이는 값이 문자열일 수 있습니다

`env` 아래의 값이 전부 문자열인 것은 DaemonSet 환경변수라서 그렇고(`tostring(var.enable_pod_eni)`가 그 이유), **최상위 키도 문자열일 수 있습니다.** `vpc-cni`의 `enableNetworkPolicy`가 그 예로, 스키마가 이렇게 선언합니다.

```json
"enableNetworkPolicy": { "format": "boolean", "type": "string" }
```

`format`만 보고 bool을 넣으면 EKS가 거부합니다.

```
InvalidParameterException: ConfigurationValue provided in request is not supported:
Json schema validation failed with error: [$.enableNetworkPolicy: boolean found, string expected]
```

**E-7과 방향이 반대라는 점이 핵심입니다.** Helm의 `set`은 차트의 `kindIs "bool"` 가드를 통과해야 하므로 진짜 bool이 필요하고, EKS Add-on의 `configuration_values`는 같은 개념을 문자열로 받습니다. 둘을 같은 규칙으로 묶지 않습니다.

| 넣는 곳 | 필요한 타입 | 틀렸을 때 |
| --- | --- | --- |
| `helm_release`의 `set` (차트 값) | 진짜 bool — `type = "string"`을 붙이지 않는다 | 플래그가 조용히 누락되고 차트 기본값으로 동작 (E-7, G-2) |
| `aws_eks_addon`의 `configuration_values` | 스키마가 정한 타입. `enableNetworkPolicy`는 문자열 | apply에서 `InvalidParameterException`으로 즉시 실패 |

**이 실수는 `plan`으로 잡히지 않습니다.** 스키마는 EKS API 쪽에 있고 `configuration_values`는 Terraform에게 그냥 문자열이라서, `validate`와 `plan` 모두 통과하고 apply에서 처음 드러납니다. 그래서 값을 추측하지 말고 스키마를 직접 읽습니다.

```bash
aws eks describe-addon-configuration --addon-name vpc-cni \
  --addon-version "$(aws eks describe-addon-versions --addon-name vpc-cni \
      --kubernetes-version 1.33 --query 'addons[0].addonVersions[0].addonVersion' --output text)" \
  --query 'configurationSchema' --output text > schema.json
# 키가 최상위 properties에 없을 수 있습니다 - definitions 안에 들어 있는 경우가 있어 전체를 훑습니다
python -c "
import json
def walk(n,p=''):
    if isinstance(n,dict):
        for k,v in n.items():
            if k=='enableNetworkPolicy': print(p+'.'+k, '->', json.dumps(v))
            walk(v,p+'.'+k)
    elif isinstance(n,list):
        for i,v in enumerate(n): walk(v,'%s[%d]'%(p,i))
walk(json.load(open('schema.json')))"
```

- 적용된 뒤에는 EKS가 저장한 값을 그대로 되읽어 확인합니다. 문자열로 들어갔는지 여기서 보입니다.

```bash
aws eks describe-addon --cluster-name <cluster> --addon-name vpc-cni \
  --query 'addon.[status,configurationValues]' --output text
#   ACTIVE	{"enableNetworkPolicy":"true"}
```

- 값을 `null`로 둘 수 있게 만들고, `null`이면 그 키를 JSON에서 아예 빼는 편이 낫습니다. 명시적 `null`을 보내면 스키마 검증에 걸리고, 키가 없으면 EKS가 자기 기본값을 적용합니다.

```hcl
configuration = merge(
  length(var.env) > 0 ? { env = var.env } : {},
  var.enable_network_policy != null ? { enableNetworkPolicy = tostring(var.enable_network_policy) } : {},
)
configuration_values = length(local.configuration) > 0 ? jsonencode(local.configuration) : null
```

- `aws_eks_addon`은 `status`라는 output 속성을 노출하지 않습니다 (`arn`, `id`, `configuration_values`, `created_at`, `modified_at` 등은 노출). Add-on 상태를 output으로 참조하려는 경우 `terraform validate` 단계에서 "Unsupported attribute" 에러가 나므로, 실제로 필요한 output만(`arn` 등) 선언합니다.

### E-6. AWS 서비스가 EKS에 접근해야 할 때는 principal이 서비스 연결 역할인지 먼저 확인한다 (Access Entry는 서비스 연결 역할을 지원하지 않음)

**`aws_eks_access_entry`는 서비스 연결 역할(service-linked role)을 principal로 지원하지 않습니다.** `AWSServiceRoleForBatch`처럼 AWS 관리형 서비스가 자동으로 만드는 서비스 연결 역할을 `principal_arn`으로 넘기면 다음 에러로 실패합니다 (AWS 공식 문서에도 명시: "The caller is not allowed to modify access entries with a principalArn value of a Service Linked Role").

```
Error: creating EKS Access Entry (...): InvalidParameterException: The specified principalArn is invalid: invalid principal.
```

서비스 연결 역할인지 아닌지는 ARN으로 구분합니다: `arn:aws:iam::<account>:role/aws-service-role/<service>/<role-name>` 형태(경로에 `aws-service-role/`가 포함)면 서비스 연결 역할입니다. 일반 IAM 역할(`vscode_ec2`의 인스턴스 역할, `karpenter`의 노드 역할 등)은 이 경로가 없으므로 Access Entry로 정상 매핑됩니다 — 이 구분 없이 "서비스가 접근해야 하면 무조건 Access Entry"로 일반화하지 않습니다.

- **일반 IAM 역할**(경로에 `aws-service-role/` 없음)의 ARN은 `aws_eks_access_entry.principal_arn`에 전달합니다. RBAC subject가 고정된 이름을 참조해야 할 때만 `user_name`도 명시적으로 설정합니다:

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

### E-8. 컨트롤러가 값을 바꾸는 필드는 `kubectl_manifest`의 `ignore_fields`로 그 경로만 제외한다 (`lifecycle.ignore_changes = [yaml_body]`는 매니페스트 전체를 동결한다)

매니페스트가 선언한 필드를 클러스터 안의 컨트롤러가 런타임에 바꾸는 경우가 있습니다. 그러면 그 필드에 주인이 둘이 됩니다 — Terraform이 최초 값을 정하고, 컨트롤러가 그 뒤를 가져갑니다.

| 필드 | 최초 값의 주인 | 런타임의 주인 |
| --- | --- | --- |
| Deployment의 `spec.replicas` | 매니페스트 | HorizontalPodAutoscaler, 또는 KEDA가 ScaledObject에서 만드는 HPA |
| Deployment의 `spec.template.spec.containers.<n>.resources` | 매니페스트 | VPA admission controller (`updateMode`가 `Initial`/`Recreate`/`Auto`일 때) |
| `webhooks.<n>.clientConfig.caBundle` | 매니페스트(빈 값) | cert-manager 등의 CA injector |

아무 처리도 하지 않으면 컨트롤러가 값을 옮긴 직후부터 **모든 `plan`이 그것을 되돌리자고 제안**하고, 그 plan을 apply하면 컨트롤러가 다시 조정할 때까지 워크로드가 원래 값으로 돌아갑니다. 오토스케일러가 5로 올린 레플리카가 1로 내려갔다가 몇십 초 뒤 다시 올라가는 왕복이 생깁니다.

#### `lifecycle.ignore_changes = [yaml_body]`로 해결하지 않습니다

`lifecycle`의 최소 단위는 **속성**이고, `kubectl_manifest`에서 매니페스트 전체는 `yaml_body` 속성 하나입니다. 그 안의 경로를 지목할 방법이 없으므로 `ignore_changes = [yaml_body]`는 이미지·애노테이션·셀렉터·레플리카를 한꺼번에 동결합니다. 실패 방향이 나쁩니다 — 이미지를 바꿔도 클러스터에 반영되지 않고, `plan`은 `No changes`라고 답합니다.

```hcl
# 이렇게 하지 않습니다. 이미지를 바꿔도 plan이 "No changes"라고 답합니다
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({ ... })

  lifecycle {
    ignore_changes = [yaml_body]
  }
}
```

프로바이더의 `ignore_fields` 인수가 경로 단위로 같은 일을 합니다.

```hcl
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({ ... })

  # HPA가 이 Deployment의 레플리카 수를 옮기므로 그 필드만 diff에서 제외합니다.
  # 이미지·애노테이션·셀렉터는 계속 추적됩니다 (rules.md E-8).
  ignore_fields = ["spec.replicas"]
}
```

#### 경로는 이름이 아니라 루트부터의 전체 경로입니다

- **필드 이름만 적으면 매칭되지 않습니다.** 매칭은 전체 경로와 그 접두사로 이루어지므로 `["caBundle"]`이 아니라 `["webhooks.0.clientConfig.caBundle"]`처럼 씁니다. 업스트림 문서의 예시가 이름만 적은 형태라서 이 오해가 흔합니다([gavinbunney/terraform-provider-kubectl#83](https://github.com/gavinbunney/terraform-provider-kubectl/issues/83)에 정리되어 있습니다. `alekc/kubectl`은 그 코드의 유지보수 포크입니다).
- **리스트 원소에는 인덱스가 필요하고 와일드카드가 없습니다.** `containers.*.resources`는 쓸 수 없습니다. 컨테이너가 하나면 `containers.0.resources`로 인덱스를 박고, 개수가 가변이면 리스트 전체를 제외하는 것 말고는 표현할 방법이 없습니다.
- **접두사로 매칭되므로 상위 경로를 적으면 그 아래가 전부 제외됩니다.** 편하지만 그것은 `lifecycle` 전체 동결과 같은 함정을 한 단계 작은 범위에서 되풀이하는 것입니다. `containers`를 제외하면 그 안의 이미지 변경도 추적되지 않으므로, **컨트롤러가 실제로 건드리는 가장 깊은 경로**를 적습니다.

#### 최초 값은 그대로 적용됩니다

`ignore_fields`는 이후의 diff 계산에서 그 경로를 빼는 것이고, 생성 시점에는 `yaml_body`가 그대로 apply됩니다. 그래서 `replicas`에 오토스케일러의 하한을 적어두는 것은 여전히 의미가 있습니다 — 데모가 범위의 맨 아래에서 시작하고, 그 뒤에 늘어난 레플리카는 전부 오토스케일러가 만든 것이 됩니다.

#### E-4번과 혼동하지 않습니다

두 규칙이 같은 문제를 다루는 것처럼 보이지만 판단 기준이 다릅니다.

| 상황 | 쓰는 것 |
| --- | --- |
| 컨트롤러가 런타임에 **특정 필드**를 바꾸고, 매니페스트의 나머지는 계속 관리되어야 한다 | `ignore_fields = ["<경로>"]` |
| 값 자체가 매 plan마다 바뀌어서 리소스가 **최초 1회만** 적용되어야 한다 (`timestamp()`, `bcrypt()`) | `lifecycle { ignore_changes = [yaml_body] }` |

E-4번의 rollout 트리거(`timestamp()`)와 043번 프로젝트의 htpasswd Secret(`bcrypt()`)이 아래 행입니다. 그 둘은 리소스가 한 번 적용된 뒤 다시는 적용되지 않는 것이 목적이므로 전체 동결이 맞습니다. 위 행은 목적이 정반대입니다.

#### 확인하는 방법

**apply 후 두 번째 `plan`이 깨끗한지가 판정입니다.** 컨트롤러가 값을 옮길 시간을 준 뒤 실행합니다.

```bash
kubectl -n <ns> scale deployment <name> --replicas 5   # 또는 오토스케일러가 옮기기를 기다립니다
terraform plan                                         # "No changes" 여야 합니다
```

`plan`이 여전히 그 필드를 되돌리려 하면 경로가 틀린 것입니다. 프로바이더가 무엇과 비교하고 있는지는 state의 `yaml_incluster`에서 확인합니다.

```bash
terraform state show 'module.<module>.kubectl_manifest.<name>' | grep -A20 'yaml_incluster'
```

감사할 때는 매니페스트 전체를 동결한 곳을 모두 세고, 각각이 위 표의 아래 행에 해당하는지(`timestamp()`나 `bcrypt()`처럼 값이 매번 바뀌는 사례인지) 확인합니다. 해당하지 않으면 `ignore_fields`로 좁혀야 하는 곳입니다.

```bash
grep -rln 'ignore_changes *= *\[yaml_body\]' --include='*.tf' .
```

### E-9. runner가 EKS API에 도달하지 못하면 도달 가능한 VPC 관리 인스턴스에서 Kubernetes 객체를 적용한다

E-1·E-2의 전제는 provider가 실행되는 **Terraform runner에서 EKS API 서버까지 네트워크·DNS 경로가 실제로 열린다**는 것입니다. runner가 도달하지 못할 때 SSM 분기가 성립하려면 **지정한 VPC 관리 인스턴스는 같은 API에 도달할 수 있어야 합니다.** 둘 다 도달하지 못하면 적용 경로가 없으므로 네트워크를 먼저 고칩니다. `endpoint_public_access`는 노출 정책을 나타낼 뿐 이 실제 도달성을 대신 판정하지 않습니다.

| 내부 객체 | runner의 API 도달성 | VPC 관리 인스턴스의 API 도달성 | 선택 |
| --- | --- | --- | --- |
| 있음 | 도달 | 관계없음 | `kubectl_manifest`/`helm_release` provider (E-1·E-2) |
| 있음 | 도달하지 못함 | 도달 | 관리 인스턴스의 SSM Association에서 `kubectl`/`helm` 실행 (**이 규칙의 SSM 분기**) |
| 있음 | 도달하지 못함 | 도달하지 못함 | 적용 경로가 없으므로 DNS·네트워크 경로를 먼저 확보 (**Blocked**) |
| 없음 | 관계없음 | 관계없음 | Kubernetes provider와 SSM 적용 단계를 모두 생략 (**AWS-only 분기**) |

현재 SSM 사례인 `041_eks_private_cluster`, `106`, `124`는 runner가 private API에 닿지 못하지만 VPC 관리 인스턴스는 닿는 루트입니다. 이 inventory가 규칙을 private endpoint에만 한정하지는 않습니다. `108`은 private endpoint를 쓰지만 Terraform이 만들 내부 객체가 없으므로 AWS-only 분기입니다.

퍼블릭으로 바꾸면 provider를 쓸 수 있다는 이유만으로 원본의 네트워크 경계를 변경하지 않습니다. `124`는 Gateway API가 주제여도 원본 CloudFormation이 private endpoint를 선택했으므로, 현재 runner 대신 VPC 관리 인스턴스가 SSM으로 적용해 원본 경계를 보존합니다. 반대로 private endpoint여도 runner가 도달하면 provider를 사용하고, public endpoint여도 runner만 차단되고 관리 인스턴스가 도달하면 같은 SSM 분기 조건이 성립합니다.

#### endpoint 정책과 실행 경로를 따로 검증합니다

`validation`은 해당 변형이 의도한 endpoint 노출 정책을 고정할 수 있지만 **runner나 관리 인스턴스의 네트워크 도달성을 계산하지는 못합니다.** 같은 `true`나 `false`도 실제 경로와 내부 객체 유무에 따라 provider, SSM, Blocked, AWS-only 분기가 될 수 있습니다. 따라서 error message와 인접 주석에 endpoint 정책, 두 실행 위치의 도달성, 내부 객체의 유무를 함께 기록합니다.

```hcl
# Unreachable-private SSM variant. The false constraint preserves the endpoint
# policy; the SSM resources and comments document how objects are applied.
variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Private-only EKS API; this root's Terraform runner has no route to it, so in-cluster objects are applied by SSM from the VPC"

  validation {
    condition     = var.endpoint_public_access == false
    error_message = "endpoint_public_access must remain false in this variant to preserve its private API boundary. Its Terraform runner cannot reach that endpoint, so Kubernetes objects are applied from the VPC through SSM; to use providers instead, first move or connect the runner to a network that can resolve and reach the private endpoint."
  }
}
```

public provider 변형이 public access를 기능 전제로 삼으면 `true`를 고정할 수 있습니다. reachable-private provider 변형은 `false`인 채 provider를 선언할 수 있고, AWS-only 변형은 내부 객체 실행 경로 자체가 없습니다. "provider를 쓴다 = true", "false = SSM"이라는 교차 검증은 만들지 않습니다.

#### SSM 분기는 runner에서 구성할 수 없는 Kubernetes provider를 선언하지 않습니다

`providers.tf`에 `kubectl`도 `helm`도 두지 않습니다. 이 저장소의 다른 EKS 루트와 다른 유일한 지점이므로, **왜 없는지를 그 파일에 길게 적습니다.** 없는 것은 grep으로 찾을 수 없습니다.

여기서 걸리는 것이 하나 더 있습니다. **`helm_release`를 품은 모듈을 그대로 재사용할 수 없습니다.** 모듈의 `required_providers`에 `helm`이 있으면 Terraform은 루트가 일부러 두지 않은 helm 프로바이더 구성을 요구합니다. 그래서 그런 모듈은 AWS 쪽만 남기고 쪼갭니다 — `041`의 `aws_load_balancer_controller_iam_role`이 그 예로, IRSA 역할만 만들고 `providers.tf`는 `aws`만 선언하며 차트 전용 변수는 제거되어 있습니다. 차트는 SSM 단계가 설치합니다.

`install_chart = false` 같은 토글로 한 모듈을 양쪽에 쓰는 방법은 쓰지 않습니다. 토글이 false여도 모듈이 helm 프로바이더를 **선언**하는 사실은 변하지 않아서, 루트가 갖지 않은 구성을 여전히 요구합니다.

#### SSM 분기에서도 매니페스트는 HCL 객체로 정의합니다

셸로 넘긴다고 YAML 문자열을 손으로 쓰지 않습니다. E-3번 그대로 HCL 객체로 선언하고 `yamlencode`로 렌더링한 뒤, 그 결과를 heredoc으로 인스턴스에 씁니다. 값은 여전히 타입이 있는 한 곳에서만 정의됩니다.

```hcl
locals {
  workload_manifests = [
    { apiVersion = "apps/v1", kind = "Deployment", metadata = { ... }, spec = { ... } },
    { apiVersion = "v1", kind = "Service", ... },
    { apiVersion = "networking.k8s.io/v1", kind = "Ingress", ... },
  ]
  # kubectl이 여러 문서를 읽는 방식 그대로 이어붙입니다.
  workload_yaml = join("\n---\n", [for m in local.workload_manifests : yamlencode(m)])
}
```

```hcl
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${var.marker_path}/load_balancer_controller ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      mkdir -p /home/ec2-user/manifests
      cat > /home/ec2-user/manifests/workload.yaml << 'TFMANIFEST'
      ${local.workload_yaml}
      TFMANIFEST
      kubectl apply -f /home/ec2-user/manifests/workload.yaml
      kubectl -n ${var.workload_namespace} rollout status deployment ${var.workload_name} --timeout=10m
      STEP
      touch ${var.marker_path}/workload
      EOT
```

- **중첩 heredoc이 동작하는 이유**: `<<-EOT`의 들여쓰기 제거는 **템플릿 소스 줄**만 보고 계산됩니다. 보간된 여러 줄 값의 두 번째 줄부터는 컬럼 0에 놓이고, 제거가 끝난 뒤 종료자도 컬럼 0에 놓입니다. 그래서 `bash << 'STEP'` 안의 `cat << 'TFMANIFEST'`가 의도대로 닫힙니다.
- **구분자는 인용하고**(`<< 'TFMANIFEST'`) 본문에 나올 수 없는 문자열로 정합니다. 값은 Terraform이 이미 채웠으므로 셸이 `$`나 백틱을 건드릴 이유가 없습니다.
- **A-4번이 두 배로 중요해집니다.** `.tf`가 CRLF로 저장되면 종료자가 `TFMANIFEST\r`이 되어 heredoc이 파일 끝까지 이어지고 스크립트가 한 줄도 실행되지 않습니다. 이 형태에서는 매니페스트까지 그 안에 들어 있습니다.
- `rollout status`로 단계가 결과를 기다리게 합니다. `kubectl apply`는 객체를 만들 뿐이고, 기다리지 않으면 다음 단계가 아직 없는 것에 의존할 수 있습니다.

#### SSM 분기의 순서는 마커 파일로, 재실행 가능성은 손으로 보장합니다

- 단계 사이의 순서는 `depends_on`이 아니라 마커 파일과 `until` 루프입니다(D-5번). 각 단계는 앞 단계의 마커를 기다리고 자기 마커를 남깁니다.
- **선택적 단계가 있으면 뒤 단계는 "실제로 실행된" 마커를 기다려야 합니다.** 조건에 따라 기다릴 이름을 바꿉니다.

```hcl
until [ -f ${var.marker_path}/${var.override_coredns_image ? "coredns_image" : "load_balancer_controller"} ]; do sleep 10; done
```

- association의 `parameters`가 바뀌면 단계가 다시 실행되므로 각 명령을 재실행 가능하게 만듭니다. `kubectl apply`는 선언을 다시 적용할 수 있습니다. `helm upgrade --install`도 정상 배포 이력이 있거나 새 이름이면 일반적으로 재실행 가능하지만, **유일한 리비전이 `failed`인 경우**에는 `has no deployed releases`로 거부하며 원래 원인을 덮습니다. 그 상태만 골라 정리하는 가드를 단계 안에 넣습니다(E-7번).
- 실패했을 때 스스로 설명하게 만듭니다. `--wait`가 터지면 `Error: context deadline exceeded` 한 줄만 남으므로, 진단 명령을 붙여 그 출력이 association 결과에 들어오게 합니다.

```hcl
helm upgrade --install ... --wait --timeout ${var.helm_timeout_seconds}s \
  || { kubectl -n ${var.namespace} get pods -l app.kubernetes.io/name=${var.chart} -o wide; exit 1; }
```

- helm의 타임아웃은 association의 `wait_for_success_timeout_seconds`보다 **작아야** 합니다. SSM이 먼저 포기하면 아무 설명 없는 `Failed`가 되고, helm이 먼저 포기하면 자기 메시지와 위 진단 출력이 남습니다. 교차 변수 `validation`으로 못박습니다(B-1번).

#### SSM 분기의 전제조건

- 인스턴스의 IAM 역할에 클러스터 접근 권한이 있어야 합니다(`aws_eks_access_entry`, C-1번). 없으면 kubectl이 설치돼 있어도 `error: You must be logged in to the server`로 끝납니다.
- 그 인스턴스는 H-1번의 작업대이므로 kubectl·helm·eksctl이 이미 있습니다. 이 규칙은 그 도구로 **리소스를 만드는** 예외를 허용하는 것이고, H-1번의 "설치되어 있다는 이유로 리소스를 만들지 않는다"는 이 경우에만 뒤집힙니다.
- 아웃바운드 인터넷이 없는 클러스터라면 이미지 경로도 함께 해결해야 합니다. VPC 엔드포인트와 ECR 풀스루 캐시가 필요하고, **캐시는 첫 pull이 리포지토리를 만들기 때문에 pull하는 주체(노드 역할)에 `ecr:CreateRepository`와 `ecr:BatchImportUpstreamImage`가 있어야 합니다.** `AmazonEC2ContainerRegistryReadOnly`에는 둘 다 없고, 없을 때 ECR은 권한 오류가 아니라 `not found`로 답하므로 이미지 경로 오타처럼 보입니다. `aws ecr describe-repositories`가 빈 목록인데 파드가 `ImagePullBackOff`면 이것입니다.

#### SSM 분기에서만 잃는 것

다음 비용은 provider 분기나 내부 객체가 없는 AWS-only 분기의 성질이 아니라, **SSM으로 객체를 적용하는 분기에서만** 생깁니다.

- **Kubernetes 객체가 Terraform state에 없습니다.** `plan`에 diff가 없고, 드리프트가 감지되지 않으며, `terraform output`으로 확인할 수 있는 것도 없습니다. 무엇이 적용되었는지는 클러스터에 물어봐야만 알 수 있습니다.
- **D-4번이 적용되지 않습니다.** Terraform이 지울 것이 없으므로 destroy 순서를 잡을 대상도 없습니다. 대신 **반대 위험이 생깁니다**: 워크로드 매니페스트가 Terraform 리소스가 아니므로 `terraform destroy`는 Ingress/Service를 먼저 지우지 않고 클러스터를 내리고, 컨트롤러가 만든 로드밸런서가 고아로 남을 수 있습니다. 로드밸런서를 미리 만들어 채택시키는 G-3번 패턴이 이 위험을 로드밸런서에 한해 줄여줍니다.
- **모든 값이 셸을 한 번 통과합니다.** 인용, 줄바꿈, `$`가 전부 표면이 됩니다.
- **실패 메시지가 한 단계 멀어집니다.** association은 `unexpected state 'Failed'`만 알려줍니다. 원인은 A-4번의 절차(`describe-association-executions` → `describe-association-execution-targets` → `get-command-invocation`)로 꺼내야 하고, 그 출력의 `ExecutionElapsedTime`이 `0.0x`초면 명령이 실행된 것이 아니라 파싱에서 실패한 것입니다.

#### 분기를 확인하는 방법

도달성은 저장소만 읽어 확정할 수 없는 **실행 환경 사실**입니다. `endpoint_public_access`의 기본값으로 provider/SSM을 자동 판정하지 않습니다. 먼저 관리할 내부 객체를 찾고 실제 apply runner에서 endpoint의 DNS 해석과 TCP/TLS 연결을 확인합니다. runner 검사가 실패하면 같은 probe를 SSM Run Command로 후보 VPC 관리 인스턴스에서 실행한 뒤 네 분기 중 하나로 분류합니다.

```bash
# 1. 구성에 내부 객체가 있는지 찾는 후보 검색
#    provider 소유 객체와 SSM/스크립트 적용 경로를 모두 봅니다.
grep -rnE 'resource "(kubectl_manifest|helm_release)"|kubectl apply|helm (upgrade|install)' \
  --include='*.tf' . | grep -v '/_monolithic/' | grep -v '/.terraform/'

# 2. 실제 runner에서 endpoint 연결 확인. HTTP 401/403도 네트워크 경로는
#    도달했다는 뜻이고, DNS 실패나 connect timeout은 도달하지 못한 것입니다.
endpoint=$(aws eks describe-cluster --name <cluster> --query 'cluster.endpoint' --output text)
curl --connect-timeout 5 -sk -o /dev/null -w '%{http_code}\n' "$endpoint/healthz"
```

- **Provider 분기:** endpoint가 public/private인지와 관계없이 runner가 도달하며 내부 객체가 있습니다. `kubectl`/`helm` provider를 구성하고 실제 runner에서 `terraform plan`과 apply를 검증합니다.
- **SSM 분기 (`041`/`106`/`124`):** 내부 객체가 있고 runner는 API에 도달하지 못하지만 지정한 VPC 관리 인스턴스는 도달합니다. 루트에는 구성된 `kubectl`/`helm` provider가 없어야 하며, SSM 단계의 `until`과 `touch` 사슬을 대조합니다.

```bash
grep -c 'until \[ -f' main.tf
grep -c 'touch .*marker_file_path' main.tf
```

- **Blocked 분기:** 내부 객체가 있는데 runner와 관리 인스턴스 모두 도달하지 못합니다. provider나 SSM 리소스를 추가해 실패를 늦추지 말고 DNS·라우팅·방화벽 경로를 먼저 만듭니다.
- **AWS-only 분기 (`108`):** 내부 객체가 없으므로 Kubernetes provider 리소스도 SSM의 `kubectl apply`/`helm install` 단계도 없어야 합니다. endpoint 종류만으로 빈 적용 경로를 만들지 않습니다.

### E-10. `helm_release`의 `version`은 핀하고, 차트가 번들 의존성을 떼어낸 메이저는 `validation`으로 막는다 — 차트 호환성은 plan이 보장하지 않으며 대개 apply 렌더링에서 드러난다

차트는 자기 안에 있던 서브차트를 떼어낼 수 있습니다. 그러면 그 의존성은 릴리스의 일부가 아니라 **선행조건**이 되고, 같은 값으로 어제까지 설치되던 릴리스가 설치되지 않습니다.

`045_eks_gitlab_jenkins`의 GitLab 차트가 그랬습니다. 10.0.0이 PostgreSQL·Redis·MinIO 셋을 한꺼번에 떼어내서, 그 버전부터는 RDS·ElastiCache·S3를 먼저 만들어 두지 않으면 차트가 렌더링을 거부합니다.

```
Error: execution error at (gitlab/templates/NOTES.txt:222:3):
CONFIGURATION CHECKS:
    You must configure an PostgreSQL connetion. Please set `global.psql.host`. Since chart v10.0.0,
```

`terraform validate`는 차트 내용을 검사하지 않습니다. `terraform plan`은 기존 릴리스를 refresh하거나 provider 동작에 따라 API에 접속할 수 있지만, 최종 값으로 차트의 모든 템플릿·NOTES 검사를 반드시 실행해 호환성을 보장하는 단계는 아닙니다. 이 incident에서는 plan이 통과했고 provider가 차트를 렌더링한 apply 중에 처음 실패했습니다. 따라서 apply 전에 같은 버전과 값으로 `helm template`을 별도 실행합니다.

#### 어디서 멈췄는지를 먼저 판정합니다

이 실패의 특징은 **릴리스 레코드가 남지 않는다**는 것입니다. `fail`은 템플릿이 아직 렌더링되는 중에 터지므로 아무것도 만들어지지 않고, 스토리지에 기록도 되지 않습니다. E-7번의 "실패한 릴리스가 남아 다음 apply를 막는" 상황과 증상이 비슷해 보이지만 복구 절차가 정반대이므로, 짐작하지 말고 릴리스 히스토리에 물어봅니다.

| `helm history <release> -n <ns>` | 어디서 멈췄는가 | 무엇을 하는가 |
| --- | --- | --- |
| `Error: release: not found` | 렌더링 — 아무것도 만들어지지 않음 | 정리할 것이 없습니다. 버전이나 값을 고치고 다시 apply (이 규칙) |
| `STATUS=failed` | 렌더링을 통과한 뒤 리소스 생성에서 | `helm uninstall`로 이름을 비운 뒤 apply (E-7번) |

전자에 E-7번의 `helm uninstall`을 시도하면 `release: not found`가 또 나오고, 그 메시지를 권한이나 네임스페이스 문제로 오진하게 됩니다.

#### 무엇을 하는가

- **`version`을 핀합니다.** 핀하지 않은 `helm install`은 무엇이 설치되는지가 실행한 날짜에 달려 있다는 뜻입니다. `_monolithic`이 `--version` 없이 돌리던 스크립트는 전부 이 성질을 갖고 있으므로, 변환할 때 버전을 정하는 것이 변환의 일부입니다.
- **번들 의존성에 기대고 있으면 메이저 상한을 `validation`으로 못박습니다.** 기대고 있다는 사실은 "이 프로젝트에 데이터베이스를 만드는 리소스가 없다"로 드러나며, 그것은 코드에 적혀 있지 않습니다.

```hcl
variable "chart_version" {
  type        = string
  default     = "9.11.13"
  description = "... 9.x 시리즈여야 합니다. 10.0.0이 번들 PostgreSQL·Redis·MinIO를 제거했고, 이 프로젝트에는 그 셋을 대신할 리소스가 없습니다 ..."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a three-part semantic version."
  }

  validation {
    # 한 자리 메이저 정규식입니다. tonumber(split(".", var.chart_version)[0]) < 10 으로 쓰면
    # 안 됩니다 - Terraform은 validation 블록을 전부 평가하므로, 위의 semver 검증이 이것을
    # 막아주지 않고 숫자가 아닌 메이저에서 tonumber가 이 메시지가 아닌 하드 에러를 냅니다 (B-1번).
    condition     = can(regex("^[0-9]\\.", var.chart_version))
    error_message = "chart_version must be below 10.0.0, because this module installs GitLab with its bundled PostgreSQL, Redis and MinIO and chart 10.0.0 removed all three. A 10.x version does not fail at plan - it fails partway through apply, when the chart's own NOTES.txt check reports that global.psql.host and global.redis.host are unset. 9.11.13 is the newest version that still bundles them. To run 10.x, provision external PostgreSQL, Redis and S3 object storage first and wire them in through additional_set_values."
  }
}
```

- **`error_message`에는 그 메이저로 가려면 무엇이 필요한지 적습니다**(B-1번). "10.x는 안 된다"로 끝내면 다음 사람이 상한을 지우는 것으로 해결하려 합니다.
- **올릴 때는 `helm template`으로 먼저 렌더합니다.** 올려도 되는지는 릴리스 노트가 아니라 그 버전이 이 값으로 렌더링되는지가 답합니다.

```bash
helm template <release> <repo>/<chart> --version <v> --kube-version 1.34.0 -n <ns> \
  --set <이 모듈이 넘기는 값 전부> > /dev/null
# exit 0 이면 그 버전은 이 값으로 설치됩니다. 번들이 남아 있는지는 Chart.yaml의 조건으로 봅니다
helm show chart <repo>/<chart> --version <v> | grep -E 'condition:|^version:'
```

#### 번들을 유지하는 선택에는 용량이 따라옵니다

떼어내지 않은 데이터스토어는 **노드에 올라갑니다.** 그리고 그 비용은 plan에도 apply에도 나타나지 않습니다 — `045`는 릴리스가 `deployed`로 끝났고, webservice 레플리카 하나가 `Insufficient memory`로 Pending인 채였습니다.

```
0/4 nodes are available: 4 Insufficient memory.
```

숫자를 보면 왜 헷갈리는지가 드러납니다.

| | 값 |
| --- | --- |
| 요청 합계 (GitLab + Jenkins + kube-system) | 약 10 GiB |
| 노드 allocatable 합계 (t3.medium × 4) | 약 12.8 GiB |
| 최대 단일 파드 (webservice, 레플리카당) | 2480 Mi |
| 노드 하나의 allocatable (t3.medium) | 3292 Mi |

**합계는 들어가고 파드는 들어가지 않습니다.** 2480Mi 파드가 3292Mi 노드에 다른 것과 함께 앉을 자리가 없기 때문이고, 클러스터는 여전히 여유 메모리를 보고합니다. 그래서 **노드 크기를 정하는 것은 요청 합계가 아니라 최대 단일 파드**입니다. 합계는 노드 개수를 정합니다.

- **오토스케일러가 없는 프로젝트에서는 스스로 낫지 않습니다.** 이 저장소의 대부분이 그렇습니다 — `max_size`가 `desired_size`보다 커도 그것을 늘려줄 주체가 없습니다.
- **`_monolithic`의 인스턴스 타입을 그대로 베끼지 않습니다.** 원본이 그 차트의 그 시점 버전에서 동작했다는 것이 핀한 버전에서도 동작한다는 뜻은 아닙니다. `045`는 원본의 `t3.medium`을 `t3.large`로 올렸고, 원본과 달라진 이유를 변수 `description`에 적었습니다(`_monolithic/`은 조회 전용이므로 모듈화된 쪽을 고칩니다).
- **`instance_types` 변경은 노드그룹을 교체합니다.** EKS API에 인스턴스 타입을 in-place로 바꾸는 호출이 없어서 프로바이더가 `forces replacement`로 표시하고, 기본 순서가 destroy-then-create이므로 **모든 노드가 사라진 뒤에 새 노드가 생깁니다.** 클러스터의 모든 파드가 재스케줄되고 그동안 서비스가 끊깁니다. PVC는 이 plan에 들어오지 않으므로 데이터는 남지만, EBS 볼륨은 AZ에 묶여 있어 그 AZ에 새 노드가 생겨야 재연결됩니다 — 노드 개수가 서브넷 개수보다 적으면 비어 있는 AZ가 생길 수 있습니다. 그래서 타입을 올릴 때는 미리 PVC 목록과 노드의 AZ 분포를 적어 두고 교체 뒤에 대조합니다.

#### 확인하는 방법

차트 버전을 핀하지 않았거나 상한이 없는 `helm_release`를 찾습니다.

```bash
# version을 아예 설정하지 않은 릴리스
python - <<'PY'
import pathlib, re
for tf in pathlib.Path('.').rglob('modules/*/main.tf'):
    if {'_monolithic', '.terraform'} & set(tf.parts):
        continue
    text = tf.read_text(encoding='utf-8')
    for m in re.finditer(r'resource "helm_release" "([^"]+)" \{', text):
        depth, i = 1, m.end()
        while depth and i < len(text):
            depth += (text[i] == '{') - (text[i] == '}')
            i += 1
        body = text[m.end():i]
        if not re.search(r'^\s*version\s*=', body, re.M):
            print(f'{tf}: {m.group(1)} pins no chart version')
PY
```

용량은 명령 하나로 판정됩니다. **apply가 성공해도 이것은 드러나지 않으므로, apply 뒤에 한 번은 봐야 합니다.**

```bash
# 스케줄되지 못한 파드. 비어 있어야 정상입니다
kubectl get pods -A --field-selector status.phase=Pending

# 노드 크기를 정하기 전에 차트가 요구하는 최대 단일 파드를 봅니다
helm template <release> <repo>/<chart> --version <v> --kube-version 1.34.0 \
  | grep -A3 'resources:' | grep -E 'memory'
```
