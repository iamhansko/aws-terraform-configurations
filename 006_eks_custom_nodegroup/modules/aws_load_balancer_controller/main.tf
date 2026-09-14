# Replaces the _monolithic bootstrap sequence, which ran
#   eksctl create iamserviceaccount --name aws-load-balancer-controller ...
#   helm repo add eks https://aws.github.io/eks-charts
#   helm install aws-load-balancer-controller eks/aws-load-balancer-controller
# from a shell on the bastion (rules.md #18). eksctl's iamserviceaccount step
# built a CloudFormation stack Terraform knew nothing about; here the IRSA role
# is a first-class resource in state.
#
# The IAM role and the Helm release stay in one module because helm_release
# references the role ARN directly and neither half is useful alone
# (rules.md #21). The cross-module rule about injecting ARNs through variables
# (rules.md #14/#15) applies between modules with different responsibilities,
# not within a single component.
resource "aws_iam_role" "aws_load_balancer_controller_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
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
    # The chart creates the service account itself and only needs the IRSA
    # annotation, so no separate "eksctl create iamserviceaccount" step.
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.aws_load_balancer_controller_iam_role.arn
    },
    ],
    var.additional_set_values,
  )

  # The role must already carry its inline policy before the controller starts
  # reconciling Ingresses, and referencing the role's ARN alone doesn't order
  # this release after the policy (rules.md #12).
  depends_on = [aws_iam_role_policy.aws_load_balancer_controller_iam_role]
}
