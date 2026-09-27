output "own_registry" {
  value       = local.own_registry
  description = "This account's ECR registry hostname. Every image the private cluster runs is pulled from here, because it is the only registry the endpoints can reach - so callers build image references from this rather than each assembling the same account and region string (rules.md B-5)"
}
output "eks_cache_prefix" {
  value       = aws_ecr_pull_through_cache_rule.eks_registry.ecr_repository_prefix
  description = "Repository prefix caching the regional EKS registry. An addon image is referenced as <own_registry>/<this prefix>/<upstream path>"
}
output "public_cache_prefix" {
  value       = var.create_public_cache ? aws_ecr_pull_through_cache_rule.public_registry[0].ecr_repository_prefix : null
  description = "Repository prefix caching ECR Public, or null when that rule was not created"
}
output "eks_image_prefix" {
  value       = "${local.own_registry}/${aws_ecr_pull_through_cache_rule.eks_registry.ecr_repository_prefix}"
  description = "Full prefix for an image cached from the regional EKS registry, ready to have an upstream path appended. Assembled here so a manifest never rebuilds it (rules.md B-5)"
}
output "public_image_prefix" {
  value       = var.create_public_cache ? "${local.own_registry}/${aws_ecr_pull_through_cache_rule.public_registry[0].ecr_repository_prefix}" : null
  description = "Full prefix for an image cached from ECR Public, ready to have an upstream path appended"
}
output "upstream_eks_registry" {
  value       = local.eks_registry
  description = "The regional EKS registry this cache reads from, re-exposed because the account ID is region-specific and a wrong one produces a rule that silently resolves to nothing (rules.md B-5)"
}
output "cache_rules_check_command" {
  value       = "aws ecr describe-pull-through-cache-rules --query 'pullThroughCacheRules[].[ecrRepositoryPrefix,upstreamRegistryUrl]' --output table"
  description = "Command listing the cache rules. Worth checking when a pod stays in ImagePullBackOff: on a cluster with no internet route, a missing or misprefixed rule is the usual cause"
}
output "pull_policy_arn" {
  value       = aws_iam_policy.cache_pull.arn
  description = "ARN of the policy a pulling principal needs for the cache to materialise on first pull. Handed to the caller as an ARN so this module never learns who pulls (rules.md B-6); the node role is what needs it, because the kubelet makes the request"
}
output "cache_repositories_check_command" {
  value       = "aws ecr describe-repositories --query 'repositories[].repositoryName' --output table"
  description = "Command listing the repositories the cache has materialised. An empty list while pods sit in ImagePullBackOff means the pulling principal lacks ecr:CreateRepository and ecr:BatchImportUpstreamImage, which ECR reports as \"not found\" rather than as a permission error"
}
