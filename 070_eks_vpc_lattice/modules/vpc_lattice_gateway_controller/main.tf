# The AWS Gateway API Controller: what turns a Gateway into a VPC Lattice service network and an
# HTTPRoute into a Lattice service with target groups pointing at pods.
#
# IAM role, Pod Identity association and Helm release in one module, because none of the three stands
# alone: the association names the role and the service account the chart creates, and the chart is
# useless without the credentials the association provides (rules.md C-2).
#
# The _monolithic template installed the chart from user data, which meant a "helm registry login"
# against public.ecr.aws first - a credential pipeline that had to succeed in a shell - and then left
# the release out of state. The IAM role and the association it did create in Terraform, so the halves
# lived in different places (rules.md E-1).
resource "aws_iam_role" "gateway_api_controller" {
  name_prefix = "gateway-api-controller-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # Pod Identity rather than IRSA, as the _monolithic template had it: the trust policy names no
        # cluster and no OIDC issuer, so which service account may use the role is decided by the
        # association below.
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming the cluster,
      # namespace and service account, and without this action the exchange fails with an error about
      # tagging rather than about trust.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# The statements the controller's own documentation asks for, reproduced rather than widened
# (rules.md A-5). vpc-lattice:* is broad and it is what upstream specifies - the controller creates
# and deletes service networks, services, listeners, rules and target groups, and there is no
# narrower documented set.
resource "aws_iam_role_policy" "gateway_api_controller" {
  name = "gateway-api-controller"
  role = aws_iam_role.gateway_api_controller.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "vpc-lattice:*",
            # Read-only discovery: which VPC and subnets to associate, and which security groups to
            # put on a Lattice service network's VPC association.
            "ec2:DescribeVpcs",
            "ec2:DescribeSubnets",
            "ec2:DescribeTags",
            "ec2:DescribeSecurityGroups",
            # Access-log delivery to CloudWatch Logs, Firehose or S3, which a Lattice service network
            # can be configured with. Nothing here turns it on; the permissions are upstream's set.
            "logs:CreateLogDelivery",
            "logs:GetLogDelivery",
            "logs:UpdateLogDelivery",
            "logs:DeleteLogDelivery",
            "logs:ListLogDeliveries",
            "logs:DescribeLogGroups",
            "logs:PutResourcePolicy",
            "logs:DescribeResourcePolicies",
            "firehose:TagDeliveryStream",
            "s3:GetBucketPolicy",
            "s3:PutBucketPolicy",
            # How the controller finds the Lattice resources belonging to this cluster again after a
            # restart: it tags them and looks them up by tag rather than keeping local state.
            "tag:GetResources",
            "tag:TagResources",
            "tag:UntagResources",
          ]
          Resource = "*"
        },
        {
          # Scoped to the one service-linked role each, unlike the blanket iam:CreateServiceLinkedRole
          # that a policy like this often ends up with.
          Effect   = "Allow"
          Action   = "iam:CreateServiceLinkedRole"
          Resource = "arn:aws:iam::*:role/aws-service-role/vpc-lattice.amazonaws.com/AWSServiceRoleForVpcLattice"
          Condition = {
            StringLike = {
              "iam:AWSServiceName" = "vpc-lattice.amazonaws.com"
            }
          }
        },
        {
          Effect   = "Allow"
          Action   = "iam:CreateServiceLinkedRole"
          Resource = "arn:aws:iam::*:role/aws-service-role/delivery.logs.amazonaws.com/AWSServiceRoleForLogDelivery"
          Condition = {
            StringLike = {
              "iam:AWSServiceName" = "delivery.logs.amazonaws.com"
            }
          }
        },
      ],
      var.iam_policy_statements_extra,
    )
  })
}
# What makes the role usable by the controller's pod. The service account is created by the chart, so
# this association names a service account that does not exist yet - which is allowed: EKS resolves it
# when a pod using that account starts.
resource "aws_eks_pod_identity_association" "gateway_api_controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.gateway_api_controller.arn
}
resource "helm_release" "gateway_api_controller" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the controller is Available. That matters for what comes next: a Gateway
  # applied before the controller is running sits with no address and no events, which reads exactly
  # like a Gateway the controller has rejected.
  wait    = true
  timeout = var.timeout_seconds

  set = [
    {
      name  = "awsRegion"
      value = var.aws_region
    },
    {
      name  = "awsAccountId"
      value = var.aws_account_id
      # An account ID is twelve digits, which helm's --set would otherwise infer as a number and
      # render in scientific notation - the chart then builds ARNs containing "1.2345678901e+11"
      # (rules.md E-7).
      type = "string"
    },
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "clusterVpcId"
      value = var.cluster_vpc_id
    },
    {
      # The service network the controller creates and associates this VPC with. It has to match the
      # Gateway's name, because that is how the controller pairs them.
      name  = "defaultServiceNetwork"
      value = var.default_service_network
    },
    {
      name  = "webhookEnabled"
      value = tostring(var.webhook_enabled)
    },
  ]

  # The role has to carry its policy and the association has to exist before the controller's first
  # Lattice call, and referencing neither from the release means nothing else orders them
  # (rules.md D-1). A controller that starts without them logs AccessDenied and keeps retrying, so the
  # release still reports success.
  depends_on = [
    aws_iam_role_policy.gateway_api_controller,
    aws_eks_pod_identity_association.gateway_api_controller,
  ]
}
