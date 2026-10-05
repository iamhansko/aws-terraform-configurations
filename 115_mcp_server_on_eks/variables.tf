variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}

variable "project_name" {
  type        = string
  default     = "eks-mcp-server"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the workbench"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones the VPC spans, by suffix. Two - a and c - exactly the pair the _monolithic template's AzMapping defined"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two, and so does an ALB."
  }
}

variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the regional NAT gateway is given an address in. One Elastic IP per entry"

  validation {
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes; an address in a zone with no subnet is routed nowhere."
  }
}

# --- EKS cluster ---

variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster. Also the elbv2.k8s.aws/cluster tag on the pre-created load balancer, which is one of the three tags adoption depends on (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version. Keep kubectl_download_version within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the workload's manifests and the controller's Helm release are applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run
    # wherever terraform runs. With a private-only endpoint they cannot connect, plan still
    # passes, and the failure appears mid-apply as a dial timeout that looks exactly like
    # the destroy-ordering problem rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its manifests and Helm release are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoint. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Node group ---

variable "node_group_name" {
  type        = string
  default     = "al2023"
  description = "Name of the managed node group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version from the workbench's user data"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller uses one shared backend security group as the source of the node-side rules it writes"

  validation {
    # The Ingress names its own frontend security group and does not set
    # manage-backend-security-group-rules, so the controller writes no node-side rules at
    # all and this project declares them itself
    # (aws_vpc_security_group_ingress_rule.load_balancer_to_pods). That is the second row of
    # the table in rules.md G-2, and it is the row that requires false (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must be false in this variant. The Ingress names its own frontend security group and does not set manage-backend-security-group-rules, so the node-side rule is declared in Terraform (load_balancer_to_pods). To let the controller manage it instead, add that annotation and set this to true (rules.md G-2)."
  }
}

# --- The load balancer in front of the MCP server ---

variable "alb_security_group_name" {
  type        = string
  default     = "mcp-server-alb-sg"
  description = "Name of the frontend security group the ALB carries, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "alb_allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB's frontend security group accepts traffic from 0.0.0.0/0. True reproduces the _monolithic template's default - and this endpoint runs an MCP server with --allow-write, so restricting it is worth doing before leaving it up"
}

variable "alb_name" {
  type        = string
  default     = null
  description = "Name of the pre-created ALB. Null generates a unique name, which is what lets this project be deployed twice in one account - adoption is decided by tags, never by the name (rules.md G-3)"

  validation {
    condition     = var.alb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.alb_name))
    error_message = "alb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}

variable "mcp_server_port" {
  type        = number
  default     = 8000
  description = "Port the proxy listens on. One value reaching the container port, the probes, the Service, the Ingress backend, the health check annotation and the node-side security group rule (rules.md B-5)"

  validation {
    condition     = var.mcp_server_port > 0 && var.mcp_server_port <= 65535
    error_message = "mcp_server_port must be a valid TCP port."
  }
}

# --- Custom domain and TLS ---

variable "create_custom_domain" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether to issue an ACM certificate for mcp.<mcp_server_domain>, validate it through Route 53, and point
    a record at the load balancer.

    False by default, which is a deliberate departure from the _monolithic template. That one read the hosted
    zone with a data source unconditionally, and a data source resolves during plan - so in an account
    without a public hosted zone for the domain, the plan fails before it can show anything, including for
    someone who only wanted to read it.

    With this false the ALB serves plain HTTP on the MCP port and the endpoint is reached by the load
    balancer's own name. With it true the frontend security group opens 443 instead, the Ingress gets the
    certificate and the ssl-redirect annotation, and the URL is https://mcp.<domain>/mcp (rules.md B-4).
  DESC
}

variable "mcp_server_domain" {
  type        = string
  default     = "example.com"
  description = "Domain whose Route 53 public hosted zone holds the mcp record. Only used when create_custom_domain is true"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.mcp_server_domain))
    error_message = "mcp_server_domain must be a valid lowercase DNS name with at least two labels (e.g. example.com)."
  }
}

variable "mcp_record_subdomain" {
  type        = string
  default     = "mcp"
  description = "Label prefixed to mcp_server_domain for the record and the certificate, as the _monolithic template used"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.mcp_record_subdomain))
    error_message = "mcp_record_subdomain must be a valid lowercase DNS label."
  }
}

variable "https_port" {
  type        = number
  default     = 443
  description = "Port the ALB listens on when create_custom_domain is true. The certificate is what makes this a TLS listener rather than a second plaintext one"

  validation {
    condition     = var.https_port > 0 && var.https_port <= 65535
    error_message = "https_port must be a valid TCP port."
  }
}

# --- Image build ---

variable "ecr_repository_name" {
  type        = string
  default     = "eks-mcp-server"
  description = "Name of the ECR repository the built image is pushed to, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._/-]*[a-z0-9])?$", var.ecr_repository_name))
    error_message = "ecr_repository_name must be lowercase letters, digits, dots, underscores, slashes and hyphens."
  }
}

variable "codebuild_project_name" {
  type        = string
  default     = "image-builder"
  description = "Name of the CodeBuild project that builds the image, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.codebuild_project_name))
    error_message = "codebuild_project_name must be 2-255 characters of letters, digits, underscores and hyphens."
  }
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag the built image carries, as the _monolithic template used"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag must be a valid container image tag."
  }
}

variable "start_build_on_apply" {
  type        = bool
  default     = true
  description = "Whether the apply starts a build. True, because nothing else pushes the image and the Deployment cannot start without it. The invocation re-runs only when its input changes, so an ordinary second apply does not start a second build"
}

