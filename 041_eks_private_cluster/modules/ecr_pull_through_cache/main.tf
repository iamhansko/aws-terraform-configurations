data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  registry_region = coalesce(var.eks_registry_region, data.aws_region.current.region)
  eks_registry    = "${var.eks_registry_account_id}.dkr.ecr.${local.registry_region}.amazonaws.com"
  # The prefixes this module actually created, used to scope the pull policy below.
  cache_prefixes = compact([
    var.eks_cache_prefix,
    var.create_public_cache ? var.public_cache_prefix : null,
  ])
  # Where every image in this cluster is pulled from. Exposed as an output so
  # manifests name it from one definition rather than each rebuilding the same
  # account/region string (rules.md B-5).
  own_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
}
# Pull-through cache is what makes an egress-less cluster able to run anything. The
# nodes can reach ECR in this account through the ecr.api/ecr.dkr endpoints, and
# nothing else - so an image referenced as public.ecr.aws/... or as the regional EKS
# registry cannot be pulled at all. These rules make ECR fetch it on first request
# and serve it from a repository in this account, which the endpoints can reach.
#
# The role and the rules are one module: the rule cannot function without a role
# that can pull from the upstream registry, and the role has no use otherwise
# (rules.md C-2).
resource "aws_iam_role" "pull_through_cache" {
  name_prefix = var.role_name_prefix

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["pullthroughcache.ecr.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
      # Confused-deputy guard: only this account's pull-through cache may assume the
      # role, rather than any account's.
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "pull_through_cache" {
  name = "EcrPullThroughCachePolicy"
  role = aws_iam_role.pull_through_cache.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PullFromUpstreamEksRegistry"
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      # The upstream registry this rule reads from. Not scoped to a repository
      # because the cache decides which repository to fetch on demand, and the
      # image path is not known until something asks for it.
      Resource = "*"
    }]
  })
}
# The regional EKS registry, which is where addon images like coredns come from.
# Reached through a role because it is a private registry in someone else's
# account.
resource "aws_ecr_pull_through_cache_rule" "eks_registry" {
  ecr_repository_prefix      = var.eks_cache_prefix
  upstream_registry_url      = local.eks_registry
  upstream_repository_prefix = "ROOT"
  custom_role_arn            = aws_iam_role.pull_through_cache.arn

  # ECR validates the role when the rule is created, and referencing the role's ARN
  # alone does not order this after the inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.pull_through_cache]
}
# ECR Public serves anonymous pulls, so this rule needs no role at all.
resource "aws_ecr_pull_through_cache_rule" "public_registry" {
  count = var.create_public_cache ? 1 : 0

  ecr_repository_prefix      = var.public_cache_prefix
  upstream_registry_url      = "public.ecr.aws"
  upstream_repository_prefix = "ROOT"
}
# What a *pulling* principal needs, which is a different thing from the role above.
# That role is what ECR assumes to read the upstream registry; this policy is for
# whoever asks for the image - here the kubelet, using the node role.
#
# A cache rule does not pre-create anything. The repository holding the cached image
# is created by the first pull that asks for it, so that pull is not a plain read:
# ECR has to create the repository and import the upstream image, and the requesting
# principal must be allowed to do both (ecr:CreateRepository is required "if the
# repository storing the cached images doesn't already exist", ecr:BatchImportUpstreamImage
# to "retrieve the external image and import it to your private registry").
#
# AmazonEC2ContainerRegistryReadOnly grants neither. A node role carrying only that
# gets its pull refused in the most misleading way available - the repository does not
# exist, so ECR answers "not found":
#
#   Failed to pull image ".../ecr-public/eks/aws-load-balancer-controller:v2.14.0":
#   failed to resolve reference ...: not found
#
# which reads as a wrong image path or a missing upstream tag rather than as a missing
# permission. `aws ecr describe-repositories` returning an empty list while pods sit in
# ImagePullBackOff is the tell.
resource "aws_iam_policy" "cache_pull" {
  name_prefix = var.pull_policy_name_prefix
  description = "Lets a principal materialise this account's pull-through cache repositories on first pull"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "MaterialisePullThroughCacheRepositories"
      Effect = "Allow"
      Action = [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository",
      ]
      # Scoped to the prefixes this module created rather than "*". CreateRepository
      # unscoped would let every node create any repository in the account, and these
      # two actions are never needed outside the cache's own namespaces.
      Resource = [
        for prefix in local.cache_prefixes :
        "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${prefix}/*"
      ]
    }]
  })
}
