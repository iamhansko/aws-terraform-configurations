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
  default     = "kubernetes-on-ec2"
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
  description = "CIDR block of the VPC. Must not overlap pod_network_cidr, or pod addresses and node addresses collide"

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
    error_message = "availability_zone_suffixes must name at least two zones; the control plane and the worker are placed in different ones."
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

# --- Kubernetes ---

variable "kubernetes_minor_version" {
  type        = string
  default     = "v1.34"
  description = <<-DESC
    Kubernetes minor version installed on both machines, as the pkgs.k8s.io repository path spells it.

    Pinned rather than read from dl.k8s.io/release/stable.txt during boot, which is what the
    _monolithic template did. That made every apply install whatever was current, and it made the two
    machines independent: booting either side of a release put them on different minors, which
    kubeadm join rejects. It also had no relationship to the kubectl downloaded onto the workbench, so
    the client could drift outside the supported one-minor skew.
  DESC

  validation {
    condition     = can(regex("^v1\\.[0-9]+$", var.kubernetes_minor_version))
    error_message = "kubernetes_minor_version must look like v1.34 - a minor version, not a patch release, because that is what the package repository path takes."
  }
}

variable "pod_network_cidr" {
  type        = string
  default     = "192.168.0.0/16"
  description = "Pod network CIDR. One value, handed to kubeadm init as --pod-network-cidr and to Calico's Installation resource as its IP pool. The _monolithic template also used one value, but propagated it into Calico by downloading the upstream custom-resources.yaml and running sed on it (rules.md B-5)"

  validation {
    condition     = can(cidrhost(var.pod_network_cidr, 0))
    error_message = "pod_network_cidr must be a valid IPv4 CIDR block."
  }
  validation {
    # Two /16s that overlap is not an error anything reports - it is pods that cannot
    # reach the node they run on (rules.md B-1).
    condition     = cidrhost(var.pod_network_cidr, 0) != cidrhost(var.vpc_cidr_block, 0)
    error_message = "pod_network_cidr must not start at the same address as vpc_cidr_block. Overlapping pod and node networks produce routing failures rather than an error."
  }
}

variable "calico_version" {
  type        = string
  default     = "v3.32.2"
  description = "Calico release whose tigera-operator manifest is applied. Pinned rather than resolved from the GitHub releases API at boot, which is what the _monolithic template did - so the CNI version depended on the day and an API rate limit produced an empty version string and a 404"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.calico_version))
    error_message = "calico_version must look like v3.32.2."
  }
}

variable "calico_encapsulation" {
  type        = string
  default     = "VXLANCrossSubnet"
  description = "Calico encapsulation mode. VXLANCrossSubnet is what works on EC2 without touching routing: the control plane and the worker sit in different subnets here, and traffic between them is encapsulated while traffic inside a subnet is not"

  validation {
    condition     = contains(["IPIP", "VXLAN", "IPIPCrossSubnet", "VXLANCrossSubnet", "None"], var.calico_encapsulation)
    error_message = "calico_encapsulation must be one of: IPIP, VXLAN, IPIPCrossSubnet, VXLANCrossSubnet, None."
  }
}

# --- Instances ---

variable "control_plane_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the control plane. kubeadm's preflight check requires two CPUs, so nothing smaller than a t3.medium passes"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.control_plane_instance_type))
    error_message = "control_plane_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "worker_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the worker node"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.worker_instance_type))
    error_message = "worker_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench and ingress security groups accept traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default; code-server runs with auth disabled, so restrict this for anything beyond a demo"
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_minor_version - outside that the client is off the supported skew"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench. Pinned rather than resolved from the GitHub releases API at boot, which is what the _monolithic template did"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on each instance where every bootstrap stage drops its completion marker. The SSM steps wait on these markers rather than trusting depends_on (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

# --- Ingress and workload ---

variable "ingress_host_name" {
  type        = string
  default     = "example.com"
  description = "Host the whoami Ingress matches. No DNS record is created for it anywhere - the workbench writes it into its own /etc/hosts pointing at the ingress Elastic IP, which is what makes `curl example.com` work from the IDE terminal and nowhere else"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.ingress_host_name))
    error_message = "ingress_host_name must be a valid lowercase DNS name with at least two labels (e.g. example.com)."
  }
}

