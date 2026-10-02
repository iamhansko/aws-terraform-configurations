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
  default     = "stars-policy-cluster"
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns, so the pre-created load balancer carries the same value (rules.md G-3)"

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
variable "enable_network_policy" {
  type        = bool
  default     = true
  description = "Whether the VPC CNI enforces Kubernetes NetworkPolicy objects. True, because that is the only thing this project demonstrates: with it off the API server still accepts every policy the demo applies and nothing enforces them, so the management UI graph stays fully green and the demo silently shows the opposite of its point. Rendered into the addon's configuration_values as a top-level key, not as a DaemonSet environment variable (rules.md E-5)"

  validation {
    # The constraint is about what this project is for, not about the value's shape, so
    # it belongs here rather than in the description (rules.md B-1).
    condition     = var.enable_network_policy == true
    error_message = "enable_network_policy must stay true in this variant. The whole demo is that applying a NetworkPolicy cuts connections in the management UI graph; with the agent off the policies are accepted and ignored, and the graph never changes. To explore the unenforced behaviour, apply with it true and simply do not apply the policy files."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl and helm providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same objects from an SSM Association on the bastion. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather
    # than left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Kubernetes objects are applied by the kubectl provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "stars-policy-key"
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
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
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
  description = "Desired node count, two as the _monolithic template had it. The demo runs four small pods plus the network policy agent on every node"

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
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what turns the management UI's Service into the NLB; the _monolithic template installed it from a helm command in userdata (rules.md E-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer that do not name the controller themselves. False, because the one such Service here - the management UI - sets aws-load-balancer-type: external and is claimed without it (rules.md G-1). The chart gives that webhook failurePolicy: Fail and no namespaceSelector, so leaving it on makes every Service creation in the cluster wait on a controller pod being Ready, and this project creates six Services right after installing the controller (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The management UI Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster and would gate this project's own Services behind a controller pod being Ready (rules.md G-4)."
  }
}
variable "management_ui_namespace" {
  type        = string
  default     = "management-ui"
  description = "Namespace the management UI runs in. Defined at the root rather than left to the workload module's default because the pre-created load balancer's adoption stack tag is built from it, and the load balancer has to be tagged before the workload module runs - so both read this one variable instead of deriving the name twice (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_namespace))
    error_message = "management_ui_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_name" {
  type        = string
  default     = "management-ui"
  description = "Name of the management UI Service and Deployment, and the second half of the adoption stack tag. Same reason as management_ui_namespace for living here (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.management_ui_name))
    error_message = "management_ui_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "management_ui_service_port" {
  type        = number
  default     = 80
  description = "Port the management UI Service publishes, and therefore the NLB's listener port - the one the frontend security group opens. Defined at the root because the security group and the Service both need it and they are separate modules, so one value feeds both (rules.md B-5/G-1)"

  validation {
    condition     = var.management_ui_service_port > 0 && var.management_ui_service_port <= 65535
    error_message = "management_ui_service_port must be between 1 and 65535."
  }
}
variable "management_ui_container_port" {
  type        = number
  default     = 9001
  description = "Port the management UI container listens on. Distinct from the Service port on purpose: with target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what the pod-side rule on the cluster security group has to open. Opening the Service port instead leaves every target unhealthy with no error anywhere (rules.md G-1/G-2)"

  validation {
    condition     = var.management_ui_container_port > 0 && var.management_ui_container_port <= 65535
    error_message = "management_ui_container_port must be between 1 and 65535."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "stars-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_load_balancer_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created NLB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.synced_load_balancer_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_load_balancer_name))
    error_message = "synced_load_balancer_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the management UI and code-server are both reached from a browser - but code-server has no authentication in front of it, so narrow this to your own address with ingress_cidr_blocks where possible"
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
variable "apply_network_policies" {
  type        = bool
  default     = true
  description = "Whether the demo's six NetworkPolicy objects are created. True, so an apply produces the finished state: the management UI reaches all three probes, the frontend reaches the backend, the client reaches the frontend, and nothing else connects. They are Terraform resources rather than files left for the user to apply, so they are in state, show up in plan, and are removed in order on destroy (rules.md E-1/E-2). Set false to see the unrestricted graph, which is the honest way to walk the demo backwards - deleting them with kubectl works until the next apply puts them back (rules.md B-4). Distinct from enable_network_policy: that decides whether they are enforced at all"
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
