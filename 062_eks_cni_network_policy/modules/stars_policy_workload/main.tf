# The Calico "stars" demo: three probes that continuously poll each other, plus a
# management UI that draws the resulting graph. With no NetworkPolicy in place every
# arrow in that graph is green; applying the policies turns most of them red, which is
# the whole point of the demo.
#
# The _monolithic template built this by curling four manifests from a pinned
# eks-workshop commit and echoing two more into files, then running kubectl apply from
# an SSM Association. Here the same objects are declared as manifests (rules.md E-1),
# as HCL objects keeping the original camelCase field names rather than rewritten YAML
# (rules.md E-3), through alekc/kubectl so the cluster can be created in the same apply
# (rules.md E-2).
#
locals {
  # Every probe is started with the full list of URLs, so each one reports on all three
  # legs. Built once here because the same list goes into three containers, and a probe
  # pointed at a stale address reports a red arrow that looks like a policy blocking it.
  probe_urls = join(",", [
    "http://frontend.${var.stars_namespace}:${var.frontend_port}/status",
    "http://backend.${var.stars_namespace}:${var.backend_port}/status",
    "http://client.${var.client_namespace}:${var.client_port}/status",
  ])
  # The client probe only polls the two stars services - it is the thing being allowed
  # or denied, not a hop in the chain.
  client_probe_urls = join(",", [
    "http://frontend.${var.stars_namespace}:${var.frontend_port}/status",
    "http://backend.${var.stars_namespace}:${var.backend_port}/status",
  ])
}
resource "kubectl_manifest" "stars_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = var.stars_namespace }
  })
}
resource "kubectl_manifest" "client_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.client_namespace
      # The label the frontend policy's namespaceSelector matches on. Without it the
      # policy selects nothing and the client is denied even when it should be allowed.
      labels = { role = "client" }
    }
  })
}
resource "kubectl_manifest" "management_ui_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name   = var.management_ui_namespace
      labels = { role = "management-ui" }
    }
  })
}
resource "kubectl_manifest" "backend_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "backend"
      namespace = var.stars_namespace
    }
    spec = {
      ports    = [{ port = var.backend_port, targetPort = var.backend_port }]
      selector = { role = "backend" }
    }
  })

  # metadata.namespace is a literal string rather than an attribute reference, so
  # nothing else orders this after the namespace exists (rules.md D-1/E-2).
  depends_on = [kubectl_manifest.stars_namespace]
}
resource "kubectl_manifest" "backend_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "backend"
      namespace = var.stars_namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = "backend" } }
      template = {
        metadata = { labels = { role = "backend" } }
        spec = {
          containers = [{
            name            = "backend"
            image           = var.probe_image
            imagePullPolicy = "Always"
            command         = ["probe", "--http-port=${var.backend_port}", "--urls=${local.probe_urls}"]
            ports           = [{ containerPort = var.backend_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.stars_namespace]
}
resource "kubectl_manifest" "frontend_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "frontend"
      namespace = var.stars_namespace
    }
    spec = {
      ports    = [{ port = var.frontend_port, targetPort = var.frontend_port }]
      selector = { role = "frontend" }
    }
  })

  depends_on = [kubectl_manifest.stars_namespace]
}
resource "kubectl_manifest" "frontend_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "frontend"
      namespace = var.stars_namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = "frontend" } }
      template = {
        metadata = { labels = { role = "frontend" } }
        spec = {
          containers = [{
            name            = "frontend"
            image           = var.probe_image
            imagePullPolicy = "Always"
            command         = ["probe", "--http-port=${var.frontend_port}", "--urls=${local.probe_urls}"]
            ports           = [{ containerPort = var.frontend_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.stars_namespace]
}
resource "kubectl_manifest" "client_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "client"
      namespace = var.client_namespace
    }
    spec = {
      ports    = [{ port = var.client_port, targetPort = var.client_port }]
      selector = { role = "client" }
    }
  })

  depends_on = [kubectl_manifest.client_namespace]
}
resource "kubectl_manifest" "client_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "client"
      namespace = var.client_namespace
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { role = "client" } }
      template = {
        metadata = { labels = { role = "client" } }
        spec = {
          containers = [{
            name            = "client"
            image           = var.probe_image
            imagePullPolicy = "Always"
            command         = ["probe", "--urls=${local.client_probe_urls}"]
            ports           = [{ containerPort = var.client_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.client_namespace]
}
# The only object here the AWS Load Balancer Controller reconciles. Its Service name and
# namespace are what the pre-created load balancer's service.k8s.aws/stack tag has to
# match for adoption (rules.md G-3).
resource "kubectl_manifest" "management_ui_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.management_ui_name
      namespace = var.management_ui_namespace
      annotations = {
        # The switch the _monolithic template omitted, and the one that decides which
        # controller handles this Service at all. Without it the in-tree AWS cloud
        # provider claims it and builds a Classic Load Balancer, silently ignoring every
        # annotation below - so the scheme, the target type and the security groups have
        # no effect and the pre-created NLB is never adopted, because the AWS Load
        # Balancer Controller never looks at the Service (rules.md G-1).
        "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
        # nlb-target-type, not target-type: the Service spelling carries the nlb- prefix
        # while the Ingress spelling does not, and the wrong one is ignored rather than
        # rejected (rules.md G-1).
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = var.scheme
        # Naming the groups here is what makes the controller keep them on the load
        # balancer. An NLB can only be given security groups at creation, so the
        # pre-created load balancer is built with this same list (rules.md G-3).
        "service.beta.kubernetes.io/aws-load-balancer-security-groups" = join(",", var.frontend_security_group_ids)
      }
    }
    spec = {
      type     = "LoadBalancer"
      ports    = [{ port = var.management_ui_service_port, targetPort = var.management_ui_container_port }]
      selector = { role = "management-ui" }
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
      selector = { matchLabels = { role = "management-ui" } }
      template = {
        metadata = { labels = { role = "management-ui" } }
        spec = {
          containers = [{
            name            = var.management_ui_name
            image           = var.collect_image
            imagePullPolicy = "Always"
            ports           = [{ containerPort = var.management_ui_container_port }]
          }]
        }
      }
    }
  })

  depends_on = [kubectl_manifest.management_ui_namespace]
}
# --- The NetworkPolicy objects the demo is about ---
#
# Declared as resources rather than left as files for the user to apply, so they are in
# state, appear in plan, and are removed in the right order on destroy like everything
# else here (rules.md E-1/E-2). The _monolithic template curled three of them from a
# pinned eks-workshop commit, echoed two more into files, and left every one of them to
# be applied by hand.
#
# Walking the demo backwards is done with apply_network_policies rather than by deleting
# objects behind Terraform's back: setting it false removes all six and the graph goes
# fully green again (rules.md B-4). Deleting them with kubectl also works, but the next
# apply puts them back, which looks like the policies reappearing on their own.
#
# Enforcement is a separate switch. These objects are accepted by the API server whether
# or not the VPC CNI's network policy agent is running, so a graph that never changes
# means enableNetworkPolicy is off on the vpc-cni addon, not that these are missing
# (rules.md E-5).
locals {
  # default-deny goes into both demo namespaces. The upstream manifest carries no
  # namespace and is applied twice as "kubectl apply -n <ns> -f default-deny.yaml"; as
  # Terraform resources each instance names its own namespace instead. The keys are
  # static labels rather than the namespace values, so a renamed namespace changes the
  # rule's contents and not its resource address (rules.md B-8).
  default_deny_namespaces = {
    stars  = var.stars_namespace
    client = var.client_namespace
  }
}
# Every policy below repeats the same depends_on list. It cannot be hoisted into a local:
# depends_on only accepts direct references to resources and modules, not an expression
# that evaluates to them. The dependency is on the pods existing before the policies that
# select them - not required by Kubernetes, but it makes the end state of an apply match
# the order the demo describes.
# Step one of the demo: deny all ingress in both namespaces. On its own this also cuts the
# management UI off, so the graph goes dark until allow-ui lands below.
resource "kubectl_manifest" "default_deny" {
  for_each = var.apply_network_policies ? local.default_deny_namespaces : {}

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "default-deny"
      namespace = each.value
    }
    # An empty podSelector selects every pod in the namespace, and no ingress key at all
    # means nothing is allowed. "ingress = []" would mean the same thing to Kubernetes but
    # reads as an oversight, so it is left out as the upstream manifest does.
    spec = { podSelector = { matchLabels = {} } }
  })

  depends_on = [
    kubectl_manifest.stars_namespace,
    kubectl_manifest.client_namespace,
    kubectl_manifest.backend_deployment,
    kubectl_manifest.frontend_deployment,
    kubectl_manifest.client_deployment,
  ]
}
# Step two: let the management UI back in, so the graph renders again. Policies are
# additive - this one unions with default-deny rather than replacing it - which is why
# every probe-to-probe arrow stays red at this point.
resource "kubectl_manifest" "allow_ui_stars" {
  count = var.apply_network_policies ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "allow-ui"
      namespace = var.stars_namespace
    }
    spec = {
      podSelector = { matchLabels = {} }
      # Selects the namespace by label, not by name, so the management UI namespace has to
      # carry role=management-ui. It does, above - a namespace without that label makes
      # this policy match nothing and the graph stays dark.
      ingress = [{ from = [{ namespaceSelector = { matchLabels = { role = "management-ui" } } }] }]
    }
  })

  depends_on = [
    kubectl_manifest.stars_namespace,
    kubectl_manifest.client_namespace,
    kubectl_manifest.backend_deployment,
    kubectl_manifest.frontend_deployment,
    kubectl_manifest.client_deployment,
  ]
}
resource "kubectl_manifest" "allow_ui_client" {
  count = var.apply_network_policies ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "allow-ui"
      namespace = var.client_namespace
    }
    spec = {
      podSelector = { matchLabels = {} }
      ingress     = [{ from = [{ namespaceSelector = { matchLabels = { role = "management-ui" } } }] }]
    }
  })

  depends_on = [
    kubectl_manifest.stars_namespace,
    kubectl_manifest.client_namespace,
    kubectl_manifest.backend_deployment,
    kubectl_manifest.frontend_deployment,
    kubectl_manifest.client_deployment,
  ]
}
# Step three, first half: the backend accepts the frontend pod, and only on its own port.
resource "kubectl_manifest" "backend_policy" {
  count = var.apply_network_policies ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "backend-policy"
      namespace = var.stars_namespace
    }
    spec = {
      podSelector = { matchLabels = { role = "backend" } }
      ingress = [{
        # podSelector, not namespaceSelector: the frontend is in this same namespace, so
        # the match is on the pod label.
        from  = [{ podSelector = { matchLabels = { role = "frontend" } } }]
        ports = [{ protocol = "TCP", port = var.backend_port }]
      }]
    }
  })

  depends_on = [
    kubectl_manifest.stars_namespace,
    kubectl_manifest.client_namespace,
    kubectl_manifest.backend_deployment,
    kubectl_manifest.frontend_deployment,
    kubectl_manifest.client_deployment,
  ]
}
# Step three, second half: the frontend accepts the client namespace. namespaceSelector
# here rather than podSelector, because the client runs in a different namespace and a
# podSelector would only ever match pods in this one.
resource "kubectl_manifest" "frontend_policy" {
  count = var.apply_network_policies ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "NetworkPolicy"
    metadata = {
      name      = "frontend-policy"
      namespace = var.stars_namespace
    }
    spec = {
      podSelector = { matchLabels = { role = "frontend" } }
      ingress = [{
        from  = [{ namespaceSelector = { matchLabels = { role = "client" } } }]
        ports = [{ protocol = "TCP", port = var.frontend_port }]
      }]
    }
  })

  depends_on = [
    kubectl_manifest.stars_namespace,
    kubectl_manifest.client_namespace,
    kubectl_manifest.backend_deployment,
    kubectl_manifest.frontend_deployment,
    kubectl_manifest.client_deployment,
  ]
}