variable "ingress_ports" {
  type = map(number)
  default = {
    http  = 80
    https = 443
  }
  description = "Ports the ingress security group opens and the Traefik DaemonSet binds as hostPorts. One map feeding both, so the group cannot open a port Traefik does not bind or miss one it does (rules.md B-5). The _monolithic template's group opened only 80, leaving the 443 hostPort listening behind a closed door"

  validation {
    condition     = contains(keys(var.ingress_ports), "http")
    error_message = "ingress_ports must include an \"http\" entry; the whoami Ingress is served on the web entrypoint."
  }
  validation {
    condition     = alltrue([for port in values(var.ingress_ports) : port > 0 && port <= 65535])
    error_message = "ingress_ports values must be valid TCP ports."
  }
}

variable "traefik_chart_version" {
  type        = string
  default     = "41.6.0"
  description = "Pinned Traefik chart version. The _monolithic template ran `helm upgrade --install` with no --version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.traefik_chart_version))
    error_message = "traefik_chart_version must be a three-part semantic version."
  }
}

variable "traefik_namespace" {
  type        = string
  default     = "traefik"
  description = "Namespace the Traefik release is installed into"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.traefik_namespace))
    error_message = "traefik_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "traefik_container_ports" {
  type = map(number)
  default = {
    http  = 8000
    https = 8443
  }
  description = "Ports Traefik listens on inside the container, mapped to ingress_ports as hostPorts. High ports, so the container can drop every capability except NET_BIND_SERVICE and still bind - which is what the chart values here rely on"

  validation {
    condition     = length(setsubtract(keys(var.traefik_container_ports), ["http", "https"])) == 0
    error_message = "traefik_container_ports keys must be http or https - the two entrypoint names the chart defines."
  }
  validation {
    condition     = alltrue([for port in values(var.traefik_container_ports) : port > 0 && port <= 65535])
    error_message = "traefik_container_ports values must be valid TCP ports."
  }
}

variable "workload_name" {
  type        = string
  default     = "whoami"
  description = "Name of the demo Deployment, Service and the Ingress backend"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 label."
  }
}

variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload is created in"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "workload_image" {
  type        = string
  default     = "traefik/whoami"
  description = "Image the demo Deployment runs. traefik/whoami echoes the request it received, which is what makes the two Ingress paths distinguishable"

  validation {
    condition     = length(var.workload_image) > 0
    error_message = "workload_image must not be empty."
  }
}

variable "workload_replicas" {
  type        = number
  default     = 2
  description = "Replica count of the demo Deployment. Two, so repeated requests land on different pods and the echoed hostname changes - which is the visible evidence that the Service is load balancing"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}

variable "workload_container_port" {
  type        = number
  default     = 80
  description = "Port the demo container listens on"

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be a valid TCP port."
  }
}

# --- SSM step timeouts ---

# Every one of these associations runs a script whose own waits have to fit inside the
# association's budget, and the failure when they do not is the worst one this project
# can produce: the command is still running when the provider stops polling, so the
# association's last state is 'Pending' rather than 'Failed'. A 'Failed' association
# leaves a command invocation to read the real error out of (rules.md A-4); a 'Pending'
# one leaves nothing but the association ID.
#
# So the inner timeouts below are variables rather than literals - a literal is
# invisible to a validation (rules.md B-3) - and each outer budget is checked against
# the sum of the inner ones it has to cover (rules.md B-1/E-9).

variable "marker_wait_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long a step waits for the previous step's marker file before giving up and naming it. Generous, because the first step waits on a full kubeadm init, but bounded: an unbounded wait is what turns a stalled earlier step into a 'Pending' association with nothing to read (rules.md D-5)"

  validation {
    condition     = var.marker_wait_timeout_seconds >= 300
    error_message = "marker_wait_timeout_seconds must be at least 300; the first marker is written at the end of the control plane bootstrap."
  }
}

variable "calico_operator_timeout_seconds" {
  type        = number
  default     = 300
  description = "Timeout for the tigera-operator Deployment rollout, inside the Calico step"

  validation {
    condition     = var.calico_operator_timeout_seconds >= 60
    error_message = "calico_operator_timeout_seconds must be at least 60."
  }
}

