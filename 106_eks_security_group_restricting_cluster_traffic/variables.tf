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
  default     = "eks-cluster-sg"
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
  description = "CIDR block of the VPC. Subnet CIDRs are derived from it rather than listed"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones the VPC spans, by suffix. Two - a and c - which is the pair the _monolithic template's AzMapping actually wired"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two."
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
  description = "Name of the EKS cluster"

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
  default     = false
  description = <<-DESC
    Whether the cluster's API server has a public endpoint. False, and pinned false: this project's
    whole subject is what reaches the cluster and how, and every Kubernetes-side object here is
    created by an SSM Association on the workbench rather than by a Terraform provider so that this
    value can stay false.
  DESC

  validation {
    # Turning this on would not break anything by itself, which is exactly why it is
    # pinned: it would quietly remove the constraint that shapes the rest of the
    # configuration, and the next person would add a helm provider and wonder why
    # providers.tf argues against it at length (rules.md E-9, B-1).
    condition     = var.endpoint_public_access == false
    error_message = "endpoint_public_access must stay false in this variant. The load balancer controller chart is installed by an SSM Association on the workbench rather than by a helm provider, so nothing here needs a public endpoint, and turning it on removes the constraint the project exists to demonstrate. To run with a public endpoint, use the kubectl and helm providers instead, as 104_eks_fargate_efs_volume does."
  }
}

variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the API server answers on a VPC-internal address. True, and it has to be: with the public endpoint off this is the only endpoint there is"

  validation {
    condition     = var.endpoint_private_access
    error_message = "endpoint_private_access must be true. With endpoint_public_access false as well, the cluster would have no reachable API server at all."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane log types shipped to CloudWatch Logs"

  validation {
    condition = alltrue([for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "enabled_cluster_log_types entries must be among: api, audit, authenticator, controllerManager, scheduler."
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
  default     = "app-mng"
  description = "Name of the managed node group, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_labels" {
  type = map(string)
  default = {
    nodegroup = "app"
  }
  description = "Kubernetes labels applied to the nodes, as the _monolithic template set them"

  validation {
    condition     = alltrue([for key in keys(var.node_labels) : length(key) > 0])
    error_message = "node_labels keys must not be empty."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count, as the _monolithic template sized it"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 1
  description = "Minimum node count"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 2
  description = "Maximum node count"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess",
  ]
  description = "Managed policies on the node role, as the _monolithic template attached them. The last one is broader than a node needs for pulling; it is kept because the original had it, and it is the first thing to drop when narrowing this down"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

# --- VPC endpoints ---

variable "interface_endpoint_services" {
  type = set(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "sts",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "eks-auth",
    "elasticloadbalancing",
  ]
  description = <<-DESC
    Short service names for the interface endpoints, each expanded to com.amazonaws.<region>.<name>.

    The first seven are the ones the _monolithic template created. The last two are not, and the
    reason they are here is the revocation: with the cluster security group's blanket egress rule
    gone, the private subnets' NAT route is no longer usable from the cluster, so every AWS API the
    data plane calls has to arrive through an endpoint. These two were reached over NAT before and
    had nowhere else to go.

      eks-auth              The Pod Identity agent exchanges a service account token for role
                            credentials against the EKS Auth API, which is how the load balancer
                            controller is given its role at all. AWS names this endpoint as a
                            requirement for Pod Identity without outbound internet access
                            (https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html).
                            Without it the controller starts and then fails every AWS call, which
                            reads as an IAM problem rather than a networking one.
      elasticloadbalancing  The controller's own API. Nothing here asks it to build a load balancer,
                            so this is not what makes the apply succeed, but leaving it out would
                            mean the one thing the controller exists to call is the one thing it
                            cannot reach.

    Deliberately not here: eks. A managed node group is handed its API server endpoint and CA by EKS
    in generated user data, so nothing in the private subnets calls the EKS API, and the workbench
    calls it from a public subnet. Add it if self-managed nodes are ever introduced, because their
    bootstrap does introspect the cluster.
  DESC

  validation {
    condition     = length(var.interface_endpoint_services) > 0
    error_message = "interface_endpoint_services must not be empty."
  }
  validation {
    # The revocation removes the cluster's only other route to this API. Catching it
    # here beats catching it in the controller's log, which is where the failure
    # otherwise appears - as an AWS-side access denial, several steps away from the
    # missing endpoint that caused it (rules.md B-1).
    condition     = contains(var.interface_endpoint_services, "eks-auth")
    error_message = "interface_endpoint_services must include eks-auth. The load balancer controller gets its credentials from the EKS Auth API through the Pod Identity agent, and once aws_ssm_association.revoke_default_cluster_egress removes the cluster security group's blanket egress rule there is no other path to that API."
  }
}

variable "vpc_endpoint_security_group_name" {
  type        = string
  default     = "vpce-sg"
  description = "Name of the security group in front of the interface endpoints, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.vpc_endpoint_security_group_name)) && !startswith(var.vpc_endpoint_security_group_name, "sg-")
    error_message = "vpc_endpoint_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "endpoint_port" {
  type        = number
  default     = 443
  description = "Port the interface endpoints answer on, and the port both cluster egress rules allow. One value feeding the endpoint security group and the cluster's egress rules, so a rule cannot be written for a port the endpoints do not serve (rules.md B-5)"

  validation {
    condition     = var.endpoint_port > 0 && var.endpoint_port <= 65535
    error_message = "endpoint_port must be a valid TCP port."
  }
}

variable "create_cluster_egress_to_s3" {
  type        = bool
  default     = true
  description = "Whether to give the cluster security group an egress rule toward the S3 gateway endpoint's prefix list. True, and pinned true: ECR keeps image layers in S3, so without it a pull fetches the manifest and then stalls on the layers"

  validation {
    # This was a free choice while the blanket egress rule was still in place, because
    # the layer fetch fell through to NAT. It is not one now: the revocation removes
    # that fallback, so false means no image on the cluster pulls its layers at all,
    # and the failure arrives as ImagePullBackOff on every pod rather than as anything
    # naming this variable (rules.md B-1).
    condition     = var.create_cluster_egress_to_s3
    error_message = "create_cluster_egress_to_s3 must be true in this variant. aws_ssm_association.revoke_default_cluster_egress removes the cluster security group's blanket egress rule, so this rule is the only route to the S3 gateway endpoint - and ECR stores image layers in S3, so without it every image pull stalls after the manifest."
  }
}

# --- Cluster egress revocation ---

variable "revoke_cluster_egress_timeout_seconds" {
  type        = number
  default     = 1800
  description = <<-DESC
    How long the revocation SSM Association waits for success.

    It has to cover the workbench bootstrap, because the association's first statement waits for that
    bootstrap's marker file before it touches anything (rules.md D-5) - so this is mostly the
    instance's dnf/code-server/kubectl install time, and only then two EC2 API calls.

    This is also the timeout that decides how long the node group waits, since every
    cluster-dependent resource in main.tf is ordered after this association. If it expires the
    association reports "unexpected state 'Failed'" with no further detail, and the actual output has
    to be fetched through describe-association-executions (rules.md A-4 walks that path).
  DESC

  validation {
    condition     = var.revoke_cluster_egress_timeout_seconds >= 600
    error_message = "revoke_cluster_egress_timeout_seconds must be at least 600. The association waits on the workbench bootstrap marker before revoking anything, and that bootstrap installs code-server, kubectl, eksctl, helm and docker."
  }
}

# --- AWS Load Balancer Controller ---

variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned aws-load-balancer-controller chart version. The _monolithic template ran `helm install` with no --version, so the release drifted with whatever the repository held that day"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "controller_release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Helm release name for the controller"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.controller_release_name))
    error_message = "controller_release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "controller_upstream_image_path" {
  type        = string
  default     = "eks/aws-load-balancer-controller"
  description = <<-DESC
    Repository path of the controller image inside public.ecr.aws, which is where the chart points by
    default (image.repository is public.ecr.aws/eks/aws-load-balancer-controller, and image.tag is the
    chart's appVersion - v2.14.1 for chart 1.14.1).

    It is a variable because the root rewrites that repository: ECR Public is not a PrivateLink
    service, so once the cluster security group's blanket egress rule is revoked there is no path to
    public.ecr.aws from a node at all, and the image is pulled through the pull-through cache in
    main.tf instead. This is the upstream half of the cached repository name; the tag is left to the
    chart, so bumping the chart version needs no change here.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.controller_upstream_image_path))
    error_message = "controller_upstream_image_path must be a lowercase repository path such as eks/aws-load-balancer-controller, with no registry hostname and no tag."
  }
}

variable "controller_image_cache_prefix" {
  type        = string
  default     = null
  description = <<-DESC
    Repository prefix of the ECR pull-through cache rule for public.ecr.aws. Null derives it from
    project_name (rules.md B-4).

    Worth knowing before pinning it: a pull-through cache prefix is unique per registry, so it is
    account- and region-wide rather than per project. A literal shared value such as "ecr-public"
    makes a second project in the same account fail with
    PullThroughCacheRuleAlreadyExistsException, which is why the default is derived instead.

    One way the derived value can be rejected: ECR wants every separator followed by a letter or
    digit, while project_name's own validation allows a repeated hyphen. The plan then fails on
    "invalid value for ecr_repository_prefix (must be 'ROOT' or only include alphanumeric,
    underscore, period, hyphen, or slash characters)" - a message that does not describe the actual
    problem, since the value does consist only of those characters. Set this explicitly, or drop the
    repeated hyphen from project_name.
  DESC

  validation {
    condition     = var.controller_image_cache_prefix == null || can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.controller_image_cache_prefix))
    error_message = "controller_image_cache_prefix must be a lowercase ECR repository namespace (letters, digits and single separators), or null to derive it from project_name."
  }
}

variable "controller_helm_timeout_seconds" {
  type        = number
  default     = 600
  description = "Timeout passed to helm for the controller install"

  validation {
    condition     = var.controller_helm_timeout_seconds >= 120
    error_message = "controller_helm_timeout_seconds must be at least 120."
  }
}

variable "controller_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the controller SSM Association waits for success. Has to cover the instance bootstrap it waits on plus the helm install"

  validation {
    # If SSM gives up first the result is an unexplained "Failed"; if helm gives up
    # first its own message and the diagnostic pod listing end up in the association
    # output. The pair is what can be wrong, not either number alone
    # (rules.md B-1/E-9).
    condition     = var.controller_timeout_seconds > var.controller_helm_timeout_seconds
    error_message = "controller_timeout_seconds must be greater than controller_helm_timeout_seconds. If SSM times out first the association reports only \"unexpected state 'Failed'\"; letting helm time out first keeps its error and the pod diagnostics in the output (rules.md E-9)."
  }
}

variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = "Whether the controller creates one shared backend security group as the source of the node-side rules it writes. False: this project creates no load balancer, so there are no node-side rules to write, and a shared group would be an unused security group on the account (rules.md G-2)"
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
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker. Every SSM step waits on the previous step's marker rather than trusting depends_on (rules.md D-5)"

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
