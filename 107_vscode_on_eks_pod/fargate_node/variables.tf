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
  default     = "vscode-on-eks-pod-fargate"
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
  description = "Zones the regional NAT gateway is given an address in. One Elastic IP per entry, as the _monolithic template allocated two"

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
  description = "EKS cluster Kubernetes version. Keep both kubectl_download_version variables within one minor of this"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server has a public endpoint. True here, and pinned true, because the pod's manifests and the controller's Helm release are applied by providers running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run wherever
    # terraform runs. With a private-only endpoint they cannot connect, plan still passes, and the
    # failure appears mid-apply as a dial timeout that looks exactly like the destroy-ordering
    # problem rules.md D-4 describes (rules.md E-9).
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
# --- Fargate ---

variable "fargate_profile_name" {
  type        = string
  default     = "app-fargate-profile"
  description = "Name of the Fargate profile, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.fargate_profile_name))
    error_message = "fargate_profile_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "fargate_namespaces" {
  type        = list(string)
  default     = ["default", "kube-system"]
  description = <<-DESC
    Namespaces the Fargate profile selects, which is the only capacity this cluster has.

    Both, and kube-system is the one that is easy to leave out. With no node group, every pod in the
    cluster needs a selector that matches it - CoreDNS and the load balancer controller included - and a
    profile covering only "default" produces a cluster where the workload starts and DNS never does.
  DESC

  validation {
    condition     = length(var.fargate_namespaces) > 0
    error_message = "fargate_namespaces must name at least one namespace; a Fargate-only cluster with no matching selector has no capacity at all."
  }

  validation {
    condition     = contains(var.fargate_namespaces, "kube-system")
    error_message = "fargate_namespaces must include kube-system in this variant. There is no node group, so CoreDNS and the load balancer controller have nowhere else to run - and a cluster without them comes up with no DNS and no Ingress reconciliation, neither of which is reported as an error (rules.md B-1)."
  }
}

variable "coredns_compute_type" {
  type        = string
  default     = "Fargate"
  description = <<-DESC
    Where the CoreDNS pods run.

    Fargate, and this is the piece that makes a node-less cluster work at all. EKS ships the CoreDNS
    Deployment with an eks.amazonaws.com/compute-type: ec2 annotation, and with that annotation its pods
    stay Pending forever on a cluster that has no EC2 nodes - so the cluster comes up with no working DNS
    and nothing says why.

    Setting it here removes the annotation declaratively, which is why this variant needs no
    rollout-restart step (contrast rules.md E-4, which triggers a rollout for a Deployment whose placement
    cannot be expressed as addon configuration).
  DESC

  validation {
    condition     = var.coredns_compute_type == "Fargate"
    error_message = "coredns_compute_type must be Fargate in this variant, because the cluster has no EC2 nodes for the pods to be scheduled on (rules.md B-1)."
  }
}

# --- Storage ---
#
# EFS and nothing else, which is a property of Fargate rather than a choice. EBS cannot be attached to a
# Fargate pod at all, and the EFS CSI node driver is built into the Fargate runtime - so there is no
# addon to install here, and only static provisioning is available.
#
# The _monolithic template created the file system, its mount targets and its security group, and then
# mounted none of them: its pod manifest was identical to the base variant's apart from one IRSA
# annotation.

variable "efs_performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode, as the _monolithic template set it"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "efs_performance_mode must be generalPurpose or maxIO."
  }
}

variable "efs_volume_mount_path" {
  type        = string
  default     = "/home/coder/project"
  description = "Where the EFS volume is mounted in the pod. A subdirectory rather than /home/coder itself, because mounting over the home directory hides the .config and .kube mounts the pod needs"

  validation {
    condition     = can(regex("^/", var.efs_volume_mount_path))
    error_message = "efs_volume_mount_path must be an absolute path."
  }
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = <<-DESC
    Pinned aws-load-balancer-controller chart version.

    The _monolithic template ran `helm install` with no --version from the workbench's user data, and that
    command never ran at all: the line before it was `exec bash`, which replaces the shell and discards
    every remaining line of the script. So the controller was never installed, the Ingress was never
    claimed, and the pre-created load balancer never got a listener.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "enable_backend_security_group" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the controller may use its shared backend security group: the k8s-traffic-<cluster>-<hash>
    group it creates, attaches to every load balancer it manages, and names as the source of the
    pod-side rules it writes.

    False here, which is the pre-v2.3.0 behaviour. The _monolithic template left it at the controller's
    own default of true and set the manage-backend-security-group-rules annotation to match, so the ALB
    ended up carrying two security groups: the frontend group the template declared, and that shared
    group the controller created. This variant requires every group on the load balancer to be a
    Terraform resource, so it gives up having the controller write the pod-side rules and declares
    that rule itself - load_balancer_to_pods in main.tf (rules.md G-2).
  DESC

  validation {
    # The second row of the table in rules.md G-2, and the reason this is a constant condition rather
    # than a cross-variable one: the Ingress does not set manage-backend-security-group-rules, so
    # there is no pairing left to express - only this one value, which the controller reads as
    # permission to put a group of its own on the load balancer. Nothing reports the difference: plan
    # and apply both succeed either way, and the extra group shows up only in describe-load-balancers
    # (rules.md B-1).
    condition     = var.enable_backend_security_group == false
    error_message = "enable_backend_security_group must stay false in this variant, whose point is that every security group attached to the ALB is a Terraform resource - with it true the controller creates its shared k8s-traffic group and attaches that to the load balancer as well. To run with it true, set the manage-backend-security-group-rules annotation on the Ingress and delete the load_balancer_to_pods rule from the root, which hands the pod-side rules back to the controller (rules.md G-2)."
  }
}

