# The AWS Load Balancer Controller, with its IAM role and Pod Identity association, replacing the
# _monolithic bootstrap's "helm repo add / helm install" on the bastion (rules.md E-1).
#
# The role, the association and the Helm release stay in one module: the association names the
# service account the chart creates, and neither half is useful without the other (rules.md C-2).
#
# Pod Identity rather than IRSA, as the _monolithic template had it. The controller supports both -
# its own installation guide lists Pod Identity as "Option B: Recommended" - and here it is the
# better one for the same reason as the EBS CSI driver: the trust policy has nothing
# cluster-specific in it, so one role serves both clusters and the association decides which
# cluster may use it.
#
# The _monolithic template got one thing wrong that this module makes impossible. It ran the same
# helm install twice, once per cluster, and the second invocation still passed
# --set clusterName=<primary cluster>. A controller told the wrong cluster name tags its load
# balancers with elbv2.k8s.aws/cluster pointing at the other cluster, and then adopts and reconciles
# load balancers that belong to it (rules.md G-3). It produces no error - the controller starts
# normally. Here cluster_name is a required variable of a module instantiated once per cluster, so
# the two cannot be confused.
resource "aws_iam_role" "aws_load_balancer_controller" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole; Pod Identity attaches session tags naming the cluster,
      # namespace and service account, and the exchange fails without it.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name = "controller"
  role = aws_iam_role.aws_load_balancer_controller.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        # Carried over from the _monolithic template, which is far wider than the controller needs.
        # Upstream publishes a scoped policy at
        # https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
        # that conditions each action on a resource tag; swap this document for that one for
        # anything beyond a demo. Left as-is rather than narrowed by guesswork, because a
        # controller missing one permission fails by never reconciling rather than by saying so.
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState", "shield:DescribeProtection",
          "shield:CreateProtection", "shield:DeleteProtection",
        ]
        Resource = "*"
      },
    ]
  })
}
resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn
}
resource "helm_release" "aws_load_balancer_controller" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace
  # Blocks the apply until the controller's Deployment is Available, which is what the
  # "sleep 60" after the _monolithic helm install was standing in for.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "replicaCount"
      value = tostring(var.replica_count)
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    # Deliberately no serviceAccount.annotations here. With IRSA the chart needs the
    # eks.amazonaws.com/role-arn annotation; with Pod Identity the association above is the whole
    # binding and an annotation would be inert. Adding one anyway is harmless but misleading, since
    # it reads as if IRSA were in use.
    {
      # The shared backend security group - the k8s-traffic-<cluster>-<hash> group the controller
      # creates and attaches to every load balancer, then names as the source in the rules it adds
      # to nodes.
      #
      # Rendered as a bare boolean rather than a quoted string. The chart guards this flag with
      # {{ if kindIs "bool" .Values.enableBackendSecurityGroup }}, which is a type check, not a
      # truthiness check: a string "false" fails it, the flag is omitted from the Deployment
      # entirely, and the controller falls back to its own default of true - silently the opposite
      # of what was asked. helm --set infers a boolean from "false", so this entry must never carry
      # type = "string" (rules.md E-7/G-2).
      name  = "enableBackendSecurityGroup"
      value = tostring(var.enable_backend_security_group)
    },
    {
      # Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook, whose only job is to
      # make this controller the default for new Services of type LoadBalancer by injecting
      # spec.loadBalancerClass.
      #
      # It matters here because of what the demo Service is. The workload's Service is type
      # LoadBalancer and does not name the controller with an annotation, so with the webhook on it
      # is the webhook that hands the Service to this controller - which is convenient until the
      # controller pod is not Ready, at which point failurePolicy: Fail makes every Service creation
      # in the cluster fail (rules.md G-4). The workload names the controller explicitly instead, so
      # this can be off.
      name  = "enableServiceMutatorWebhook"
      value = tostring(var.enable_service_mutator_webhook)
    },
    ],
    var.additional_set_values,
  )

  # The policy has to be attached and the association has to exist before the controller's first
  # AWS call, and referencing neither from the release means nothing else orders them
  # (rules.md D-1). A controller that starts without credentials logs an AccessDenied loop and
  # keeps running, so the failure is recoverable but easy to miss.
  depends_on = [
    aws_iam_role_policy.aws_load_balancer_controller,
    aws_eks_pod_identity_association.aws_load_balancer_controller,
  ]
}
