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
  default     = "adot-xray-trace-cluster"
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
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True because the helm and kubectl providers run on the machine executing terraform apply rather than inside the VPC (rules.md E-1/E-2); the _monolithic template had this true as well, driving the same objects from an SSM Association on the bastion. Narrow public_access_cidrs rather than leaving the default open"

  validation {
    # Pinned in the direction this variant actually depends on. The two forms fail
    # differently and the SSM alternative is E-9's, so the choice is recorded rather than
    # left implicit (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because cert-manager and the add-on's RBAC are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
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
  default     = "adot-xray-trace-key"
  description = "Name of the EC2 key pair created for the demo instance"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. The OTLP collector is a Deployment behind a Service rather than a DaemonSet - applications send to it, so one is enough regardless of node count. The node size matters for the sample application instead, which is a JVM"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it"

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
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "cert_manager_chart_version" {
  type        = string
  default     = "v1.21.2"
  description = "Pinned cert-manager version. Not optional and not incidental: the ADOT add-on installs an operator whose admission webhook serves TLS from a certificate cert-manager issues, so without it the add-on installs and the operator never becomes ready. The _monolithic template installed it unpinned from a shell script (rules.md E-1)"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.cert_manager_chart_version))
    error_message = "cert_manager_chart_version must be a semantic version, optionally prefixed with v."
  }
}
variable "adot_addon_version" {
  type        = string
  default     = null
  description = "Specific adot add-on version, or null to let EKS pick its default - which is what the _monolithic template did. The add-on's configuration schema is versioned with it, so pinning this pins the shape of the configuration below as well"

  validation {
    condition     = var.adot_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.adot_addon_version))
    error_message = "adot_addon_version must look like v0.156.0-eksbuild.1, or null."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it, because code-server is reached from a browser - but it runs with authentication disabled, so narrow this to your own address where possible"
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
variable "sample_app_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the sample application and its traffic generator run in, as the _monolithic template had it. Part of the application's IRSA trust policy, and the namespace whose DNS name the generator resolves"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.sample_app_namespace))
    error_message = "sample_app_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "sample_app_image" {
  type        = string
  default     = "public.ecr.aws/aws-otel-test/aws-otel-java-spark:1.17.0"
  description = "Image for the sample application, as the _monolithic template had it. An AWS-published sample already instrumented with the OpenTelemetry Java SDK, which is why nothing in this project has to instrument anything"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.sample_app_image))
    error_message = "sample_app_image must carry an explicit tag."
  }
}
variable "traffic_generator_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/alpine:3.24.2"
  description = "Image for the traffic generator. Alpine from ECR Public at a pinned tag, where the _monolithic template used ellerbrock/alpine-bash-curl-ssl:latest from Docker Hub - a floating tag on a registry that rate-limits anonymous pulls per source address, which every node here shares through one NAT gateway per zone"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.traffic_generator_image))
    error_message = "traffic_generator_image must carry an explicit tag."
  }
}
variable "otel_service_namespace" {
  type        = string
  default     = "GettingStarted"
  description = "OpenTelemetry service.namespace attribute, as the _monolithic template had it. Not a Kubernetes namespace - it is how traces group themselves in the X-Ray console, so it is the name to search for there"

  validation {
    condition     = length(var.otel_service_namespace) > 0
    error_message = "otel_service_namespace must not be empty."
  }
}
variable "otel_service_name" {
  type        = string
  default     = "GettingStartedService"
  description = "OpenTelemetry service.name attribute, which is what the node in the X-Ray service map is called"

  validation {
    condition     = length(var.otel_service_name) > 0
    error_message = "otel_service_name must not be empty."
  }
}
variable "enable_xray" {
  type        = bool
  default     = true
  description = "Whether the OTLP ingest collector forwards traces to X-Ray. True, because it is the only thing this variant demonstrates: with it false the collector still accepts traces from the sample application and exports them nowhere, so every pod is healthy, the application's log is clean, and the X-Ray console is empty"

  validation {
    # Pinned in the direction the project depends on (rules.md B-1). The failure is silent
    # on both sides - the application sees its exports accepted, and X-Ray simply has
    # nothing.
    condition     = var.enable_xray
    error_message = "enable_xray must stay true in this variant; it is the only export path configured. With it false the collector accepts traces and drops them, which looks identical to a working pipeline from inside the cluster."
  }
}
