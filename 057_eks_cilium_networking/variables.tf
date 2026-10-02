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
  default     = "cilium-cluster"
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
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather
    # than left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because Cilium and the load balancer controller are installed by the helm provider from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "cilium-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets'. The _monolithic template tagged no subnets at all (rules.md G-1)"

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
  description = "Instance types for the managed node group. The instance type also caps how many interfaces Cilium can attach, and therefore how many pod addresses a node can hold - the same limit the VPC CNI works within, because both allocate real VPC addresses"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Desired node count, three as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 3
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 6
  description = "Maximum node count, six as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "cilium_chart_version" {
  type        = string
  default     = "1.18.2"
  description = "Pinned cilium chart version, as the _monolithic template had it. This is the cluster's CNI and its Service implementation, so an unexpected upgrade takes the data plane with it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cilium_chart_version))
    error_message = "cilium_chart_version must be a semantic version (e.g. 1.18.2)."
  }
}
variable "cilium_ipam_mode" {
  type        = string
  default     = "eni"
  description = "How Cilium allocates pod addresses. eni gives pods real VPC addresses by attaching Elastic Network Interfaces, which is what lets the load balancer reach them directly with target-type ip. Pinned to eni by the validation below for that reason"

  validation {
    # Cross-cutting rather than cross-variable: the project's load balancer path depends
    # on pod addresses being VPC addresses, and cluster-pool would leave them on an
    # overlay the ALB cannot route to. Nothing would report that - the Ingress gets an
    # address and every target is unhealthy (rules.md B-1/G-1).
    condition     = var.cilium_ipam_mode == "eni"
    error_message = "cilium_ipam_mode must be eni in this variant. The 2048 Ingress uses target-type ip, so the load balancer sends traffic straight to pod addresses; with cluster-pool those addresses are on an overlay network the load balancer cannot reach, and the only symptom is a healthy Ingress whose targets never pass their health check. To explore cluster-pool, switch the Ingress to target-type instance first."
  }
}
variable "cilium_kube_proxy_replacement" {
  type        = bool
  default     = true
  description = "Whether Cilium implements Services instead of kube-proxy. True, and pinned below: no kube-proxy addon is installed on this cluster, so this is not an optimisation but the only implementation of Services present"

  validation {
    condition     = var.cilium_kube_proxy_replacement
    error_message = "cilium_kube_proxy_replacement must be true in this variant. This root installs no kube-proxy addon - that absence is half of what the project demonstrates - so turning this off leaves nothing implementing ClusterIP routing at all: pods get addresses and can reach each other directly, while every Service address is a black hole. To run with kube-proxy, add an eks_kube_proxy_addon module first (rules.md C-4)."
  }
}
variable "cilium_egress_masquerade_interfaces" {
  type        = string
  default     = null
  description = "Interface pattern Cilium masquerades pod egress behind. Null on purpose, and this differs from the Cilium-on-EKS instructions in wide circulation, which pass eth0. In ENI mode the chart renders enable-ipv4-masquerade: false - pod addresses are VPC addresses the network already routes, and the NAT gateway does the translation - so the setting has no effect whatsoever. Passing it anyway is harmless but reads as though it is doing something"

  validation {
    condition     = var.cilium_egress_masquerade_interfaces == null || length(var.cilium_egress_masquerade_interfaces) > 0
    error_message = "cilium_egress_masquerade_interfaces must be a non-empty interface pattern, or null to leave the chart's own detection in place."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The controller is what reconciles the 2048 Ingress into the pre-created ALB"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook, which claims new Services of type LoadBalancer. False: this project creates no Service of type LoadBalancer at all - the demo is reached through an Ingress - so the webhook has nothing to do, while its failurePolicy: Fail would gate every Service creation in the cluster on a Ready controller pod (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. Nothing here creates a Service of type LoadBalancer, so the webhook serves no purpose, while its failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "game_namespace" {
  type        = string
  default     = "game-2048"
  description = "Namespace the demo workload runs in. Defined at the root rather than left to the workload module's default because the pre-created load balancer's adoption stack tag is built from it, and the load balancer has to be tagged before the workload module runs (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.game_namespace))
    error_message = "game_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "game_ingress_name" {
  type        = string
  default     = "ingress-2048"
  description = "Name of the demo workload's Ingress, and the second half of the adoption stack tag (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.game_ingress_name))
    error_message = "game_ingress_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "game_replica_count" {
  type        = number
  default     = 5
  description = "How many demo pods to run. Five, as the upstream example has it, which also spreads pod addresses across enough interfaces that the allocation Cilium is doing is visible in a single kubectl get pods -o wide"

  validation {
    condition     = var.game_replica_count >= 1
    error_message = "game_replica_count must be at least 1."
  }
}
variable "game_container_port" {
  type        = number
  default     = 80
  description = "Port the demo container listens on. With target-type ip the load balancer reaches the pod directly on this port, so this is what the pod-side security group rule opens - not the Service port (rules.md G-1/G-2)"

  validation {
    condition     = var.game_container_port > 0 && var.game_container_port <= 65535
    error_message = "game_container_port must be a valid TCP port."
  }
}
variable "alb_listener_port" {
  type        = number
  default     = 80
  description = "Listener port on the ALB, which the frontend security group opens. 80 is what the controller creates when an Ingress does not override listen-ports"

  validation {
    condition     = var.alb_listener_port > 0 && var.alb_listener_port <= 65535
    error_message = "alb_listener_port must be a valid TCP port."
  }
}
variable "alb_security_group_name" {
  type        = string
  default     = "cilium-alb-sg"
  description = "Name of the frontend security group attached to the pre-created ALB"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "synced_alb_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the pre-created ALB. Null generates a unique one, which is what lets this project be deployed twice in one account - adoption is decided entirely by tags, so the name plays no part in it (rules.md G-3)"

  validation {
    condition     = var.synced_alb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.synced_alb_name))
    error_message = "synced_alb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB's frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because both are reached from a browser - but code-server has no authentication in front of it, so narrow this to your own address where possible"
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
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl, helm and the cilium CLI"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
