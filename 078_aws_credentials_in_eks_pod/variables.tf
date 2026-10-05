variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name_prefix" {
  type        = string
  default     = "pod-credentials"
  description = "Prefix for the three cluster names, which become <prefix>-imds, <prefix>-irsa and <prefix>-pod-identity. One prefix rather than three names, so the three cannot be named inconsistently and the set is obviously a set (rules.md B-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,60}$", var.cluster_name_prefix))
    error_message = "cluster_name_prefix must start with a letter or digit, contain only letters, digits, hyphens and underscores, and leave room for the per-cluster suffix."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for all three clusters. One value, because a version difference between them would be a second variable in a comparison meant to have one"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the clusters' API server endpoints are reachable from the internet. True as the _monolithic template had it, and needed because the kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the service accounts and pods on all three clusters are applied by the kubectl providers from the machine running terraform. To run with private endpoints, apply them from the bastion through SSM Associations instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoints. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach an endpoint with a valid AWS credential for the creating principal has cluster-admin on that cluster"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "pod-credentials-key"
  description = "Name of the EC2 key pair created for the demo instance and shared by all three clusters' node groups"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_name" {
  type        = string
  default     = "al2023"
  description = "Name of the node group on each cluster, as the _monolithic template named all three. The same name on three different clusters is fine - a node group name is scoped to its cluster - and keeping them identical is what makes the comparison a comparison"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]*)$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the node groups, t3.medium as the _monolithic template had it. Each cluster runs one pod that does nothing, so the size is irrelevant to the demo"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_size" {
  type        = number
  default     = 1
  description = "Node count per cluster, one as the _monolithic template had it - and fixed rather than a range, because the demo has nothing to scale. One node per cluster still means three nodes in total"

  validation {
    condition     = var.node_group_size >= 1
    error_message = "node_group_size must be at least 1."
  }
}
variable "imds_hop_limit" {
  type        = number
  default     = 2
  description = "The nodes' IMDS hop limit, and the setting the IMDS cluster's whole demonstration rests on. A pod is a network hop away from its node, so with the limit at one - the EC2 default for a new launch template - a pod's request to 169.254.169.254 is dropped and the mechanism does not work at all. Two lets it through, which is what makes the IMDS pod get the node's credentials. Worth knowing that it cuts both ways: the same setting is what lets every pod on the node reach the node's credentials, which is the reason to prefer IRSA or Pod Identity"

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "imds_hop_limit must be between 1 and 64."
  }
  validation {
    # Constant condition, because this variant exists to demonstrate the mechanism that needs it
    # (rules.md B-1).
    condition     = var.imds_hop_limit >= 2
    error_message = "imds_hop_limit must be at least 2 in this variant. At one, a pod's request to the instance metadata service is dropped before it reaches the node, so the IMDS cluster demonstrates nothing - its pod simply has no credentials at all, which looks like a broken image rather than a hop limit. Set it to 1 deliberately only to watch that happen."
  }
}
variable "pod_name" {
  type        = string
  default     = "cli"
  description = "Name of the AWS CLI pod on every cluster, cli as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.pod_name))
    error_message = "pod_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "pod_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the pods and service accounts live in on every cluster, as the _monolithic template had it. One value, because the IRSA trust policy's sub condition and the Pod Identity association both name it - and a mismatch there leaves the pod with the node's credentials rather than an error (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.pod_namespace))
    error_message = "pod_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "cli-sa"
  description = "Name of the service account on every cluster, cli-sa as the _monolithic template had it. The same string appears in the IRSA trust policy and in the Pod Identity association, and one variable feeds all three so they cannot disagree (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "pod_image" {
  type        = string
  default     = "public.ecr.aws/aws-cli/aws-cli:2.32.9"
  description = "Image for the pod on every cluster. Pinned and from ECR Public, where the _monolithic template used amazon/aws-cli - docker.io's floating latest, pulled three times over because there are three clusters, from a registry that rate-limits anonymous pulls per source address"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.pod_image))
    error_message = "pod_image must carry an explicit tag or a digest."
  }
}
variable "bucket_name" {
  type        = string
  default     = null
  description = "Fixed name for the demo bucket. Null generates one, which is what lets this project be deployed twice in one account - bucket names are globally unique"

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name, or null to generate one."
  }
}
variable "grant_node_role_bucket_access" {
  type        = bool
  default     = false
  description = "Whether the shared node role is also allowed to read the demo bucket. False, and the false case is the lesson: on the IMDS cluster the pod ends up with the node's credentials, so listing the bucket is denied and the difference between \"an identity\" and \"an identity with permissions\" becomes visible. Set it true to make the IMDS pod succeed as well - and notice what that means, since the node role is shared by every pod on every node of all three clusters, so granting it here grants it to all of them at once. That is the argument for the other two mechanisms, and it is worth producing rather than just reading (rules.md B-4)"
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port, as the _monolithic template had it. code-server has no authentication in front of it, so narrow this where possible and reach it through SSM Session Manager port forwarding instead"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where the bootstrap drops its completion marker. The README association waits for that marker instead of trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