variable "build_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the SSM step that waits for the image waits before failing. The build has to finish before the Deployment's pods can pull, and nothing in the Terraform graph expresses \"the build succeeded\" - only \"a build was started\""

  validation {
    condition     = var.build_wait_timeout_seconds >= 600
    error_message = "build_wait_timeout_seconds must be at least 600; the image installs a Python toolchain and a package from PyPI."
  }
}

# --- MCP server pod permissions ---

variable "mcp_server_iam_policy_arns" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Managed policies attached to the MCP server pod's IAM role.

    Empty, as the _monolithic template left it. What the server can actually do comes from the EKS access
    entry the root creates for this role, which is cluster access rather than AWS API access.

    Worth reading twice before adding anything: the server runs with --allow-write and
    --allow-sensitive-data-access, so a language model on the other end of the MCP endpoint inherits
    everything attached here (rules.md A-5).
  DESC

  validation {
    condition     = alltrue([for arn in var.mcp_server_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "mcp_server_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "mcp_server_cluster_access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  description = <<-DESC
    Cluster access policy associated with the MCP server pod's role.

    Cluster admin, which is what makes the eks-mcp-server useful and also what makes it dangerous: with
    --allow-write set, this is full control of the cluster exposed over an HTTP endpoint. The
    _monolithic template created the access entry with no policy association at all, so the role was mapped
    and authorised for nothing - the server could authenticate and then be denied everything.

    Narrow this to a namespace-scoped policy for anything beyond a demo.
  DESC

  validation {
    condition     = can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.mcp_server_cluster_access_policy_arn))
    error_message = "mcp_server_cluster_access_policy_arn must be an EKS cluster access policy ARN."
  }
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts code-server traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default; code-server runs with auth disabled, so restrict this for anything beyond a demo"
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build against a 1.36 cluster"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench. Pinned rather than resolved from the GitHub releases API at boot, which is what the _monolithic template did - an API rate limit produced an empty version and a 404"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}

# --- Names the adoption tag is built from ---
#
# Variables rather than literals because three places have to agree: the Ingress the module
# creates, the pre-created load balancer's ingress.k8s.aws/stack tag, and the verification
# command that reads the address back. A disagreement is not an error - the controller simply
# builds a second load balancer (rules.md G-3).

variable "mcp_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the MCP server's objects are created in, as the _monolithic template placed them. The first half of the adoption tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.mcp_namespace))
    error_message = "mcp_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "mcp_ingress_name" {
  type        = string
  default     = "mcp"
  description = "Name of the Ingress, as the _monolithic template named it. The second half of the adoption tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.mcp_ingress_name))
    error_message = "mcp_ingress_name must be a valid lowercase RFC 1123 label."
  }
}
variable "marker_wait_timeout_seconds" {
  type        = number
  default     = 600
  description = <<-DESC
    How long each SSM step waits for the marker file it depends on before failing with a message.

    It exists so that the failure says something. Both steps here open by waiting on a marker, and
    without a ceiling that wait is an unbounded `until ... sleep` loop: the command never returns, the
    association sits at Pending, and after half an hour Terraform reports

      Error: waiting for SSM Association (...) create: timeout while waiting for state to become
      'Success' (last state: 'Pending', timeout: 30m0s)

    against a UUID, naming neither the instance nor the thing it was waiting for. That is what this
    project's apply produced when the image build failed and the image marker was therefore never
    written. With a ceiling the step exits non-zero, SSM records Failed, and the reason - including the
    command that reads the build - is in the invocation's standard error where rules.md A-4's procedure
    finds it.

    Ten minutes against a bootstrap that normally finishes in about three. Note that in the image step
    this budget is shared with the ECR poll that follows it, inside one build_wait_timeout_seconds.
  DESC

  validation {
    condition     = var.marker_wait_timeout_seconds > 0
    error_message = "marker_wait_timeout_seconds must be positive."
  }
  validation {
    # The script has to give up before SSM and Terraform do, or its message is never written and the
    # bare Pending is all that is left - the same constraint rules.md E-9 states for a helm timeout
    # inside an association (rules.md B-1).
    condition     = var.marker_wait_timeout_seconds < var.build_wait_timeout_seconds && var.marker_wait_timeout_seconds < var.readme_timeout_seconds
    error_message = "marker_wait_timeout_seconds must be less than both build_wait_timeout_seconds and readme_timeout_seconds. The wait loop has to give up before the association's own budget expires, or the loop is still running when SSM stops it and the only thing reported is \"last state: 'Pending'\" - which is the message this ceiling exists to replace."
  }
}
variable "http_port" {
  type        = number
  default     = 80
  description = <<-DESC
    Plain-HTTP port the ALB listens on. Eighty, which is what the AWS Load Balancer Controller would
    default to anyway - the value exists so that the default is written down and governs the frontend
    security group and the output URL as well as the listener.

    It is not the MCP server's port. That is mcp_server_port, which the pod listens on and the target
    group forwards to, and conflating the two is what made the endpoint unreachable: the security group
    opened 8000 while the listener was on 80 (rules.md G-1 keeps those two rules separate for this
    reason).

    With create_custom_domain set, this stays in the listener set as the port the ssl-redirect
    annotation redirects from.
  DESC

  validation {
    condition     = var.http_port > 0 && var.http_port <= 65535
    error_message = "http_port must be a valid TCP port."
  }
}
