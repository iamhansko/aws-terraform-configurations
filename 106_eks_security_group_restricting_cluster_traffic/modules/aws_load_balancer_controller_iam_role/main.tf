# Replaces the _monolithic bootstrap sequence, which ran
# The AWS Load Balancer Controller's IAM role and its Pod Identity association -
# and only those. No Helm release here.
#
# Everywhere else in this repository this module also owns the controller's
# helm_release, because the two halves reference each other and neither is useful
# alone (rules.md C-2). This project splits them, and the reason is the cluster's
# API server endpoint: it is private, so a helm provider running on the machine
# that executes terraform apply cannot reach it. The chart is installed instead by
# an SSM Association on the bastion, which is inside the VPC - the one exception
# rules.md E-9 allows, taken so the API server does not have to be opened publicly
# just for Terraform to reach it.
#
# What that costs: the release is not in Terraform state, so nothing detects it
# being removed or upgraded by hand. The role is still a first-class resource,
# which is the half that matters for IAM.
#
# Pod Identity rather than IRSA, as the _monolithic template had it. It also means
# the chart install needs no serviceAccount annotation - with IRSA that annotation
# is a string the shell command has to get exactly right, and getting it wrong
# produces a controller that starts and then fails every AWS call.
#
# It follows that this module declares no helm provider. Declaring one would make
# Terraform demand a helm provider configuration in a root module that
# deliberately has none (rules.md E-9).
resource "aws_iam_role" "aws_load_balancer_controller_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # pods.eks.amazonaws.com, not the cluster's OIDC provider: EKS Pod Identity,
        # as the _monolithic template had it. The agent on the node exchanges the
        # service account's token for credentials from this role, and which service
        # account may do so is decided by the association below rather than by a
        # condition here.
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming
      # the cluster, namespace and service account, and without this action the
      # exchange fails with an error about tagging rather than about trust - which is
      # not where anyone looks first.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# What actually binds the role to a service account. Nothing in the trust policy
# above names the cluster, so without this the role is assumable by the Pod Identity
# service and by no particular pod.
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
