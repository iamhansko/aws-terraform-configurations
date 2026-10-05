# Replaces the _monolithic template's helm install, which ran from the workbench's
# user data - after an "exec bash" line that replaced the shell, so on a real boot
# the controller was never installed at all (rules.md E-1/H-1).
#
# The role, the Pod Identity association and the Helm release stay in one module
# because none of the three is useful alone: the association binds the role to a
# service account the chart creates, and the chart is useless without it
# (rules.md C-2). The cross-module rule about injecting ARNs through variables
# (rules.md C-1/B-6) applies between modules with different responsibilities, not
# within a single component.
#
# Pod Identity rather than IRSA, which is what this project's _monolithic template
# used and what most of the others here use. The difference is worth stating:
#
#   IRSA         - the role trusts the cluster's OIDC provider, and the service
#                  account carries an eks.amazonaws.com/role-arn annotation. The
#                  role's trust policy names the namespace and service account.
#   Pod Identity - the role trusts pods.eks.amazonaws.com, and a separate
#                  association resource names the namespace and service account.
#                  No annotation, and no OIDC provider needed.
#
# Pod Identity moves the binding out of the trust policy and into its own
# resource, which makes it visible in plan and removable without editing IAM. It
# needs the eks-pod-identity-agent addon on the cluster, which the caller
# installs.
resource "aws_iam_role" "aws_load_balancer_controller_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      # Both actions, and sts:TagSession is not optional: the Pod Identity agent
      # tags the session with the cluster, namespace and service account, and a
      # role that does not allow tagging cannot be assumed at all - which appears
      # as an AccessDenied in the pod rather than anywhere in IAM.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# What binds the role to the service account the chart creates. This is the half
# that replaces IRSA's annotation, and it is a resource rather than a string - so
# a plan shows the binding, and removing it is a delete rather than an edit.
resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.aws_load_balancer_controller_iam_role.arn
}
# Inline rather than a standalone aws_iam_policy so the permissions are deleted
# with the role instead of lingering as an account-wide managed policy that a
# second copy of this project would collide with on its fixed name
# (the _monolithic template hardcoded name = "AWSLoadBalancerControllerIAMPolicy").
resource "aws_iam_role_policy" "aws_load_balancer_controller_iam_role" {
  role = aws_iam_role.aws_load_balancer_controller_iam_role.name
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
        # Carried over verbatim from the _monolithic template. This is far
        # wider than the controller needs (the upstream policy at
        # https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
        # scopes each action and adds resource tag conditions). Swap this
        # inline document for the upstream one for anything beyond a demo.
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
resource "helm_release" "aws_load_balancer_controller" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace
  # wait = true makes the apply block until the controller's Deployment is
  # Available, which is what the "kubectl rollout status -n kube-system deploy
  # aws-load-balancer-controller" line in the _monolithic userdata was for.
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
    # The chart creates the service account, and with Pod Identity that is all it
    # needs - there is no role-arn annotation, because the association above
    # carries the binding instead. An annotation left here would be harmless but
    # misleading: it would suggest IRSA was in use.
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    # Controls the shared backend security group (the k8s-traffic-<cluster>-<hash>
    # group the controller creates and attaches to every load balancer, then uses
    # as the traffic source in the rules it adds to nodes).
    #
    # Rendered as a bare boolean rather than a quoted string. The chart guards
    # this flag with {{ if kindIs "bool" .Values.enableBackendSecurityGroup }},
    # which is a type check, not a truthiness check: a string "false" fails it,
    # the flag is omitted from the Deployment entirely, and the controller falls
    # back to its own default of true - silently the opposite of what was asked.
    # helm --set infers a boolean from "false", so this entry must never carry
    # type = "string" (rules.md E-7/G-2).
    {
      name  = "enableBackendSecurityGroup"
      value = tostring(var.enable_backend_security_group)
    },
    # Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook, whose
    # only job is to make this controller the default for new Services of type
    # LoadBalancer by injecting spec.loadBalancerClass.
    #
    # It is worth turning off because of how widely it reaches. The chart gives it
    # failurePolicy: Fail and no namespaceSelector at all, and its rule matches every
    # v1/services CREATE in the cluster - the sole exclusion is an objectSelector for
    # the controller's own app.kubernetes.io/name label, which is just how the chart
    # avoids deadlocking on its own Service. So for as long as the controller has no
    # Ready pod backing aws-load-balancer-webhook-service, the API server rejects
    # every Service created anywhere:
    #
    #   Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws":
    #   failed to call webhook: Post "https://aws-load-balancer-webhook-service
    #   .kube-system.svc:443/mutate-v1-service?timeout=10s": no endpoints available
    #   for service "aws-load-balancer-webhook-service"
    #
    # That window is not an edge case: the webhook object is registered during this
    # release's install, well before its Deployment is Available, and it reopens on
    # every controller rollout or node replacement. Any other chart installing
    # Services at that moment fails, and the failure names this webhook rather than
    # anything the caller did.
    #
    # Rendered as a bare boolean, never type = "string". The chart's guard is a plain
    # {{- if .Values.enableServiceMutatorWebhook }}, and a non-empty string is truthy
    # in a Go template - so "false" as a string would leave the webhook installed
    # while appearing to disable it (rules.md E-7).
    {
      name  = "enableServiceMutatorWebhook"
      value = tostring(var.enable_service_mutator_webhook)
    },
    ],
    var.additional_set_values,
  )

  # The role must already carry its inline policy before the controller starts
  # reconciling Ingresses, and referencing the role's ARN alone doesn't order
  # this release after the policy (rules.md D-1).
  # The policy and the Pod Identity association both have to exist before the
  # controller pod starts, and neither is implied by the role ARN reference above
  # (rules.md D-1). A controller that starts before the association exists gets no
  # credentials and reports AccessDenied against every AWS call it makes.
  depends_on = [
    aws_iam_role_policy.aws_load_balancer_controller_iam_role,
    aws_eks_pod_identity_association.aws_load_balancer_controller,
  ]
}
