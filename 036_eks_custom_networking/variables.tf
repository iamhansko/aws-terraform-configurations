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
  default     = "custom-networking-cluster"
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
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the kubectl provider that creates the ENIConfig custom resources runs on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2). The _monolithic template had this false and applied those manifests with kubectl from the bastion instead; 041_eks_private_cluster is the project that keeps that approach. Narrow public_access_cidrs rather than leaving the default open"
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
  default     = "custom-networking-key"
  description = "Name of the EC2 key pair created for the demo instances"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary VPC CIDR. Nodes take their addresses from subnets carved out of this; pods do not, which is the point of the project"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "secondary_cidr_block" {
  type        = string
  default     = "100.64.0.0/16"
  description = "Second CIDR associated with the VPC, carrying the pod subnets. 100.64.0.0/16 is CGNAT space: addresses from it do not have to be unique across peered or on-premises networks, which is the reason to move pods out of the primary RFC 1918 range in the first place"

  validation {
    condition     = can(cidrhost(var.secondary_cidr_block, 0))
    error_message = "secondary_cidr_block must be a valid IPv4 CIDR block."
  }
  validation {
    condition     = tonumber(split("/", var.secondary_cidr_block)[1]) <= 24
    error_message = "secondary_cidr_block must be /24 or larger, because it is carved into one /24 pod subnet per availability zone."
  }
}
variable "enable_pod_subnet_nat_route" {
  type        = bool
  default     = true
  description = "Whether the pod subnets get a default route through their zone's NAT gateway. True, which departs from the _monolithic template: it created the pod route tables and never added a route, so any pod calling outside the VPC timed out with nothing indicating routing as the cause. Inbound-only workloads do not notice, because the kubelet pulls images over the node's own interface. Set false to reproduce the original exactly"
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1). Deliberately not applied to the pod subnets - a load balancer must never be placed in CGNAT space"

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
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. Worth knowing with custom networking: the node's primary interface no longer carries pod addresses, so the instance type's ENI and per-ENI address limits bound pod density differently than on a default cluster"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count. Two, one per zone, so the demo shows each zone's pods drawing from that zone's pod subnet"

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
  description = "Maximum node count"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
}
variable "eni_config_label_def" {
  type        = string
  default     = "topology.kubernetes.io/zone"
  description = "Node label the VPC CNI reads to decide which ENIConfig applies to a node. With this set to the zone label, an ENIConfig must be named after an availability zone - which is what the eni_config module does. Changing it means renaming every ENIConfig to match whatever the new label's values are"

  validation {
    condition     = length(var.eni_config_label_def) > 0
    error_message = "eni_config_label_def must not be empty. With custom networking on and no label definition, the CNI looks for an ENIConfig named after the node itself."
  }
}
variable "pod_security_group_name" {
  type        = string
  default     = "pod-sg"
  description = "Name of the security group attached to every pod ENI"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.pod_security_group_name)) && !startswith(var.pod_security_group_name, "sg-")
    error_message = "pod_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
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
  description = "Demo container image. nginxdemos/hello rather than plain nginx because its page prints the server address, which makes custom networking visible in a browser. It comes from Docker Hub, which rate-limits anonymous pulls - switch to an ECR Public mirror if that becomes a problem"

  validation {
    condition     = length(var.workload_image) > 0
    error_message = "workload_image must not be empty."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 2
  description = "Replicas for the demo Deployment, one per zone so both pod subnets are exercised"

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
