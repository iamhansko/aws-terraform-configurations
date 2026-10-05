# The MCP server: an IAM role the pod assumes through EKS Pod Identity, and the four
# Kubernetes objects that run and publish it.
#
# The role and the workload are one module because the binding between them is the whole
# point: the association names this namespace and this service account, and the service
# account is created here. Splitting them would put a Kubernetes object name in an IAM
# module (rules.md C-2).
#
# What the role is for is worth stating plainly: awslabs.eks-mcp-server runs with
# --allow-write and --allow-sensitive-data-access, so whatever this role can do, a language
# model driving the MCP endpoint can do.
resource "aws_iam_role" "mcp_server" {
  name_prefix = "${substr(var.name, 0, 32)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # pods.eks.amazonaws.com: EKS Pod Identity, as the _monolithic template had it. The
        # agent on the node exchanges the service account's token for credentials from this
        # role, and which service account may do so is decided by the association below
        # rather than by a condition here.
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming the
      # cluster, namespace and service account, and without this action the exchange fails
      # with an error about tagging rather than about trust.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mcp_server" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.mcp_server.name
  policy_arn = each.value
}

resource "aws_eks_pod_identity_association" "mcp_server" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.mcp_server.arn
}

# The service account the association binds to. No eks.amazonaws.com/role-arn annotation:
# that is the IRSA form, and Pod Identity needs none - which is one fewer string to get
# exactly right.
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.service_account_name
      namespace = var.namespace
    }
  })
}

resource "kubectl_manifest" "deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.name
      namespace = var.namespace
      labels    = { app = var.name }
    }
    spec = {
      replicas = var.replicas
      selector = { matchLabels = { app = var.name } }
      template = {
        metadata = { labels = { app = var.name } }
        spec = {
          serviceAccountName = var.service_account_name
          containers = [{
            name  = "mcp-server"
            image = var.image
            # Always, as the _monolithic template set it, and it is the right choice for a
            # mutable :latest tag - without it a restarted pod keeps whatever the node
            # already cached, so a rebuilt image never actually rolls out.
            imagePullPolicy = var.image_pull_policy
            ports           = [{ containerPort = var.container_port }]
            readinessProbe = {
              httpGet = {
                path = var.health_check_path
                port = var.container_port
              }
              initialDelaySeconds = 10
              periodSeconds       = 15
            }
            livenessProbe = {
              httpGet = {
                path = var.health_check_path
                port = var.container_port
              }
              initialDelaySeconds = 15
              periodSeconds       = 30
            }
          }]
        }
      }
    }
  })

  # True is the provider's default, and it is set here anyway because the default is invisible and
  # its failure message does not mention rollouts. With it on, the apply blocks until this
  # Deployment reports an available replica - which is what makes "terraform apply succeeded" mean
  # the server is actually serving, rather than that an object was accepted.
  #
  # What it looks like when the rollout cannot complete - a missing image, a crash loop, a probe
  # that never passes - is not obvious:
  #
  #   Error: default/eks-mcp-server failed to fetch resource from kubernetes:
  #   client rate limiter Wait returned an error: context deadline exceeded
  #
  # That is the provider polling until the resource timeout expires, surfacing whichever call was
  # in flight. It reads like a rate limit or a network problem and is neither. Read the pod before
  # the provider: `kubectl -n <ns> get pods` and its events say which of the three it was.
  wait_for_rollout = true

  timeouts {
    # Long enough for a node to pull the image on a cold cache, short enough that a rollout which
    # is never going to succeed fails inside the apply rather than at the end of the provider's
    # own default.
    create = var.rollout_timeout
    update = var.rollout_timeout
  }

  # serviceAccountName is a literal string, so nothing else orders this after the account
  # (rules.md E-2). A pod created before its service account exists is not rejected - it is
  # admitted and then denied its Pod Identity credentials.
  depends_on = [kubectl_manifest.service_account]
}

resource "kubectl_manifest" "service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.service_name
      namespace = var.namespace
    }
    spec = {
      # ClusterIP: the ALB the Ingress produces is the public path, and with
      # target-type ip it sends traffic straight to pod addresses - so this Service is a
      # name and a selector rather than a data path.
      type     = "ClusterIP"
      selector = { app = var.name }
      ports = [{
        port       = var.container_port
        targetPort = var.container_port
      }]
    }
  })

  depends_on = [kubectl_manifest.deployment]
}

resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name        = var.ingress_name
      namespace   = var.namespace
      annotations = var.ingress_annotations
    }
    spec = {
      # Without this the Ingress is created and no controller ever looks at it
      # (rules.md G-1).
      ingressClassName = var.ingress_class_name
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = var.service_name
                port = { number = var.container_port }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.service]
}
