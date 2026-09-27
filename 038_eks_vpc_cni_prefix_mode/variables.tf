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
  default     = "prefix-mode-cluster"
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
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl provider that creates the demo workload runs on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). The _monolithic template had this false and applied the same manifests from the bastion; 041_eks_private_cluster keeps that approach. Narrow public_access_cidrs rather than leaving the default open"
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
  default     = "prefix-mode-key"
  description = "Name of the EC2 key pair created for the demo instances"

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
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer. A misspelled key is not rejected by AWS, so the failure surfaces much later as a controller that cannot auto-discover subnets (rules.md G-1)."
  }
}
variable "enable_prefix_delegation" {
  type        = bool
  default     = true
  description = "Whether the VPC CNI assigns /28 prefixes to each ENI instead of individual addresses. True, and this is the project: a t3.medium's three ENIs hold 15 usable addresses in the default mode, which caps the node at 17 pods; with prefix delegation each of those address slots becomes a /28, so the same instance can host well over a hundred. Set through the addon's configuration_values rather than by running kubectl set env against the aws-node DaemonSet (rules.md E-5)"
}
variable "warm_prefix_target" {
  type        = number
  default     = 1
  description = "How many spare /28 prefixes the CNI keeps allocated per node ahead of demand. 1 means one prefix beyond what is currently in use, which is what the _monolithic template set: it keeps pod startup fast without holding a large block of addresses idle. Only meaningful when enable_prefix_delegation is true"

  validation {
    condition     = var.warm_prefix_target >= 0
    error_message = "warm_prefix_target must be zero or greater."
  }
}
variable "node_max_pods" {
  type        = number
  default     = 110
  description = "Maximum pods the kubelet will admit per node, set through a NodeConfig in the launch template's user data. This has to be raised by hand: turning prefix delegation on changes what the CNI can allocate, but the kubelet's limit is computed at node bootstrap from the instance type using the non-prefix formula, and the bootstrap cannot see the DaemonSet's configuration. The _monolithic template left this commented out, so its nodes stayed capped at 17 pods and its 100-replica demo could never have scheduled. 110 is the ceiling AWS recommends for instances with fewer than 30 vCPUs"

  validation {
    condition     = var.node_max_pods >= 1 && var.node_max_pods <= 737
    error_message = "node_max_pods must be between 1 and 737. Above roughly 110 is not advisable on a small instance regardless of what prefix delegation makes addressable - the kubelet and the container runtime become the limit, not the address space."
  }
}
variable "node_timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on each node by the launch template's user data, as the _monolithic template did. Null skips the shell part of the user data entirely"

  validation {
    condition     = var.node_timezone == null || can(regex("^[A-Za-z_]+(/[A-Za-z_+-]+){0,2}$", var.node_timezone))
    error_message = "node_timezone must be an IANA timezone name such as Asia/Seoul or UTC, or null to skip the shell part of the user data. An unknown name makes timedatectl fail on the node rather than at plan time."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. t3.medium on purpose: it is small enough that the default 17-pod cap is obviously limiting, which is what makes the prefix mode comparison legible. Note that prefix delegation is only supported on Nitro-based instances"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count. One, deliberately: the demo is about how many pods fit on a single node, and more nodes would let the scheduler spread the replicas and hide the point"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 1
  description = "Maximum node count. Also one, so nothing scales out and rescues the demo: if the replicas do not fit on one node they stay Pending, which is the observation the project is making"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload is created in. default, as the _monolithic template had it, which is also why the ALB's adoption stack tag reads default/<name> (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name shared by the demo Deployment, Service and Ingress"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_image" {
  type        = string
  default     = "nginxdemos/hello"
  description = "Demo container image. nginxdemos/hello as the _monolithic template used. It comes from Docker Hub, which rate-limits anonymous pulls - and this project pulls it a hundred times onto one node, which makes that limit far more likely to bite than usual. Switch to an ECR Public mirror if pods start failing with toomanyrequests"

  validation {
    condition     = length(var.workload_image) > 0
    error_message = "workload_image must not be empty."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 100
  description = "Replicas for the demo Deployment. 100 is the demonstration: it does not fit on a t3.medium in the default CNI mode, where the node admits 17 pods, and does fit once prefix delegation is on and node_max_pods is raised"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_container_port" {
  type        = number
  default     = 80
  description = "Container and Service port for the demo workload"

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be between 1 and 65535."
  }
}
variable "manage_backend_security_group_rules" {
  type        = bool
  default     = false
  description = "Whether the controller writes the pod-side security group rules itself, via the Ingress annotation. False, so nothing asks it to - which is what allows enable_backend_security_group to be false and keeps the shared backend group from being created at all. The path from the load balancer to the pods is declared in Terraform instead, as aws_vpc_security_group_ingress_rule.load_balancer_to_pods, where it is visible in plan (rules.md G-2)"
}
variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller creates and uses its shared backend security group - the k8s-traffic-<cluster>-<hash> group it attaches to every load balancer and names as the traffic source in the rules it adds to node or ENI groups. False, so that group is never created. With manage_backend_security_group_rules also false the controller has no pod-side rules to write, so nothing is lost by turning it off; the trade is that the rule below belongs to Terraform, and a rule per load balancer accumulates on the pod-side group as load balancers are added"

  validation {
    # Cross-variable condition, available since Terraform 1.9: the constraint is about
    # the pair rather than either value alone. A workload that sets
    # manage-backend-security-group-rules while this is off is refused by the
    # controller, and only its own log says so - plan and apply both succeed and the
    # load balancer is simply never finished (rules.md B-1/G-2).
    condition     = var.manage_backend_security_group_rules ? var.enable_backend_security_group : true
    error_message = "enable_backend_security_group must be true when manage_backend_security_group_rules is true, because the controller rejects that combination when the Ingress also names its own frontend security group. Keep both false and let Terraform declare the pod-side rule, which is what this project does (rules.md G-2)."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "alb_port" {
  type        = number
  default     = 80
  description = "Listener port on the ALB"

  validation {
    condition     = var.alb_port > 0 && var.alb_port <= 65535
    error_message = "alb_port must be between 1 and 65535."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.0"
  description = "Pinned aws-load-balancer-controller chart version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group and the ALB security group accept traffic from 0.0.0.0/0. False by default; the ALB fronts a demo nginx and code-server has no authentication in front of it"
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
