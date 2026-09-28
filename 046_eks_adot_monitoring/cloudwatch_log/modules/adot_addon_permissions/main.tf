# What EKS needs before it can install the ADOT add-on.
#
# The add-on is installed by EKS itself, acting as the Kubernetes user eks:addon-manager
# through the control plane. That user has no standing permission to create the
# OpenTelemetry Operator's CRDs, webhooks, namespace or Deployment - so these five objects
# are the grant that lets it, and without them the add-on install fails with a forbidden
# error rather than doing nothing.
#
# The _monolithic template got them with
#   kubectl apply -f https://amazon-eks.s3.amazonaws.com/docs/addons-otel-permissions.yaml
# from an SSM Association on the bastion. That leaves five cluster-scoped RBAC objects
# outside Terraform: no diff in plan, nothing removed on destroy, and their contents
# whatever that URL served on the day. Declared here they are reviewable and versioned with
# the rest of the configuration (rules.md E-1/E-2/E-3).
#
# The rules are transcribed from that document rather than invented. They are wider than
# they look at first: most entries are scoped by resourceNames to the exact objects the
# operator install creates, and the unscoped ones at the end are what the operator itself
# needs once running.
locals {
  # Cluster-scoped. Creating CRDs, the operator's namespace, its cluster roles and its
  # webhook configurations - each pinned to the names the add-on uses.
  cluster_rules = [
    {
      apiGroups     = ["apiextensions.k8s.io"]
      resources     = ["customresourcedefinitions"]
      resourceNames = ["opentelemetrycollectors.opentelemetry.io", "instrumentations.opentelemetry.io"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups     = [""]
      resources     = ["namespaces"]
      resourceNames = [var.operator_namespace]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["rbac.authorization.k8s.io"]
      resources = ["clusterroles"]
      resourceNames = [
        "opentelemetry-operator-manager-role",
        "opentelemetry-operator-metrics-reader",
        "opentelemetry-operator-proxy-role",
        "otel-prometheus-role",
      ]
      verbs = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["rbac.authorization.k8s.io"]
      resources = ["clusterrolebindings"]
      resourceNames = [
        "opentelemetry-operator-manager-rolebinding",
        "opentelemetry-operator-proxy-rolebinding",
        "otel-prometheus-rolebinding",
      ]
      verbs = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["admissionregistration.k8s.io"]
      resources = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
      resourceNames = [
        "opentelemetry-operator-mutating-webhook-configuration",
        "opentelemetry-operator-validating-webhook-configuration",
      ]
      verbs = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    # From here down the rules are unscoped, and they are what the operator needs at
    # runtime rather than what installing it needs: it reconciles OpenTelemetryCollector
    # objects into Deployments, DaemonSets, Services and ConfigMaps in whichever namespace
    # the collector is declared in, so those cannot be pinned to names known in advance.
    {
      nonResourceURLs = ["/metrics"]
      verbs           = ["get"]
    },
    {
      apiGroups = [""]
      resources = ["configmaps"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["events"]
      verbs     = ["create", "patch"]
    },
    {
      apiGroups = [""]
      resources = ["namespaces"]
      verbs     = ["list", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["serviceaccounts"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["services"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["apps"]
      resources = ["daemonsets"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["apps"]
      resources = ["deployments"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["apps"]
      resources = ["replicasets"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["apps"]
      resources = ["statefulsets"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["autoscaling"]
      resources = ["horizontalpodautoscalers"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["coordination.k8s.io"]
      resources = ["leases"]
      verbs     = ["create", "get", "list", "update"]
    },
    {
      apiGroups = ["opentelemetry.io"]
      resources = ["opentelemetrycollectors"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["opentelemetry.io"]
      resources = ["opentelemetrycollectors/finalizers"]
      verbs     = ["get", "patch", "update"]
    },
    {
      apiGroups = ["opentelemetry.io"]
      resources = ["opentelemetrycollectors/status"]
      verbs     = ["get", "patch", "update"]
    },
    {
      apiGroups = ["opentelemetry.io"]
      resources = ["instrumentations"]
      verbs     = ["get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = ["authentication.k8s.io"]
      resources = ["tokenreviews"]
      verbs     = ["create"]
    },
    {
      apiGroups = ["authorization.k8s.io"]
      resources = ["subjectaccessreviews"]
      verbs     = ["create"]
    },
    {
      apiGroups = ["networking.k8s.io"]
      resources = ["ingresses"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["endpoints"]
      verbs     = ["get"]
    },
    {
      apiGroups = [""]
      resources = ["nodes/proxy"]
      verbs     = ["get", "list", "watch"]
    },
    {
      apiGroups = ["extensions"]
      resources = ["ingresses"]
      verbs     = ["get"]
    },
  ]
  # Namespaced, inside the operator's own namespace. The scoped entries are the operator's
  # own service account, roles, services and Deployment; the unscoped ones at the end are
  # what it needs while running.
  namespaced_rules = [
    {
      apiGroups     = [""]
      resources     = ["serviceaccounts"]
      resourceNames = ["opentelemetry-operator-controller-manager"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups     = ["rbac.authorization.k8s.io"]
      resources     = ["roles"]
      resourceNames = ["opentelemetry-operator-leader-election-role"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups     = ["rbac.authorization.k8s.io"]
      resources     = ["rolebindings"]
      resourceNames = ["opentelemetry-operator-leader-election-rolebinding"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["services"]
      resourceNames = [
        "opentelemetry-operator-controller-manager-metrics-service",
        "opentelemetry-operator-webhook-service",
      ]
      verbs = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups     = ["apps"]
      resources     = ["deployments"]
      resourceNames = ["opentelemetry-operator-controller-manager"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      # The operator's webhook serves TLS from a certificate cert-manager issues, which is
      # why cert-manager has to be installed before the add-on. These two rules are the
      # only reason this RBAC mentions cert-manager at all.
      apiGroups     = ["cert-manager.io"]
      resources     = ["certificates", "issuers"]
      resourceNames = ["opentelemetry-operator-serving-cert", "opentelemetry-operator-selfsigned-issuer"]
      verbs         = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["configmaps"]
      verbs     = ["create", "delete", "get", "list", "patch", "update", "watch"]
    },
    {
      apiGroups = [""]
      resources = ["configmaps/status"]
      verbs     = ["get", "update", "patch"]
    },
    {
      apiGroups = [""]
      resources = ["events"]
      verbs     = ["create", "patch"]
    },
    {
      apiGroups = [""]
      resources = ["pods"]
      verbs     = ["list"]
    },
  ]
  # Both bindings name the same subject: the user EKS authenticates as.
  addon_manager_subject = [{
    kind     = "User"
    name     = var.addon_manager_user
    apiGroup = "rbac.authorization.k8s.io"
  }]
}
# Created here rather than left to the add-on, even though the add-on has permission to
# create it. The namespaced Role below has to exist in it, and a Role cannot be created in
# a namespace that is not there yet - so the ordering only works one way round.
resource "kubectl_manifest" "operator_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.operator_namespace
      labels = {
        "app.kubernetes.io/component" = "controller-manager"
      }
    }
  })
}
resource "kubectl_manifest" "cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = var.cluster_role_name
    }
    # camelCase, as the Kubernetes API defines them - not HCL block syntax
    # (rules.md E-2/E-3).
    rules = local.cluster_rules
  })
}
resource "kubectl_manifest" "cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = var.cluster_role_name
    }
    subjects = local.addon_manager_subject
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = var.cluster_role_name
    }
  })

  # roleRef.name is a literal string, so Terraform's graph does not otherwise know the
  # ClusterRole must exist first (rules.md D-1/E-2).
  depends_on = [kubectl_manifest.cluster_role]
}
resource "kubectl_manifest" "namespaced_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = var.namespaced_role_name
      namespace = var.operator_namespace
    }
    rules = local.namespaced_rules
  })

  # metadata.namespace is a literal string (rules.md D-1).
  depends_on = [kubectl_manifest.operator_namespace]
}
resource "kubectl_manifest" "namespaced_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = var.namespaced_role_name
      namespace = var.operator_namespace
    }
    subjects = local.addon_manager_subject
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = var.namespaced_role_name
    }
  })

  depends_on = [kubectl_manifest.operator_namespace, kubectl_manifest.namespaced_role]
}
