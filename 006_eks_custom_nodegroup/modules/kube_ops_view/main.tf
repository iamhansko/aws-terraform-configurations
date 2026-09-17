locals {
  # kube-ops-view is always fronted by a Service, never an Ingress, so unlike
  # the game_2048 module there is only one kind of object to read. Defined once
  # so the commands this module exposes cannot disagree (rules.md B-5).
  load_balancer_hostname_command = "kubectl -n ${var.namespace} get service ${var.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
# Declared as manifests rather than installed from a Helm chart, for two reasons
# found the hard way:
#
#   1. There is no dependable chart. Upstream (hjacobs/kube-ops-view) moved to
#      Codeberg and publishes kustomize manifests only - which is why the
#      _monolithic template did "git clone ... && kubectl apply -k deploy". The
#      community charts are third-party republications, and one of them
#      (christianknell/helm-charts) simply 404s, taking the whole plan down with
#      "Unable to locate chart kube-ops-view".
#   2. The maintained community chart (christianhuth/helm-charts 8.3.3) renders no
#      metadata.annotations on its Service at all, so service annotations passed
#      to it are silently dropped. That is fatal for the NLB variants of project
#      008, where service.beta.kubernetes.io/aws-load-balancer-* annotations are
#      the entire mechanism that hands provisioning to the AWS Load Balancer
#      Controller.
#
# The object definitions below are the ones that chart renders (image
# docker.io/hjacobs/kube-ops-view:23.5.0, container port 8080, /health probes,
# nodes+pods list and metrics.k8s.io read RBAC), with the Service gaining the
# annotation support the chart lacks. Declaring them directly also removes the
# last https:// Helm repository from this project, so the provider's repository
# index cache is no longer on the critical path (see providers.tf).
#
# Uses alekc/kubectl because this module is applied in the same terraform apply
# as the cluster whose outputs configure the provider (rules.md E-3/E-2).
locals {
  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/managed-by" = "terraform"
  }
  selector_labels = {
    "app.kubernetes.io/name" = var.name
  }
}
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
  })
}
# kube-ops-view is a read-only dashboard: it lists nodes and pods to draw them,
# and reads the metrics API to colour them by utilization. Nothing here grants
# write access to anything.
resource "kubectl_manifest" "cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name   = var.cluster_role_name
      labels = local.labels
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["nodes", "pods"]
        verbs     = ["list"]
      },
      {
        # Supplies the CPU and memory figures. Without metrics-server installed
        # these calls fail and the dashboard renders boxes without utilization,
        # rather than failing outright.
        apiGroups = ["metrics.k8s.io"]
        resources = ["nodes", "pods"]
        verbs     = ["get", "list"]
      },
    ]
  })
}
resource "kubectl_manifest" "cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name   = var.cluster_role_name
      labels = local.labels
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = var.cluster_role_name
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = var.name
      namespace = var.namespace
    }]
  })

  # roleRef.name and the subject are literal strings, so nothing else tells
  # Terraform the ClusterRole and ServiceAccount must exist first (rules.md E-2).
  depends_on = [kubectl_manifest.cluster_role, kubectl_manifest.service_account]
}
resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
    }
    spec = {
      replicas             = var.replica_count
      revisionHistoryLimit = 10
      selector             = { matchLabels = local.selector_labels }
      template = {
        metadata = { labels = local.selector_labels }
        spec = {
          serviceAccountName = var.name
          containers = [{
            name            = var.name
            image           = "${var.image_repository}:${var.image_tag}"
            imagePullPolicy = var.image_pull_policy
            ports = [{
              name          = "http"
              containerPort = var.container_port
              protocol      = "TCP"
            }]
            securityContext = {
              capabilities             = { drop = ["ALL"] }
              readOnlyRootFilesystem   = true
              runAsNonRoot             = true
              runAsUser                = 1000
              allowPrivilegeEscalation = false
            }
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
              limits = {
                cpu    = var.cpu_limit
                memory = var.memory_limit
              }
            }
            livenessProbe = {
              httpGet             = { path = "/health", port = "http" }
              initialDelaySeconds = 30
              periodSeconds       = 30
              timeoutSeconds      = 10
              failureThreshold    = 5
            }
            readinessProbe = {
              httpGet             = { path = "/health", port = "http" }
              initialDelaySeconds = 5
              timeoutSeconds      = 1
            }
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.service_account]
}
resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = local.labels
      # The annotations the upstream community chart drops. With
      # service_type = LoadBalancer these are what select and configure the load
      # balancer the AWS Load Balancer Controller creates.
      annotations = var.service_annotations
    }
    spec = {
      type     = var.service_type
      selector = local.selector_labels
      ports = [{
        name       = "http"
        port       = var.service_port
        targetPort = "http"
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.deployment]
}