# --- The load balancer in front of the pod ---

variable "alb_security_group_name" {
  type        = string
  default     = "vscode-alb-sg"
  description = "Name of the frontend security group the ALB carries. The _monolithic template called it alb-sg and then built the load balancer with the VPC default group instead, so the group the Ingress annotation named and the group the load balancer had were different"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-")
    error_message = "alb_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\"."
  }
}

variable "alb_allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB's frontend security group accepts traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default - and code-server in the pod runs with auth disabled, so anyone who reaches this gets a terminal with cluster-admin"
}

variable "alb_listener_port" {
  type        = number
  default     = 80
  description = "Port the ALB listens on, as the _monolithic template's listener used. Plain HTTP, so the frontend security group opens the same port"

  validation {
    condition     = var.alb_listener_port > 0 && var.alb_listener_port <= 65535
    error_message = "alb_listener_port must be a valid TCP port."
  }
}

variable "alb_name" {
  type        = string
  default     = null
  description = "Name of the pre-created ALB. Null generates a unique name, which is what lets this project be deployed twice in one account - adoption is decided by tags, never by the name. The _monolithic template fixed it to \"vscode\", so a tag mismatch surfaced as a name collision instead (rules.md G-3)"

  validation {
    condition     = var.alb_name == null || can(regex("^[a-zA-Z0-9-]{1,32}$", var.alb_name))
    error_message = "alb_name must be 32 characters or fewer of letters, digits and hyphens, or null."
  }
}

# --- The code-server pod ---

variable "vscode_pod_name" {
  type        = string
  default     = "vscode"
  description = "Name shared by the pod's objects, as the _monolithic template named them. Also the second half of the load balancer's adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.vscode_pod_name))
    error_message = "vscode_pod_name must be a valid lowercase RFC 1123 label."
  }
}

variable "vscode_pod_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the pod's objects are created in, as the _monolithic template placed them. The first half of the adoption stack tag"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.vscode_pod_namespace))
    error_message = "vscode_pod_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "vscode_pod_image" {
  type        = string
  default     = "codercom/code-server:4.108.2-fedora"
  description = "Image the pod runs. The tag suffix names the base distribution - 4.108.2-fedora and 4.108.2-39 are the same digest, while a bare 4.108.2 is Debian. The _monolithic template used -39 and then ran dnf inside the container, which only works because of that"

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s:]+$", var.vscode_pod_image))
    error_message = "vscode_pod_image must include an explicit tag."
  }
}

variable "vscode_pod_port" {
  type        = number
  default     = 8080
  description = "Port code-server listens on inside the pod. One value reaching the container port, the Service, the Ingress backend and the target group's health check (rules.md B-5)"

  validation {
    condition     = var.vscode_pod_port > 0 && var.vscode_pod_port <= 65535
    error_message = "vscode_pod_port must be a valid TCP port."
  }
}

variable "vscode_pod_cpu_request" {
  type        = string
  default     = "4"
  description = <<-DESC
    CPU the pod requests.

    Four rather than the _monolithic template's three, because Fargate does not give a pod what it asked
    for: it rounds the sum of the pod's requests up to the nearest supported vCPU/memory pair and bills
    that. A 3 vCPU / 12 Gi request lands on the 4 vCPU / 16 Gi size anyway, so asking for 3 pays for 4
    while telling the scheduler something that is not true of the pod it gets.
  DESC

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?m?$", var.vscode_pod_cpu_request))
    error_message = "vscode_pod_cpu_request must be a Kubernetes CPU quantity (e.g. 3, 500m)."
  }
}

variable "vscode_pod_memory_request" {
  type        = string
  default     = "16Gi"
  description = "Memory the pod requests. Raised with the CPU request to match a supported Fargate size exactly, for the same reason - 4 vCPU allows 8 to 30 Gi, and 16 Gi is what a 12 Gi request would have been rounded to"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(Ki|Mi|Gi|Ti|K|M|G|T)?$", var.vscode_pod_memory_request))
    error_message = "vscode_pod_memory_request must be a Kubernetes memory quantity (e.g. 12Gi)."
  }
}

variable "vscode_pod_install_tools" {
  type        = bool
  default     = true
  description = "Whether an init container installs kubectl, helm, eksctl, terraform and the AWS CLI into the pod. True, because that tooling is the point of putting an IDE in the cluster"
}

variable "vscode_pod_kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build installed into the pod, as <version>/<release-date>. The _monolithic template pinned a 1.34.2 build here and a 1.33.3 build on the workbench, against the same cluster"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.vscode_pod_kubectl_download_version))
    error_message = "vscode_pod_kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "vscode_pod_cluster_access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  description = "Cluster access policy associated with the pod's IAM role, as the _monolithic template associated. Cluster admin, which combined with auth-disabled code-server on a public load balancer is worth narrowing before leaving this up"

  validation {
    condition     = can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.vscode_pod_cluster_access_policy_arn))
    error_message = "vscode_pod_cluster_access_policy_arn must be an EKS cluster access policy ARN."
  }
}

variable "vscode_pod_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = "Managed policies attached to the pod's IAM role, as the _monolithic template attached. AdministratorAccess: the pod is a workbench, and it is also reachable from the internet without authentication - narrow this before leaving it up"

  validation {
    condition     = alltrue([for arn in var.vscode_pod_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "vscode_pod_iam_policy_arns must contain valid IAM policy ARNs."
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
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench. The _monolithic template downloaded a release tarball from GitHub by version, which is what this keeps - pinned rather than resolved at boot"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker. The _monolithic template used `sleep 180` instead, which is the same bet with worse odds (rules.md D-5)"

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
