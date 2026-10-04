# The IRSA role for the AWS Load Balancer Controller, and only the role.
#
# Everywhere else in this repository this module also owns the controller's helm_release, because the release
# has to point the service account at this role and neither half is useful alone (rules.md C-2). This project
# splits them, and the reason is the cluster's API server endpoint: it is private, so a helm provider running
# on the machine that executes terraform apply cannot reach it. The chart is installed instead by an SSM
# Association on the workbench, which is inside the VPC (rules.md E-9).
#
# It follows that this module declares no helm provider. Declaring one would make Terraform demand a helm
# provider configuration in a root module that deliberately has none - which is also why the chart-only
# variables (version, values, timeouts) live in the root rather than here.
#
# What the split costs: the release is not in Terraform state, so nothing detects it being removed or upgraded
# by hand, and this role's ARN reaches the chart as a string interpolated into a shell command rather than as a
# resource reference. The role itself is still a first-class resource, which is the half that matters for IAM.
resource "aws_iam_role" "aws_load_balancer_controller_iam_role" {
  name_prefix = var.role_name_prefix
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
          # Both conditions, and the :aud one is not decoration: without it the trust policy accepts any token
          # the cluster's OIDC provider issues for that subject, including one minted for a different audience.
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# The upstream policy, carried in as a file rather than retyped.
#
# This is the one piece of IAM the _monolithic template did not have in any form. Its bootstrap installed the
# chart with nothing but --set serviceAccount.name, so the service account carried no role annotation, the
# controller fell back to the node instance role through IMDS, and every AWS call it made was denied - which
# shows up only in the controller's log, long after a successful stack create.
#
# rules.md A-5 is about exactly this gap, and about the shortcut it invites: with no policy to carry over, the
# easy answer is AdministratorAccess or ec2:*/elasticloadbalancing:*. Instead this is
# docs/install/iam_policy.json from the controller release this project pins, byte for byte, so the
# permissions are the scoped ones upstream publishes - tag-conditioned on
# elbv2.k8s.aws/cluster for the mutating calls - and re-checking them against a new release is one diff:
#
#   diff <(curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v<ver>/docs/install/iam_policy.json) \
#        modules/aws_load_balancer_controller_iam_role/iam_policy.json
#
# jsondecode/jsonencode rather than file() alone, for two reasons: it parses the document at plan time, so a
# truncated or malformed file fails before apply, and it strips the formatting whitespace that would otherwise
# count toward the 10,240-character inline policy limit.
locals {
  iam_policy_document = jsonencode(jsondecode(file("${path.module}/iam_policy.json")))
}
# Inline on the role rather than a standalone aws_iam_policy, so the permissions are deleted with the role
# instead of lingering as an account-wide managed policy that a second copy of this project would collide with
# on a fixed name.
resource "aws_iam_role_policy" "aws_load_balancer_controller_iam_role" {
  role   = aws_iam_role.aws_load_balancer_controller_iam_role.name
  policy = local.iam_policy_document
}
