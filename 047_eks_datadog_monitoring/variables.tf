variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "datadog-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.33."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "datadog_api_key" {
  type        = string
  sensitive   = true
  description = "Datadog API key, from https://app.datadoghq.com/organization-settings/api-keys. No default: a key belongs to an account, and one committed here would be a working credential in the repository. Pass it with TF_VAR_datadog_api_key. It reaches the cluster as a Secret rather than through a shell command, so unlike the _monolithic template it is not left readable in an SSM association parameter"

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.datadog_api_key))
    error_message = "datadog_api_key must be 32 lowercase hexadecimal characters. A 40-character value is an application key, which is not interchangeable with an API key."
  }
}
variable "datadog_site" {
  type        = string
  default     = "datadoghq.com"
  description = "Datadog site the agent reports to, which must match the region the account was created in. A mismatch is not a connection error: the agent reaches the wrong site and has its key rejected there, which reads as an invalid key"

  validation {
    condition = contains([
      "datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com",
      "datadoghq.eu", "ddog-gov.com", "ap1.datadoghq.com", "ap2.datadoghq.com",
    ], var.datadog_site)
    error_message = "datadog_site must be one of Datadog's documented sites: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com, datadoghq.eu, ddog-gov.com, ap1.datadoghq.com, ap2.datadoghq.com."
  }
}
variable "datadog_namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace the operator, the API key Secret and the DatadogAgent share, as the _monolithic template had it. One namespace for all three because the DatadogAgent's apiSecret reference resolves in its own namespace"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.datadog_namespace))
    error_message = "datadog_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "datadog_operator_chart_version" {
  type        = string
  default     = "2.7.0"
  description = "Pinned datadog-operator chart version. The _monolithic template pinned nothing, so a later apply would install whatever was current - and the DatadogAgent CRD's apiVersion can move between chart majors"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.datadog_operator_chart_version))
    error_message = "datadog_operator_chart_version must be a semantic version."
  }
}
variable "enable_log_collection" {
  type        = bool
  default     = true
  description = "Whether the agent collects container logs, as the _monolithic template had it"
}
variable "collect_all_containers" {
  type        = bool
  default     = true
  description = "Whether log collection covers every container rather than only annotated ones. True, as the _monolithic template had it: otherwise a fresh cluster shows no logs until pods are annotated, which looks like a broken install"
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl and helm providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Kubernetes objects are applied by the kubectl and helm providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "datadog-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = "Tags merged into every public subnet. Nothing in this project creates a load balancer, but the tags cost nothing and are what the AWS Load Balancer Controller would need to auto-discover subnets if one is added later (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
  }
}
variable "private_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  description = "Tags merged into every private subnet, used the same way for internal load balancers (rules.md G-1)"

  validation {
    condition = alltrue([
      for key, value in var.private_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. The agent is a DaemonSet, so it runs one pod per node and two nodes is enough to see that"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0. True as the _monolithic template had it, but code-server runs with no authentication in front of it, so narrow this to your own address with ingress_cidr_blocks where possible"
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
