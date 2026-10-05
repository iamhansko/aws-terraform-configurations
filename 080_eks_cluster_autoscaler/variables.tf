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
  default     = "cluster-autoscaler-cluster"
  description = "Name of the EKS cluster. It is also what cluster-autoscaler's auto-discovery matches on: EKS tags every managed node group's Auto Scaling group with k8s.io/cluster-autoscaler/<cluster name>, and the autoscaler finds its groups by that tag. The AWS Load Balancer Controller writes the same value into the elbv2.k8s.aws/cluster tag it uses to find its own load balancers (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster. Raise cluster_autoscaler_chart_version with it: the chart's default image tag tracks the Kubernetes minor it was released for, and an autoscaler more than a minor behind the API server can misread node conditions"

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
  description = "Whether the EKS API server endpoint is reachable from the internet. True as the _monolithic template had it, and needed because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-2). Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Helm releases and manifests are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "cluster-autoscaler-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1). The _monolithic template tagged no subnets and named the load balancer's subnets by hand instead"

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
  description = "Instance types for the managed node group, t3.medium as the _monolithic template had it. The size decides how many of the demo's 100m pods fit on one node, and therefore how many nodes the autoscaler has to add - a larger type makes the same demo scale less"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count at apply time, one as the _monolithic template had it. One is the starting point of the demo rather than a sizing decision: the autoscaler is what takes it from here, and the number only means anything on the first apply because EKS afterwards syncs the node group's scaling configuration from whatever the Auto Scaling group actually holds"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1. The autoscaler itself, CoreDNS and metrics-server all have to be scheduled somewhere before anything can scale."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 1
  description = "Floor the autoscaler may not scale below, one as the _monolithic template had it. This is a real constraint rather than a starting value: the autoscaler will not remove the last node however unneeded it looks"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Ceiling the autoscaler may not scale above, four as the _monolithic template had it. The demo is built to reach it: twenty-four pods at 100m each do not fit on one t3.medium, and if this were equal to the minimum the autoscaler would log that it wants more capacity and then do nothing - which looks exactly like an autoscaler that is not working"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size > var.node_group_min_size
    error_message = "node_group_max_size must be greater than node_group_min_size. Equal bounds leave the autoscaler nothing to do: it reports unschedulable pods and never adds a node, which is indistinguishable from a broken install."
  }
}
variable "cluster_autoscaler_chart_version" {
  type        = string
  default     = "9.51.0"
  description = "Pinned cluster-autoscaler chart version. The _monolithic template ran helm repo update and installed whatever was current at boot time, so two applies a month apart produced different autoscalers"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cluster_autoscaler_chart_version))
    error_message = "cluster_autoscaler_chart_version must be a semantic version."
  }
}
variable "scale_down_unneeded_time" {
  type        = string
  default     = "5m"
  description = "How long a node must sit underutilized before the autoscaler removes it. Shortened from upstream's 10m so the scale-down half of the demo finishes within a sitting - the scale-up half takes a minute or two, and the wait to shrink again is the part people assume is broken"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.scale_down_unneeded_time))
    error_message = "scale_down_unneeded_time must be a Go duration such as 30s, 5m or 1h."
  }
}
variable "balance_similar_node_groups" {
  type        = bool
  default     = true
  description = "Whether the autoscaler keeps similar node groups at similar sizes. There is only one node group here, so it changes nothing today - it is on because it is what AWS recommends the moment a cluster has one node group per availability zone, which is the shape this project would take next"
}
variable "spread_workloads" {
  type = map(object({
    image        = string
    topology_key = string
    replicas     = optional(number, 12)
  }))
  default = {
    nginx = {
      image        = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
      topology_key = "topology.kubernetes.io/zone"
    }
    httpd = {
      image        = "public.ecr.aws/docker/library/httpd:2.4.65-alpine"
      topology_key = "kubernetes.io/hostname"
    }
  }
  description = "The Deployments that make the cluster want more capacity, keyed by Deployment name. Two of them, spreading on zone and on hostname, as the _monolithic template's two manifest files did - except that it only wrote those files onto the bastion and never applied them, so an apply produced an autoscaler with nothing to autoscale (rules.md E-1). Both images are pinned and come from ECR Public, where the original used the bare names nginx and httpd: floating tags on a registry that rate-limits anonymous pulls per source address, pulled again on every node the autoscaler adds. Keys become resource addresses, so they are literal strings in configuration (rules.md B-8)"

  validation {
    condition     = length(var.spread_workloads) > 0
    error_message = "spread_workloads must contain at least one entry. With none, the cluster never needs more capacity and the autoscaler has nothing to demonstrate."
  }
  validation {
    condition     = alltrue([for name in keys(var.spread_workloads) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))])
    error_message = "spread_workloads keys must each be a valid lowercase RFC 1123 DNS label - each becomes a Deployment name and a pod label value."
  }
  validation {
    condition     = alltrue([for entry in values(var.spread_workloads) : can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", entry.image))])
    error_message = "spread_workloads images must each carry an explicit tag or a digest."
  }
  validation {
    condition     = alltrue([for entry in values(var.spread_workloads) : entry.replicas >= 0])
    error_message = "spread_workloads replicas must be zero or greater. Zero is deliberately allowed: setting every entry to zero is how the scale-down half of the demo is triggered."
  }
}
variable "spread_workload_replicas" {
  type        = number
  default     = null
  description = "Overrides the replica count of every entry in spread_workloads. Null leaves each entry at its own value. It exists so the second half of the demo is one flag rather than a restated map: terraform apply -var spread_workload_replicas=0 takes the pressure off and lets the autoscaler decide the nodes are unneeded, and a larger number pushes the cluster to the node group's ceiling"

  validation {
    condition     = var.spread_workload_replicas == null || var.spread_workload_replicas >= 0
    error_message = "spread_workload_replicas must be zero or greater, or null to leave each spread_workloads entry at its own replica count."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo Deployments run in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. It is here for one reason: the dashboard's Service is of type LoadBalancer, and without this controller the in-tree cloud provider would claim it and build a Classic Load Balancer instead (rules.md G-1). The _monolithic template installed it with a helm command in user data, after an \"exec bash\" line that discarded every remaining line - so on a real boot it was never installed (rules.md E-1/H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the controller installs the mservice.elbv2.k8s.aws mutating webhook. False: the one Service of type LoadBalancer here sets aws-load-balancer-type: external and is claimed without it (rules.md G-1), while the webhook's failurePolicy: Fail and missing namespaceSelector make every Service creation in the cluster wait on a controller pod being Ready (rules.md G-4)"

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. The dashboard Service sets aws-load-balancer-type: external, so the controller claims it without the webhook, while the webhook's failurePolicy: Fail applies to every Service created in the cluster (rules.md G-4)."
  }
}
variable "dashboard_namespace" {
  type        = string
  default     = "default"
  description = "Namespace kube-ops-view runs in, as the _monolithic template had it. Also the first half of the stack tag the pre-created NLB must carry to be adopted rather than duplicated (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.dashboard_namespace))
    error_message = "dashboard_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "dashboard_name" {
  type        = string
  default     = "kube-ops-view"
  description = "Name of the kube-ops-view Deployment and Service, and the second half of the adoption stack tag. The _monolithic template hardcoded \"default/kube-ops-view\" into the pre-created load balancer's tag; here both halves come from these variables so the tag cannot drift from the Service (rules.md B-5/G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.dashboard_name))
    error_message = "dashboard_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "dashboard_service_port" {
  type        = number
  default     = 80
  description = "Port the dashboard Service publishes, and therefore the NLB's listener port - the one the frontend security group opens. 80 as the _monolithic template's security group had it"

  validation {
    condition     = var.dashboard_service_port > 0 && var.dashboard_service_port <= 65535
    error_message = "dashboard_service_port must be between 1 and 65535."
  }
}
variable "dashboard_container_port" {
  type        = number
  default     = 8080
  description = "Port the dashboard container listens on. Distinct from the Service port on purpose: with nlb-target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what the pod-side rule on the cluster security group has to open. Opening the Service port instead leaves every target unhealthy with no error anywhere (rules.md G-1/G-2). The _monolithic template sidestepped the question by putting the cluster security group on the load balancer itself, which let traffic in through the cluster group's self-referencing rule and left no record of what was actually being allowed"

  validation {
    condition     = var.dashboard_container_port > 0 && var.dashboard_container_port <= 65535
    error_message = "dashboard_container_port must be between 1 and 65535."
  }
}
variable "load_balancer_security_group_name" {
  type        = string
  default     = "kube-ops-view-nlb-sg"
  description = "Name of the frontend security group attached to the pre-created NLB. An NLB can only be given security groups at creation, so this group and the load balancer are created together (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.load_balancer_security_group_name)) && !startswith(var.load_balancer_security_group_name, "sg-")
    error_message = "load_balancer_security_group_name must use the character set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the NLB frontend security group and the VS Code security group accept traffic from 0.0.0.0/0. True as the _monolithic template had it, because the dashboard and code-server are both reached from a browser - but code-server has no authentication in front of it, so narrow this with ingress_cidr_blocks where possible"
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