variable "calico_crd_timeout_seconds" {
  type        = number
  default     = 180
  description = "Timeout for each wait inside the Calico step that depends on the operator registering something: two waits per CRD (one for the CRD to be created, one for it to be Established) and the loop waiting for the operator to create the calico-node DaemonSet from the Installation. 180 rather than 300, because five of these now run in series and the registration itself takes seconds - the one observed failure missed by three"

  validation {
    condition     = var.calico_crd_timeout_seconds >= 60
    error_message = "calico_crd_timeout_seconds must be at least 60."
  }
}

variable "calico_node_timeout_seconds" {
  type        = number
  default     = 600
  description = "Timeout for the calico-node DaemonSet rollout. The longest wait in the Calico step, because it covers an image pull on every node"

  validation {
    condition     = var.calico_node_timeout_seconds >= 120
    error_message = "calico_node_timeout_seconds must be at least 120."
  }
}

variable "cni_timeout_seconds" {
  type        = number
  default     = 2400
  description = "How long the Calico SSM Association waits for success. It blocks on the control plane's bootstrap marker first, so this has to cover a full kubeadm init as well as the CNI rollout"

  validation {
    condition     = var.cni_timeout_seconds >= 600
    error_message = "cni_timeout_seconds must be at least 600; it waits on kubeadm init before it starts."
  }

  validation {
    # The step's own waits, in series: the operator rollout, four CRD waits (create then
    # Established, for each of two CRDs), the DaemonSet-exists loop, and the DaemonSet
    # rollout - so five multiples of calico_crd_timeout_seconds. The marker wait is
    # excluded on purpose: it has its own bound and fails with a message naming the
    # marker, so it does not need to fit inside this budget to stay diagnosable.
    condition     = var.cni_timeout_seconds >= var.calico_operator_timeout_seconds + (5 * var.calico_crd_timeout_seconds) + var.calico_node_timeout_seconds + 300
    error_message = "cni_timeout_seconds must leave 300 seconds of headroom over the Calico step's own waits (calico_operator_timeout_seconds + 5 x calico_crd_timeout_seconds + calico_node_timeout_seconds). If SSM gives up first the association reports 'Pending' and there is no command invocation to read the real error out of (rules.md B-1/E-9)."
  }
}

variable "worker_ready_timeout_seconds" {
  type        = number
  default     = 300
  description = <<-DESC
    Timeout for the "kubectl wait --for=condition=Ready node/<worker>" that opens the
    Traefik step, because the chart pins its DaemonSet to that node with a nodeSelector.

    This was a literal 600s, and that is how the Traefik step came to have a budget it
    could not meet: 600 here plus 600 for helm is exactly
    ingress_controller_timeout_seconds, so the association could still be running at
    the moment the provider stopped waiting. A literal cannot participate in the
    validation that is supposed to catch that (rules.md B-3).

    300 is enough by construction: this step only starts once the Calico marker exists,
    and that marker is written after calico-node has rolled out - which cannot happen
    on a node that never joined.
  DESC

  validation {
    condition     = var.worker_ready_timeout_seconds >= 60
    error_message = "worker_ready_timeout_seconds must be at least 60."
  }
}

variable "ingress_controller_timeout_seconds" {
  type        = number
  default     = 1500
  description = "How long the Traefik SSM Association waits for success. It has to cover worker_ready_timeout_seconds and traefik_helm_timeout_seconds in series, plus the margin below"

  validation {
    condition     = var.ingress_controller_timeout_seconds >= 600
    error_message = "ingress_controller_timeout_seconds must be at least 600."
  }
}

variable "traefik_helm_timeout_seconds" {
  type        = number
  default     = 600
  description = "Timeout passed to helm for the Traefik install"

  validation {
    condition     = var.traefik_helm_timeout_seconds >= 120
    error_message = "traefik_helm_timeout_seconds must be at least 120."
  }
}

variable "workload_rollout_timeout_seconds" {
  type        = number
  default     = 300
  description = "Timeout for the whoami Deployment rollout, inside the workload step"

  validation {
    condition     = var.workload_rollout_timeout_seconds >= 60
    error_message = "workload_rollout_timeout_seconds must be at least 60."
  }
}

