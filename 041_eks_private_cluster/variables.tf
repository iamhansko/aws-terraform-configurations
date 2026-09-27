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
  default     = "private-cluster"
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
  default     = false
  description = "Whether the EKS API server endpoint is reachable from the internet. False, and this is the project. Every Kubernetes object here is created by an SSM Association running kubectl or helm on the bastion, which is inside the VPC, precisely so this can stay false - the rest of the repository sets it true instead so the kubectl and helm providers can reach the cluster from outside (rules.md E-1/E-2)"

  validation {
    condition     = var.endpoint_public_access == false
    error_message = "endpoint_public_access must stay false in this variant. Nothing here needs it: the Kubernetes objects are applied by SSM Associations on the bastion rather than by a Terraform provider, and turning it on removes the only thing this project demonstrates. To run with a public endpoint, use one of the other EKS projects as the starting point instead."
  }
}
variable "key_name" {
  type        = string
  default     = "private-cluster-key"
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
  description = "Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer Controller auto-discovers subnets for an internet-facing load balancer; without it the controller fails with 'couldn't auto-discover subnets' (rules.md G-1). The ALB is internet-facing even though the cluster is private - the nodes have no egress, but the load balancer still needs public subnets to accept traffic"

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
variable "enable_nat_gateway" {
  type        = bool
  default     = false
  description = "Whether the private subnets get a NAT gateway. False, which is what makes this a private cluster: the nodes reach AWS APIs only through the VPC endpoints below, and every container image has to come through the ECR pull-through cache. Turning it on would give the nodes ordinary internet egress and make both of those unnecessary"
}
variable "interface_endpoint_services" {
  type = set(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "sts",
    "eks",
    "ssm",
    "ssmmessages",
    "elasticloadbalancing",
  ]
  description = "Short service names for the interface VPC endpoints. Each is load-bearing with no NAT gateway: ecr.api and ecr.dkr to pull images, sts for IRSA, ec2 for the VPC CNI's ENI calls, eks for the kubelet, ssm and ssmmessages so the nodes can register with Systems Manager, elasticloadbalancing for the load balancer controller. Removing one makes that API unreachable from the cluster"

  validation {
    condition     = length(var.interface_endpoint_services) > 0
    error_message = "interface_endpoint_services must not be empty when enable_nat_gateway is false, or nothing in the private subnets can reach any AWS API."
  }
}
variable "eks_registry_account_id" {
  type        = string
  default     = "602401143452"
  description = "Account ID of the regional Amazon EKS container registry the pull-through cache reads from. Region-specific: AWS publishes a different account per region and a wrong value produces a cache rule that resolves to nothing. 602401143452 covers most commercial regions including ap-northeast-2, which is what the _monolithic template hardcoded - check the EKS add-on images documentation for other regions"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.eks_registry_account_id))
    error_message = "eks_registry_account_id must be a 12-digit AWS account ID."
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
  description = "Desired node count"

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
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload is created in. default, as the _monolithic template had it, which is also why the ALB's adoption stack tag reads default/<ingress name> (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_name" {
  type        = string
  default     = "nginx"
  description = "Name shared by the demo Deployment, Service and Ingress. The Ingress name is the second half of the ALB's adoption stack tag, so this value reaches AWS as a tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_image_repository" {
  type        = string
  default     = "nginx/nginx"
  description = "Upstream path of the demo image inside ECR Public, appended to this account's public cache prefix. Not a public.ecr.aws reference: the nodes have no internet route, so the image has to be pulled through the cache in this account"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*$", var.workload_image_repository))
    error_message = "workload_image_repository must be a lowercase image path such as nginx/nginx."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 1
  description = "Replicas for the demo Deployment"

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
variable "vscode_code_server_port" {
  type        = number
  default     = 8000
  description = "TCP port code-server binds to on the VS Code instance, and the port opened in its security group. Named at the root rather than left to the module default because it is half of the exposure allow_vscode_inbound_from_anywhere describes - the two are read together (rules.md B-3)"

  validation {
    condition     = var.vscode_code_server_port > 0 && var.vscode_code_server_port <= 65535
    error_message = "vscode_code_server_port must be a valid TCP port."
  }
}
variable "allow_vscode_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic on vscode_code_server_port from 0.0.0.0/0. True, so the IDE is reachable from a browser without a tunnel. Note what that means: code-server here has no authentication in front of it, so anyone who finds the address gets a shell on an instance whose role is cluster-admin on the EKS cluster. Set it false and reach the IDE through SSM Session Manager port forwarding, or leave it false and pass ingress_prefix_list_ids so only CloudFront edge locations can connect"
}
variable "allow_load_balancer_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the ALB security group accepts traffic on alb_port from 0.0.0.0/0. Separate from the VS Code switch because the two exposures are unrelated: this one reaches a demo nginx through the load balancer, the other one reaches an unauthenticated IDE. One variable for both would mean opening the IDE to change the demo, or the reverse"
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.0"
  description = "Pinned aws-load-balancer-controller chart version, installed by the bastion. Pinned even though the release is not in Terraform state, so a rebuilt bastion installs the same version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version."
  }
}
variable "override_coredns_image" {
  type        = bool
  default     = true
  description = "Whether to repoint the coredns Deployment at the pull-through cache. True reproduces the _monolithic template, which did this so the image comes from this account's ECR rather than the regional EKS registry directly. Note the coredns EKS addon reconciles its own Deployment, so this override can be reverted by the addon - it is a demonstration of the cache, not a durable setting"
}
variable "coredns_image_tag" {
  type        = string
  default     = "v1.12.1-eksbuild.2"
  description = "Tag of the cached coredns image used when override_coredns_image is true. Has to be a tag that exists upstream for the cluster's Kubernetes version, or the Deployment rolls into ImagePullBackOff"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.coredns_image_tag))
    error_message = "coredns_image_tag must look like v1.12.1-eksbuild.2."
  }
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
  description = "Directory on the VS Code instance where each bootstrap step drops its completion marker. This project chains four SSM steps through these markers rather than trusting depends_on, because wait_for_success_timeout_seconds does not reliably wait for the remote command to finish (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'. It cannot be null in this variant: the SSM steps that create the Kubernetes objects are ordered by these markers."
  }
}
variable "controller_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM step that installs the load balancer controller may take. It waits for the instance bootstrap first, then downloads the chart and waits for the Deployment"

  validation {
    condition     = var.controller_timeout_seconds > 0
    error_message = "controller_timeout_seconds must be positive."
  }
}
variable "controller_release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Helm release name for the load balancer controller. Named once here because the SSM step uses it three times - to install, to detect a failed release with no deployed revision, and to clear it (rules.md B-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.controller_release_name))
    error_message = "controller_release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "controller_helm_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long helm waits for the controller Deployment to become Available, rendered as its --timeout. Raised above helm's own 5 minute default on purpose: the controller's image is pulled through the pull-through cache, and the very first pull has to import it from ECR Public before any layer is served locally, so the pull alone can consume most of a 5 minute budget. Exceeding it reports 'Error: context deadline exceeded', which says nothing about why the pods are not ready"

  validation {
    condition     = var.controller_helm_timeout_seconds > 0
    error_message = "controller_helm_timeout_seconds must be positive."
  }

  validation {
    # Cross-variable condition, available since Terraform 1.9. helm has to lose the
    # race, not SSM: if the association gives up first, the failure is reported as an
    # SSM association in state 'Failed' with no output, whereas helm timing out leaves
    # its own message and the pod listing the step prints on failure.
    condition     = var.controller_helm_timeout_seconds < var.controller_timeout_seconds
    error_message = "controller_helm_timeout_seconds must be smaller than controller_timeout_seconds, so that a slow rollout surfaces as helm's own timeout rather than as an SSM association failure with no explanation."
  }
}
variable "workload_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM step that applies the demo workload may take. The first image pull goes through the pull-through cache, which fetches from upstream on demand and is slower than a warm pull"

  validation {
    condition     = var.workload_timeout_seconds > 0
    error_message = "workload_timeout_seconds must be positive."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README SSM association may take. It waits for the workload step, which is the last of the chain"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
