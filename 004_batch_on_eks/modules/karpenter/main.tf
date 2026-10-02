resource "aws_iam_role" "karpenter_controller_iam_role" {
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

resource "aws_iam_role_policy_attachment" "karpenter_controller_iam_role" {
  for_each   = toset(var.controller_policy_arns)
  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = each.value
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
# Karpenter's published least-privilege controller policy, which the _monolithic template
# carried as an inline heredoc and which is reproduced here rather than replaced by
# AdministratorAccess.
#
# Worth spelling out why it is this long. Karpenter launches and terminates instances, builds
# launch templates and creates instance profiles, so a policy that is merely "EC2 access" would
# be close to administrative over the account's compute. Almost every statement is therefore
# scoped by a tag condition - kubernetes.io/cluster/<name> = owned, plus a karpenter.sh/nodepool
# or karpenter.k8s.aws/ec2nodeclass tag - so the controller can only act on the resources it
# created for this cluster. The three statements without a tag condition are read-only
# (describe, pricing, ssm:GetParameter for the AMI aliases) or pinned to one ARN
# (eks:DescribeCluster, iam:PassRole on the node role).
resource "aws_iam_policy" "karpenter_controller_policy" {
  count = var.create_controller_policy ? 1 : 0

  # This module hardcodes the release name rather than taking it as a variable, so the prefix is
  # derived from the service account instead - it identifies the same component either way.
  name_prefix = "${var.service_account_name}-controller-"
  description = "Least-privilege policy for the Karpenter controller on ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:subnet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
        ]
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
            "ec2:CreateAction"                                         = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*"
        Action   = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
          StringEqualsIfExists = {
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.region}:*:launch-template/*",
        ]
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.region
          }
        }
      },
      {
        # How the EC2NodeClass alias (al2023@latest) is resolved to an AMI ID.
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        # Consolidation compares instance prices, so the controller reads the pricing API.
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Resource = aws_iam_role.karpenter_node_iam_role.arn
        Action   = "iam:PassRole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
          }
        }
      },
      {
        # Karpenter builds the instance profile itself from the role name in
        # EC2NodeClass.spec.role, which is why these four statements exist at all - there is no
        # aws_iam_instance_profile in this module.
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = ["iam:CreateInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"             = data.aws_region.current.region
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = ["iam:TagInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = data.aws_region.current.region
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"  = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                       = var.cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"              = data.aws_region.current.region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = data.aws_region.current.region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = "iam:GetInstanceProfile"
      },
      {
        # Unscoped deliberately, and the only statement in this policy that has to be. The
        # instanceprofile.garbagecollection controller lists the account's instance profiles to
        # find the ones whose EC2NodeClass is gone, and iam:ListInstanceProfiles takes no
        # resource - so the instance-profile/* ARN above does not authorise it, and adding the
        # action to that statement instead leaves the call denied.
        #
        # Without this the controller returns AccessDenied on every reconcile and orphaned
        # instance profiles are never collected. Provisioning keeps working, so nothing surfaces
        # it except the controller log:
        #
        #   controller: instanceprofile.garbagecollection ... api error AccessDenied: ... not
        #     authorized to perform: iam:ListInstanceProfiles
        #
        # Carried by the upstream cloudformation.yaml for this chart version as
        # AllowUnscopedInstanceProfileListAction.
        Sid      = "AllowUnscopedInstanceProfileListAction"
        Effect   = "Allow"
        Resource = "*"
        Action   = "iam:ListInstanceProfiles"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
        Action   = "eks:DescribeCluster"
      },
      ],
      # Only present when an interruption queue was given, and scoped to that one queue. Without
      # it the controller still provisions nodes; it just never learns a node is about to go
      # away, which is the difference this project is built around.
      var.interruption_queue_arn == null ? [] : [{
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = var.interruption_queue_arn
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      }],
    )
  })
}
resource "aws_iam_role_policy_attachment" "karpenter_controller_policy" {
  count = var.create_controller_policy ? 1 : 0

  role       = aws_iam_role.karpenter_controller_iam_role.name
  policy_arn = aws_iam_policy.karpenter_controller_policy[0].arn
}
# The role Karpenter-provisioned instances run as. Karpenter builds the instance
# profile itself from the role name in EC2NodeClass.spec.role, so no
# aws_iam_instance_profile here.

resource "aws_iam_role" "karpenter_node_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_iam_role" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.karpenter_node_iam_role.name
  policy_arn = each.value
}

resource "aws_eks_access_entry" "karpenter_node_iam_access_entry" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node_iam_role.arn
  type          = "EC2_LINUX"
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  wait             = true

  set = [
    {
      name  = "settings.clusterName"
      value = var.cluster_name
    },
    {
      name  = "controller.resources.requests.cpu"
      value = var.controller_cpu_request
    },
    {
      name  = "controller.resources.requests.memory"
      value = var.controller_memory_request
    },
    {
      name  = "controller.resources.limits.cpu"
      value = var.controller_cpu_limit
    },
    {
      name  = "controller.resources.limits.memory"
      value = var.controller_memory_limit
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.karpenter_controller_iam_role.arn
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_controller_policy,
    aws_iam_role_policy_attachment.karpenter_controller_iam_role,
    aws_eks_access_entry.karpenter_node_iam_access_entry,
  ]
}
