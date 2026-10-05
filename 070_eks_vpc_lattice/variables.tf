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
  default     = "vpc-lattice-cluster"
  description = "Name of the EKS cluster. The Gateway API controller also tags the VPC Lattice services and target groups it creates with it, which is how one cluster's Lattice resources are told from another's"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for the EKS cluster. The _monolithic template pinned 1.32, which has been out of standard support since March 2026"

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
    error_message = "endpoint_public_access must be true in this variant, because the Gateway API CRDs, the controller and every Gateway, Service and HTTPRoute are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "vpc-lattice-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group, t3.large as the _monolithic template had it. Eight demo pods plus the Gateway API controller, the EBS CSI driver and CoreDNS do not fit comfortably on anything smaller"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. Two is useful rather than incidental here: with the backends' pods spread over two nodes, a VPC Lattice target group holds addresses from both and the traffic is visibly not going through a node port"

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
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales this node group"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "storage_class_name" {
  type        = string
  default     = "gp3"
  description = "Name of the default StorageClass created for the cluster, gp3 as the _monolithic template named it. Nothing in this project claims a volume; it is the cluster's storage baseline, and it is here because the original set it up"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "gateway_api_version" {
  type        = string
  default     = "v1.2.0"
  description = "Gateway API release whose CRDs are installed, as the _monolithic template pinned it. Has to be a release the controller chart supports: a controller older than the CRDs ignores fields it does not know rather than rejecting them, so a mismatch shows up as a route that half works"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gateway_api_version))
    error_message = "gateway_api_version must look like v1.2.0."
  }
}
variable "gateway_api_channel" {
  type        = string
  default     = "standard"
  description = "Which Gateway API CRD bundle to install. standard as the _monolithic template used - at v1.2.0 it carries GatewayClass, Gateway, HTTPRoute, GRPCRoute and ReferenceGrant, GRPCRoute having graduated out of the experimental channel in that release. The experimental channel adds TLSRoute, TCPRoute, UDPRoute and the policy kinds, none of which this project uses. Which kinds a channel holds moves between releases, so read the gateway_api_install output after changing the version rather than trusting this sentence"

  validation {
    condition     = contains(["standard", "experimental"], var.gateway_api_channel)
    error_message = "gateway_api_channel must be standard or experimental."
  }
}
variable "gateway_api_crd_url" {
  type        = string
  default     = null
  description = "Full URL of the Gateway API CRD bundle, overriding the upstream GitHub release URL built from gateway_api_version. Null uses upstream, which is what the original applied - and which makes terraform plan need a route to github.com, since the bundle is fetched at plan time so its documents can become individual resources. Point this at a mirror in a network without one"

  validation {
    condition     = var.gateway_api_crd_url == null || can(regex("^https://", var.gateway_api_crd_url))
    error_message = "gateway_api_crd_url must be an https URL, or null to use the upstream release."
  }
}
variable "gateway_api_controller_chart_version" {
  type        = string
  default     = "v1.1.5"
  description = "Pinned aws-gateway-controller-chart version, as the _monolithic template pinned it. Installed from public.ecr.aws, which serves anonymous pulls - so the \"aws ecr-public get-login-password | helm registry login\" step the original ran first is not needed"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.gateway_api_controller_chart_version))
    error_message = "gateway_api_controller_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "gateway_name" {
  type        = string
  default     = "eks-network"
  description = "Name of the Gateway, eks-network as the _monolithic template had it. One value reaches two places that have to agree: the Gateway object, and the controller's defaultServiceNetwork - the controller pairs them by name, and a mismatch leaves the Gateway without an address and nothing saying why (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.gateway_name))
    error_message = "gateway_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Gateway, the backends and the routes all live in, as the _monolithic template had it. One namespace for all of them because a Gateway's default listener does not allow routes from elsewhere, and a route that is not allowed to attach says so only in its own status"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "backend_services" {
  type = map(object({
    replicas = optional(number, 2)
  }))
  default = {
    inventory-ver1 = {}
    inventory-ver2 = {}
    parking        = {}
    review         = {}
  }
  description = "The demo backends, keyed by Service name. Four of them, as the _monolithic template had: two versions of one service for the weighted-routing half of the demo, and two different services for the path-routing half. Keys become resource addresses, so they are literal strings in configuration (rules.md B-8)"

  validation {
    condition     = length(var.backend_services) > 0
    error_message = "backend_services must contain at least one entry."
  }
  validation {
    condition     = alltrue([for name in keys(var.backend_services) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))])
    error_message = "backend_services keys must each be a valid lowercase RFC 1123 DNS label - each becomes a Deployment name, a Service name and a pod label value."
  }
  validation {
    condition     = alltrue([for entry in values(var.backend_services) : entry.replicas >= 1])
    error_message = "backend_services replicas must be at least 1."
  }
}
variable "backend_image" {
  type        = string
  default     = "public.ecr.aws/x2j8p8w7/http-server:latest"
  description = "Image every backend runs, as the _monolithic template had it - AWS's sample HTTP server, which echoes the PodName environment variable so responses can be told apart. A floating tag, but on ECR Public rather than a rate-limited registry, and there is no versioned alternative published"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.backend_image))
    error_message = "backend_image must carry an explicit tag or a digest."
  }
}
variable "backend_service_port" {
  type        = number
  default     = 80
  description = "Port every backend Service publishes, which is the port a route's backendRef names"

  validation {
    condition     = var.backend_service_port > 0 && var.backend_service_port <= 65535
    error_message = "backend_service_port must be between 1 and 65535."
  }
}
variable "backend_container_port" {
  type        = number
  default     = 8090
  description = "Port the sample server listens on. The VPC Lattice target group is built from the Service's target port, so the controller registers pods on this port rather than on the Service's"

  validation {
    condition     = var.backend_container_port > 0 && var.backend_container_port <= 65535
    error_message = "backend_container_port must be between 1 and 65535."
  }
}
variable "inventory_route_weight" {
  type        = number
  default     = 10
  description = "Weight on the inventory route's single backend, ten as the _monolithic template had it. On its own it changes nothing - a rule with one backend sends everything there whatever the weight says - and that is the point of having it: adding inventory-ver2 to the same rule with a weight of its own turns this into a canary split, and the weight is already where it needs to be"

  validation {
    condition     = var.inventory_route_weight >= 0
    error_message = "inventory_route_weight must be zero or greater."
  }
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
