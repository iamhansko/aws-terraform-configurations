variable "eks_registry_account_id" {
  type        = string
  description = "Account ID of the regional Amazon EKS container registry the private cache pulls from. This is region-specific: AWS publishes a different account per region, and the wrong one produces a cache rule that resolves to nothing. 602401143452 covers most commercial regions including ap-northeast-2; check the EKS 'add-on images' documentation for yours"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.eks_registry_account_id))
    error_message = "eks_registry_account_id must be a 12-digit AWS account ID."
  }
}
variable "eks_registry_region" {
  type        = string
  default     = null
  description = "Region of the regional EKS registry. Null means the caller's own region, which is the normal case; set it only to pull from another region's registry"

  validation {
    condition     = var.eks_registry_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.eks_registry_region))
    error_message = "eks_registry_region must be an AWS region name, or null."
  }
}
variable "eks_cache_prefix" {
  type        = string
  default     = "ecr-to-ecr"
  description = "Repository prefix in this account under which EKS registry images are cached. An image is then pulled as <account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<upstream path>, so this string appears in every manifest that uses a cached EKS image"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._/-]*[a-z0-9])?$", var.eks_cache_prefix))
    error_message = "eks_cache_prefix must be a valid lowercase ECR repository prefix."
  }
}
variable "public_cache_prefix" {
  type        = string
  default     = "ecr-public"
  description = "Repository prefix under which ECR Public images are cached. The cluster has no route to the internet, so anything from public.ecr.aws has to be pulled through this"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._/-]*[a-z0-9])?$", var.public_cache_prefix))
    error_message = "public_cache_prefix must be a valid lowercase ECR repository prefix."
  }
}
variable "create_public_cache" {
  type        = bool
  default     = true
  description = "Whether to create the ECR Public cache rule. ECR Public needs no credentials, which is why this rule takes no custom role unlike the EKS registry one"
}
variable "role_name_prefix" {
  type        = string
  default     = "ecr-pull-through-cache"
  description = "Name prefix for the IAM role the EKS registry cache rule assumes"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters from the set IAM accepts for a role name, leaving room for the generated suffix."
  }
}
variable "pull_policy_name_prefix" {
  type        = string
  default     = "ecr-cache-pull"
  description = "Name prefix for the IAM policy that lets a pulling principal materialise the cache repositories. Attached to the node role by the caller, because this module does not know who pulls (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.pull_policy_name_prefix))
    error_message = "pull_policy_name_prefix must be 1-64 characters from the set IAM accepts for a policy name, leaving room for the generated suffix."
  }
}