variable "workload_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the workload SSM Association waits for success. It has to cover workload_rollout_timeout_seconds with headroom"

  validation {
    condition     = var.workload_timeout_seconds >= 300
    error_message = "workload_timeout_seconds must be at least 300."
  }

  validation {
    condition     = var.workload_timeout_seconds >= var.workload_rollout_timeout_seconds + 300
    error_message = "workload_timeout_seconds must leave 300 seconds of headroom over workload_rollout_timeout_seconds, so kubectl reports a failed rollout before SSM abandons the command (rules.md B-1/E-9)."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association waits for success"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}

# A cross-variable validation, which Terraform has allowed since 1.9 - the repository
# is on >= 1.9. The constraint is about the set, not about any number on its own: if SSM
# gives up first the association reports a bare timeout, while letting the inner command
# give up first keeps its own error and the diagnostic output beside it in the
# association result (rules.md B-1/E-9).
#
# This validation used to compare the budget against helm's timeout alone, and it
# passed: 1200 >= 600 + 300. What it could not see was the 600-second
# "kubectl wait node" that runs before helm in the same script, because that number was
# a literal rather than a variable. The two together already equalled the budget, so the
# step could run out of time without ever reaching a state the provider could report -
# a validation that is blind to one term in the sum is worse than none (rules.md B-3).
variable "ingress_controller_timeout_margin_seconds" {
  type        = number
  default     = 300
  description = "How much longer the Traefik SSM Association waits than its own commands do. The margin is what keeps SSM from timing out first and hiding their errors"

  validation {
    condition     = var.ingress_controller_timeout_margin_seconds >= 60
    error_message = "ingress_controller_timeout_margin_seconds must be at least 60."
  }

  validation {
    # worker_ready_timeout_seconds is counted twice: the step waits for the Node object
    # to be created and then for it to report Ready, each with that timeout.
    condition     = var.ingress_controller_timeout_seconds >= (2 * var.worker_ready_timeout_seconds) + var.traefik_helm_timeout_seconds + var.ingress_controller_timeout_margin_seconds
    error_message = "ingress_controller_timeout_seconds must be at least twice worker_ready_timeout_seconds (the Node create wait and the Node Ready wait) plus traefik_helm_timeout_seconds plus ingress_controller_timeout_margin_seconds. Those waits run in series inside the association, so if their sum reaches the budget the command can still be running when the provider stops polling - and an association abandoned on 'Pending' leaves no command invocation to read the real error out of (rules.md A-4/E-9)."
  }
}

variable "calico_block_size" {
  type        = number
  default     = 26
  description = "Prefix length of each per-node block Calico carves out of the pod CIDR. 26, as the upstream custom-resources.yaml has it: a /26 is 64 addresses per node, and a /16 pod CIDR then supports 1024 nodes"

  validation {
    condition     = var.calico_block_size >= 20 && var.calico_block_size <= 32
    error_message = "calico_block_size must be between 20 and 32."
  }
}

variable "traefik_release_name" {
  type        = string
  default     = "traefik"
  description = "Helm release name of the ingress controller. Also the name of the IngressClass the chart creates, which is what the whoami Ingress asks for - so changing this changes what that Ingress has to name (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.traefik_release_name))
    error_message = "traefik_release_name must be a valid lowercase RFC 1123 label."
  }
}

variable "traefik_chart_repository" {
  type        = string
  default     = "https://traefik.github.io/charts"
  description = "Helm repository the Traefik chart comes from"

  validation {
    condition     = can(regex("^https://", var.traefik_chart_repository))
    error_message = "traefik_chart_repository must be an https URL."
  }
}

variable "ingress_paths" {
  type        = list(string)
  default     = ["/", "/api"]
  description = "Path prefixes the Ingress routes to the demo Service, as the _monolithic template had them. Two rules onto one backend, which is visible because whoami echoes the request line - so the response says which path matched"

  validation {
    condition     = length(var.ingress_paths) > 0
    error_message = "ingress_paths must contain at least one path; an Ingress rule with no paths routes nothing."
  }

  validation {
    condition     = alltrue([for path in var.ingress_paths : startswith(path, "/")])
    error_message = "ingress_paths entries must start with '/'."
  }
}
