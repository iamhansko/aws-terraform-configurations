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
  default     = "keycloak-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns, so the pre-created ALB carries the same value (rules.md G-3)"

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
variable "hosted_zone_name" {
  type        = string
  description = "Name of the public Route 53 hosted zone the Keycloak record and the certificate validation records go into, e.g. example.com. No default: it names a zone that has to already exist, and this project cannot work without real DNS - the ACM certificate is validated through it and the ALB is reached by name"

  validation {
    condition     = can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?\\.)+[a-z]{2,}\\.?$", var.hosted_zone_name))
    error_message = "hosted_zone_name must be a domain name such as example.com."
  }
}
variable "keycloak_subdomain" {
  type        = string
  default     = "keycloak"
  description = "Label prepended to hosted_zone_name to form the Keycloak host. That host is used in three places that must agree - the ACM certificate, the Ingress rule and the Route 53 record - so all three read the one value derived from this (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.keycloak_subdomain))
    error_message = "keycloak_subdomain must be a valid lowercase DNS label."
  }
}
variable "keycloak_namespace" {
  type        = string
  default     = "keycloak"
  description = "Namespace Keycloak runs in, and the first half of the Ingress adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.keycloak_namespace))
    error_message = "keycloak_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "keycloak_ingress_name" {
  type        = string
  default     = "keycloak"
  description = "Name of the Ingress, and the second half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.keycloak_ingress_name))
    error_message = "keycloak_ingress_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "keycloak_admin_username" {
  type        = string
  default     = "admin"
  description = "Bootstrap admin username, as upstream's quickstart has it. Created on first start only"

  validation {
    condition     = length(var.keycloak_admin_username) > 0
    error_message = "keycloak_admin_username must not be empty."
  }
}
variable "keycloak_admin_password" {
  type        = string
  sensitive   = true
  description = "Bootstrap admin password. No default on purpose: upstream's quickstart hardcodes \"admin\" and the _monolithic template published it in a plaintext output, which put a working administrator login for an internet-facing console into the plan, the state and the instance README. Pass it with TF_VAR_keycloak_admin_password"

  validation {
    condition     = length(var.keycloak_admin_password) >= 12
    error_message = "keycloak_admin_password must be at least 12 characters. The console it protects is reachable from the internet whenever allow_inbound_from_anywhere is true."
  }
}
variable "keycloak_database_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL password for Keycloak's database. No default: upstream hardcodes \"keycloak\" and says in the manifest itself that a production setup should not. Pass it with TF_VAR_keycloak_database_password"

  validation {
    condition     = length(var.keycloak_database_password) >= 12
    error_message = "keycloak_database_password must be at least 12 characters."
  }
}
variable "keycloak_replicas" {
  type        = number
  default     = 2
  description = "Keycloak replicas, two as upstream recommends so a configuration change can roll without losing the in-memory session cache. Each requests 1700Mi, which is what sizes the node group below"

  validation {
    condition     = var.keycloak_replicas >= 1
    error_message = "keycloak_replicas must be at least 1."
  }
}
variable "keycloak_image" {
  type        = string
  default     = "quay.io/keycloak/keycloak:26.7.4"
  description = "Keycloak image, pinned. The _monolithic template applied a manifest from a Git branch, so this tag changed without notice"

  validation {
    condition     = can(regex(":", var.keycloak_image))
    error_message = "keycloak_image must include an explicit tag."
  }
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
  default     = "keycloak-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1)"

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
  default     = ["t3.large"]
  description = "Instance types for the managed node group. t3.large rather than the t3.medium most variants use: two Keycloak replicas request 1700Mi each, and a t3.medium has under 4Gi allocatable once the kubelet and the CNI take their share - so the second replica would stay Pending"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count. Two, so the two Keycloak replicas can land on different nodes - which is the point of running two"

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
  description = "Maximum node count. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what turns Keycloak's Ingress into the ALB; the _monolithic template declared its IAM role and installed it from a helm command in userdata (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because no Service here is of that type at all - Keycloak is reached through an Ingress and its Services are ClusterIP. The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on gates every Service creation in the cluster behind a controller pod being Ready (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. No Service here is of type LoadBalancer, so the webhook has nothing to mutate, while its failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "load_balancer_port" {
  type        = number
  default     = 443
  description = "Listener port on the ALB, and the port its frontend security group opens. 443 as the _monolithic template had it: the ALB terminates TLS with the ACM certificate and the Ingress redirects http to it, so https is the only port that has to be reachable"

  validation {
    condition     = var.load_balancer_port > 0 && var.load_balancer_port <= 65535
    error_message = "load_balancer_port must be between 1 and 65535."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "keycloak-alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created ALB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.synced_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_load_balancer_name))
    error_message = "synced_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the Keycloak console is reached from a browser - but code-server has no authentication in front of it, so narrow this to your own address where possible"
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
