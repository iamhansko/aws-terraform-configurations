# Replaces the _monolithic bootstrap sequence, which ran
# The IRSA role for the AWS Load Balancer Controller, and only the role.
#
# Everywhere else in this repository this module also owns the controller's
# helm_release, because the release has to annotate the service account with this
# role's ARN and neither half is useful alone (rules.md C-2). This project splits
# them, and the reason is the cluster's API server endpoint: it is private, so a
# helm provider running on the machine that executes terraform apply cannot reach
# it. The chart is installed instead by an SSM Association on the bastion, which
# is inside the VPC - a deliberate departure from rules.md E-1, taken to avoid
# exposing the API server publicly just so Terraform could reach it.
#
# What that costs: the release is not in Terraform state, so nothing detects it
# being removed or upgraded by hand, and the role's ARN reaches the chart as a
# string interpolated into a shell command rather than as a resource reference.
# The role itself is still a first-class resource, which is the half that matters
# for IAM - the _monolithic template built it with
# "eksctl create iamserviceaccount", producing a CloudFormation stack Terraform
# knew nothing about.
#
# It follows that this module declares no helm provider. Declaring one would make
# Terraform demand a helm provider configuration in a root module that
# deliberately has none.
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
