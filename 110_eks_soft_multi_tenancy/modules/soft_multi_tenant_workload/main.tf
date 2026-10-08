# The Calico "stars" demo arranged as two tenants, plus the quotas and NetworkPolicies that isolate them.
#
# Every object here is a kubectl_manifest rather than a YAML file rendered by a shell script and applied with
# kubectl, which is what the _monolithic template did from a single SSM association (rules.md E-1/E-2). What
# that bought: nothing was in Terraform state, so a destroy removed the cluster and took the objects with it
# without ever removing them in order, and a change to a quota meant re-running a 200-line shell script.
#
# alekc/kubectl rather than hashicorp/kubernetes, because the cluster is created in the same apply
# (rules.md E-2).
locals {
  # The namespaces, keyed the same way as the tenants so a policy can find its own namespace without a second
  # lookup.
  tenant_namespaces = var.tenants
  # Every Deployment and Service exists once per tenant, so they are all keyed by tenant label. The
  # _monolithic template rendered them with a shell "for TENANT in tenant-a tenant-b" loop writing YAML to
  # disk, which meant the list of tenants appeared in three places - the namespace document, the quota
  # document, and that loop.
  tenant_labels = keys(var.tenants)
}
resource "kubectl_manifest" "tenant_namespace" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = each.value
      labels = {
        # The label the tenant is identified by. The _monolithic template set tenant: a and tenant: b - the
        # bare letter rather than the namespace - which nothing selected on. Setting it to the label keeps it
        # usable as a selector.
        tenant = each.key
      }
    }
  })
}
resource "kubectl_manifest" "management_ui_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.management_ui_namespace
      labels = {
        # This label is what the allow-ui policy selects on, so it is the one thing that lets the UI through a
        # default-deny namespace. One value feeds both (rules.md B-5).
        role = var.management_ui_role_label
      }
    }
  })
}
# ---------------------------------------------------------------------------------------------------
# Quotas. The half of multi-tenancy the IAM access scope does nothing about.
# ---------------------------------------------------------------------------------------------------
resource "kubectl_manifest" "tenant_quota" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ResourceQuota"
    metadata = {
      name      = "tenant-quota"
      namespace = each.value
    }
    spec = {
      hard = {
        # Quantities as strings, which is what Kubernetes expects - "20" rather than 20. A number here
        # serialises without quotes and the API server rejects the object.
        "pods"            = tostring(var.resource_quota.pods)
        "requests.cpu"    = var.resource_quota.requests_cpu
        "requests.memory" = var.resource_quota.requests_memory
        "limits.cpu"      = var.resource_quota.limits_cpu
        "limits.memory"   = var.resource_quota.limits_memory
      }
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace]
}
# What makes the quota effective. A container with no resource requests counts as zero against a requests
# quota, so without these defaults a tenant could run far more than the quota appears to allow - and the quota
# would look like it was working.
resource "kubectl_manifest" "tenant_limit_range" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "LimitRange"
    metadata = {
      name      = "tenant-limitrange"
      namespace = each.value
    }
    spec = {
      limits = [{
        type = "Container"
        default = {
          cpu    = var.limit_range.default_cpu
          memory = var.limit_range.default_memory
        }
        defaultRequest = {
          cpu    = var.limit_range.default_request_cpu
          memory = var.limit_range.default_request_memory
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace]
}
# ---------------------------------------------------------------------------------------------------
# The workload: a frontend and a backend probe in each tenant.
#
# Each probe is told to poll both tenants' services, which is what makes the policies visible: the probe
# reports which URLs answered, so a blocked path shows up as a timeout in the graph rather than having to be
# inferred.
# ---------------------------------------------------------------------------------------------------
resource "kubectl_manifest" "backend_service" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "backend"
      namespace = each.value
      labels    = { role = "backend" }
    }
    spec = {
      ports    = [{ port = var.backend_port }]
      selector = { role = "backend" }
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace]
}
resource "kubectl_manifest" "backend_deployment" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "backend"
      namespace = each.value
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = "backend" } }
      template = {
        metadata = { labels = { role = "backend" } }
        spec = {
          containers = [{
            name  = "backend"
            image = var.probe_image
            command = concat(
              ["probe", "--http-port=${var.backend_port}"],
              # Every tenant's frontend, so the backend's own view of what it can reach is recorded too. Built
              # from the tenant map rather than written out, which is what the original did with two literal
              # URLs - adding a third tenant there meant editing the command line of every probe.
              ["--urls=${join(",", [for namespace in values(var.tenants) : "http://frontend.${namespace}.svc.cluster.local:${var.frontend_port}/status"])}"],
            )
            ports = [{ containerPort = var.backend_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace, kubectl_manifest.tenant_limit_range]
}
resource "kubectl_manifest" "frontend_service" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "frontend"
      namespace = each.value
      labels    = { role = "frontend" }
    }
    spec = {
      ports    = [{ port = var.frontend_port }]
      selector = { role = "frontend" }
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace]
}
resource "kubectl_manifest" "frontend_deployment" {
  for_each = var.tenants

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "frontend"
      namespace = each.value
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = "frontend" } }
      template = {
        metadata = { labels = { role = "frontend" } }
        spec = {
          containers = [{
            name  = "frontend"
            image = var.probe_image
            command = concat(
              ["probe", "--http-port=${var.frontend_port}"],
              ["--urls=${join(",", [for namespace in values(var.tenants) : "http://backend.${namespace}.svc.cluster.local:${var.backend_port}/status"])}"],
            )
            ports = [{ containerPort = var.frontend_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace, kubectl_manifest.tenant_limit_range]
}
# ---------------------------------------------------------------------------------------------------
# The management UI, which polls every probe and draws the result.
# ---------------------------------------------------------------------------------------------------
resource "kubectl_manifest" "probes_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "probes"
      namespace = var.management_ui_namespace
    }
    data = {
      # Built from the tenant map, so a third tenant appears in the graph without editing JSON. The
      # _monolithic template listed four entries literally, with ids - FA, BA, FB, BB - that encoded the
      # tenant letters.
      "probes.json" = jsonencode(flatten([
        for label, namespace in var.tenants : [
          {
            id  = "frontend-${label}"
            url = "http://frontend.${namespace}.svc.cluster.local:${var.frontend_port}/status"
          },
          {
            id  = "backend-${label}"
            url = "http://backend.${namespace}.svc.cluster.local:${var.backend_port}/status"
          },
        ]
      ]))
    }
  })

  depends_on = [kubectl_manifest.management_ui_namespace]
}
resource "kubectl_manifest" "management_ui_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name        = var.management_ui_name
      namespace   = var.management_ui_namespace
      labels      = { role = var.management_ui_role_label }
      annotations = var.service_annotations
    }
    spec = {
      type     = "LoadBalancer"
      selector = { role = var.management_ui_role_label }
      ports = [{
        port       = var.management_ui_service_port
        targetPort = var.management_ui_container_port
        protocol   = "TCP"
      }]
    }
  })

  depends_on = [kubectl_manifest.management_ui_namespace]
}
resource "kubectl_manifest" "management_ui_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.management_ui_name
      namespace = var.management_ui_namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = var.management_ui_role_label } }
      template = {
        metadata = { labels = { role = var.management_ui_role_label } }
        spec = {
          containers = [{
            name            = var.management_ui_name
            image           = var.collect_image
            imagePullPolicy = "Always"
            ports           = [{ containerPort = var.management_ui_container_port }]
            volumeMounts = [{
              name      = "probes-json"
              mountPath = "/star/probes.json"
              subPath   = "probes.json"
              readOnly  = true
            }]
          }]
          volumes = [{
            name = "probes-json"
            configMap = {
              name = "probes"
            }
          }]
        }
      }
    }
  })

  # The ConfigMap is mounted, so a Deployment created first sits with a container stuck on a missing volume
  # until the kubelet retries (rules.md D-1).
  depends_on = [kubectl_manifest.probes_config]
}
# ---------------------------------------------------------------------------------------------------
# The policies. Three per tenant, and the order they take effect in is the demonstration.
# ---------------------------------------------------------------------------------------------------
# Deny everything into the namespace. A NetworkPolicy with an empty podSelector and no ingress rules selects
# every pod and permits nothing, which is how "default deny" is expressed - there is no deny verb.
resource "kubectl_manifest" "default_deny" {
  for_each = var.apply_network_policies ? var.tenants : {}

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "default-deny"
      namespace = each.value
    }
    spec = {
      podSelector = {}
    }
  })

  depends_on = [kubectl_manifest.tenant_namespace]
}
# The exception for the management UI, by namespace label. This is why the UI's namespace carries a label at
# all: a policy cannot name a namespace, only select one.
resource "kubectl_manifest" "allow_ui" {
  for_each = var.apply_network_policies ? var.tenants : {}

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "allow-ui"
      namespace = each.value
    }
    spec = {
      podSelector = {}
      ingress = [{
        from = [{
          namespaceSelector = {
            matchLabels = { role = var.management_ui_role_label }
          }
        }]
      }]
    }
  })

  depends_on = [kubectl_manifest.default_deny]
}
# Frontend to backend, within the namespace. Note what it does not allow: the other tenant's frontend, because
# a podSelector is scoped to the policy's own namespace. That is the isolation - it comes from the absence of a
# namespaceSelector rather than from anything written down.
resource "kubectl_manifest" "backend_policy" {
  for_each = var.apply_network_policies ? var.tenants : {}

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "backend-policy"
      namespace = each.value
    }
    spec = {
      podSelector = {
        matchLabels = { role = "backend" }
      }
      ingress = [{
        from = [{
          podSelector = {
            matchLabels = { role = "frontend" }
          }
        }]
        ports = [{
          protocol = "TCP"
          port     = var.backend_port
        }]
      }]
    }
  })

  depends_on = [kubectl_manifest.default_deny]
}
