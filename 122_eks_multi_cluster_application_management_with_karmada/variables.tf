variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). All three clusters, the load balancer and the workbench land in it - this project has no second region"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name_prefix" {
  type        = string
  default     = "karmada"
  description = "Prefix for the three cluster names, as the _monolithic template had it: <prefix>-parent carries the Karmada control plane and <prefix>-member-1 and <prefix>-member-2 are registered with it. Also names the VPC and the key pair, so everything this project creates is recognisable as one set"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.cluster_name_prefix))
    error_message = "cluster_name_prefix must be 2-21 characters of lowercase letters, digits and hyphens. Shorter than an EKS cluster name allows, because \"-member-1\" is appended to it and the result also becomes a Kubernetes object name on the Karmada API server."
  }
}
variable "member_cluster_count" {
  type        = number
  default     = 2
  description = <<-DESC
    Member clusters created and registered with Karmada. Two, as the _monolithic template had it, and two is
    the only value this configuration accepts.

    The original template declared this as a string and validated it with contains(["0","1","2","3","4"],
    ...) - which allowed values its own description said would not work, because the guidance script only
    deployed the demo workload when at least two members existed.

    Why it is pinned rather than variable now: each member cluster needs its own helm provider, because each
    has its own API server endpoint and credentials, and provider aliases cannot be generated - there is no
    for_each for a provider block. So the member clusters are declared one by one in main.tf, and adding a
    third means adding a provider alias, a cluster module, its addons, its node group and its agent by hand.
    The variable is kept rather than deleted because it is the parameter the original exposed, and a
    validation is a better place to say "two" than a comment nobody reads (rules.md B-1).
  DESC

  validation {
    condition     = var.member_cluster_count == 2
    error_message = "member_cluster_count must be 2. Each member cluster needs its own helm provider alias and provider aliases cannot be generated with for_each, so the members are declared individually in main.tf - a third one means adding a provider block, a cluster module, its addons, its node group and its agent module. The demo workload also needs at least two clusters to have anything to divide its replicas between."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = <<-DESC
    Kubernetes version for all three clusters. The _monolithic template defaulted to "latest", which the
    guidance script resolved at run time by asking the EKS API which versions its addons supported - so two
    applies months apart built different clusters with no change here.

    1.34 pins it to the newest version in standard support, matching the rest of this repository. "latest" is
    still accepted because the original accepted it, but it no longer resolves to the newest version: it
    maps to leaving the version field unset, which gets EKS's own default, and that trails the newest
    supported release (see modules/eks_cluster).
  DESC

  validation {
    condition     = contains(["latest", "1.32", "1.33", "1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of the versions the guidance script accepted: latest, 1.32, 1.33, 1.34, 1.35 or 1.36."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the three EKS API servers are reachable from outside the VPC. True, and it has to stay true for
    this configuration as written.

    Every Kubernetes object here is created by a provider - the StorageClass by kubectl, the Karmada control
    plane and the agents by helm - and those providers run on the machine executing terraform, not inside
    the VPC. With private-only endpoints they cannot connect, and the failure arrives mid-apply as a
    connection timeout that looks exactly like the destroy-ordering problem rules.md D-4 describes.

    rules.md E-9 is the other shape: private endpoints, with every Kubernetes object applied from an
    instance in the VPC through SSM Associations. That is what 041_eks_private_cluster does, and it gives up
    having any of those objects in Terraform state - which is the thing this project was changed to gain.
  DESC

  validation {
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant. The StorageClass, the Karmada control plane, the member agents and the demo workload are all applied by Terraform providers running outside the VPC, so a private-only endpoint makes them unreachable. To run with a private endpoint, apply them from the workbench through SSM Associations instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API servers' public endpoints. Open by default because the machine running terraform has to reach them and its address is not known here - narrow it to that address where possible"

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must be a non-empty list of valid IPv4 CIDR blocks."
  }
}
# ---------------------------------------------------------------------------------------------------------
# Node groups
# ---------------------------------------------------------------------------------------------------------
variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for every node group. t3.medium is 2 vCPU and 4 GiB, which is what the guidance script asked eksctl for through --instance-selector-vcpus 2 --instance-selector-memory 4 - it let eksctl choose the type from that, where this names it"

  validation {
    condition     = length(var.node_instance_types) > 0 && alltrue([for type in var.node_instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))])
    error_message = "node_instance_types must be a non-empty list of valid EC2 instance types."
  }
}
variable "parent_node_count" {
  type        = number
  default     = 3
  description = <<-DESC
    Nodes on the parent cluster. Three, which is what the guidance script required: its -n flag refused
    anything below three with the message that Karmada is deployed in high availability mode.

    Three is a real constraint rather than a habit, and the reason is pod anti-affinity. The chart puts a
    requiredDuringSchedulingIgnoredDuringExecution anti-affinity on karmada-apiserver, so three apiserver
    replicas need three nodes - on two, the third pod stays Pending and the Helm release waits out its
    timeout without saying why. Lower this only together with karmada_apiserver_replicas.
  DESC

  validation {
    condition     = var.parent_node_count >= 1
    error_message = "parent_node_count must be at least one."
  }
}
variable "member_node_count" {
  type        = number
  default     = 2
  description = "Nodes on each member cluster. Two rather than the parent's three: a member runs the agent, CoreDNS and its share of the demo workload, none of which has an anti-affinity constraint. The guidance script gave every cluster three because its -n flag was a single value for all of them"

  validation {
    condition     = var.member_node_count >= 1
    error_message = "member_node_count must be at least one."
  }
}
variable "node_max_count" {
  type        = number
  default     = 4
  description = "Upper bound on each node group's size. Nothing scales these - there is no autoscaler in this project - so this is only headroom for a manual change"

  validation {
    condition     = var.node_max_count >= 1
    error_message = "node_max_count must be at least one."
  }
}
# ---------------------------------------------------------------------------------------------------------
# Karmada
# ---------------------------------------------------------------------------------------------------------
variable "karmada_namespace" {
  type        = string
  default     = "karmada-system"
  description = "Namespace the control plane runs in on the parent cluster, and the agents in their members. karmada-system, as karmada init used. Part of the certificates' in-cluster SANs, so it is passed to both the certificate module and the chart from here rather than defaulted twice"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.karmada_namespace))
    error_message = "karmada_namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "karmada_chart_version" {
  type        = string
  default     = "v1.19.0"
  description = "Karmada chart version, with the leading v its repository's index uses. The control plane and both agents get the same value, so an agent is never a different Karmada release from the control plane it registers with. Pinned where the _monolithic template pinned nothing - it cloned the guidance repository's default branch and installed whatever that branch's script asked for"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.karmada_chart_version))
    error_message = "karmada_chart_version must look like v1.19.0, including the leading v that the Karmada chart repository's index uses."
  }
}
variable "karmada_image_version" {
  type        = string
  default     = "v1.19.0"
  description = "Tag for the Karmada component images, normally the chart's appVersion. Set because the chart leaves every Karmada image on :latest through a YAML anchor that user values cannot override - see modules/karmada_control_plane/main.tf, where the mechanism and the reason it goes unnoticed are written out"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.karmada_image_version))
    error_message = "karmada_image_version must look like v1.19.0."
  }
}
variable "karmada_apiserver_replicas" {
  type        = number
  default     = 3
  description = "Replicas of karmada-apiserver, three as the guidance script asked for with --karmada-apiserver-replicas 3. Needs one node each because of the chart's required pod anti-affinity, so it cannot exceed parent_node_count"

  validation {
    condition     = var.karmada_apiserver_replicas >= 1
    error_message = "karmada_apiserver_replicas must be at least one."
  }
  validation {
    # The pair is the constraint. Exceeding the node count leaves pods Pending and the Helm release waiting
    # out its timeout with nothing in the Terraform output to explain it (rules.md B-1).
    condition     = var.karmada_apiserver_replicas <= var.parent_node_count
    error_message = "karmada_apiserver_replicas must not exceed parent_node_count. The chart puts a requiredDuringSchedulingIgnoredDuringExecution pod anti-affinity on karmada-apiserver, so each replica needs its own node - surplus replicas stay Pending and the Helm release waits out its whole timeout rather than reporting why."
  }
}
variable "etcd_replicas" {
  type        = number
  default     = 1
  description = <<-DESC
    Replicas of Karmada's etcd. One, which is the value this project's _monolithic template patched the
    guidance installer down to:

      sed -i 's/--etcd-replicas 3/--etcd-replicas 1/' include/deploy-karmada-functions.sh

    The patch is now a default rather than a sed, and the reason it existed still holds: etcd carries the
    same required pod anti-affinity as the apiserver and each replica claims its own volume, so three
    replicas need three nodes with volumes in three zones. One replica is not highly available - losing that
    node loses the control plane, including every member registration - which is fine for a demo and wrong
    for anything else.
  DESC

  validation {
    condition     = contains([1, 3, 5], var.etcd_replicas)
    error_message = "etcd_replicas must be 1, 3 or 5. etcd needs an odd number to establish a quorum, and the guidance installer offered no other values."
  }
  validation {
    condition     = var.etcd_replicas <= var.parent_node_count
    error_message = "etcd_replicas must not exceed parent_node_count. etcd carries the same required pod anti-affinity as the apiserver, so surplus replicas stay Pending - and because every other Karmada component waits on etcd in an init container, the whole control plane then appears not to start."
  }
}
variable "etcd_volume_size" {
  type        = string
  default     = "5Gi"
  description = "Size of Karmada's etcd volume, which karmada init also requested as 5Gi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.etcd_volume_size))
    error_message = "etcd_volume_size must be a Kubernetes quantity such as 5Gi."
  }
}
variable "etcd_storage_class_name" {
  type        = string
  default     = "ebs-sc"
  description = "Name of the StorageClass created on the parent cluster and named by etcd's volume claim, as the guidance installer's --storage-classes-name had it. One value for both so a claim cannot name a class that was never created (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.etcd_storage_class_name))
    error_message = "etcd_storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "karmada_api_port" {
  type        = number
  default     = 32443
  description = "Port the Karmada API server is published on - both the load balancer's listener and the Service's nodePort, kept equal so the port in the endpoint is the port on the nodes. 32443 is what the guidance installer's karmada-service-loadbalancer Service published"

  validation {
    condition     = var.karmada_api_port >= 30000 && var.karmada_api_port <= 32767
    error_message = "karmada_api_port must be between 30000 and 32767, because it is also used as the Karmada API server Service's nodePort."
  }
}
variable "karmada_control_plane_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long helm waits for the control plane release. Generous because it is not only Deployments: etcd has to get an EBS volume provisioned and bound, and the chart's static-resource Job has to pull an image and apply Karmada's CRDs into the new API server before the release is considered done"

  validation {
    condition     = var.karmada_control_plane_timeout_seconds > 0
    error_message = "karmada_control_plane_timeout_seconds must be positive."
  }
}
variable "karmada_agent_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long helm waits for each member's agent release. Shorter than the control plane's: it is one stateless Deployment. Note what it does not cover - the agent registers its cluster after it starts, so a finished release is not yet a registered cluster"

  validation {
    condition     = var.karmada_agent_timeout_seconds > 0
    error_message = "karmada_agent_timeout_seconds must be positive."
  }
}
variable "karmada_apply_retry_count" {
  type        = number
  default     = 3
  description = "Times the kubectl provider aimed at the Karmada API server retries an apply. Covers the gap between the load balancer's targets passing their health check and the demo workload being applied, which should already be closed by the time the control plane's Helm release finishes - see providers.tf"

  validation {
    condition     = var.karmada_apply_retry_count >= 0
    error_message = "karmada_apply_retry_count must be zero or greater."
  }
}
variable "member_registration_wait_seconds" {
  type        = number
  default     = 90
  description = <<-DESC
    How long to wait after the member agents are installed before creating the demo workload, so that
    Karmada's scheduler sees both clusters as Ready and divides the replicas between them.

    Ninety seconds against a gap measured at two. The agent reports cluster status every ten seconds, so the
    Ready condition normally lands within one cycle of its pod becoming Ready; the margin is wide because
    the cost of it being too short is not an error. The apply succeeds, every replica goes to whichever
    cluster registered first, and only the ResourceBinding shows it - see the timeline on
    time_sleep.karmada_member_registration in main.tf for the apply where that happened.

    This is a timer rather than a signal because there is no signal to read: the Ready condition sits on an
    object Terraform does not manage, and neither provider aimed at the Karmada API server can read an
    arbitrary object back.
  DESC

  validation {
    condition     = var.member_registration_wait_seconds >= 0
    error_message = "member_registration_wait_seconds must be zero or greater."
  }
}
variable "demo_replicas" {
  type        = number
  default     = 4
  description = "Replicas the demo Deployment asks for on the Karmada API server, four as the guidance installer's `kubectl create deployment --replicas=4` did. Divided between the member clusters rather than duplicated in each, so this is two pods per cluster with two members"

  validation {
    condition     = var.demo_replicas >= 1
    error_message = "demo_replicas must be at least one."
  }
}
variable "demo_image_tag" {
  type        = string
  default     = "1.29"
  description = "Tag for the demo workload's nginx image. Pinned, where the installer passed a bare `nginx` and therefore :latest"

  validation {
    condition     = length(var.demo_image_tag) > 0
    error_message = "demo_image_tag must not be empty."
  }
}
# ---------------------------------------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------------------------------------
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it. The subnets are derived from it rather than listed, so changing it moves them with it. Also the source range allowed to reach the Karmada API server's node port, since the load balancer's interfaces live in it"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c", "d"]
  description = "Zones the VPC spans, as the _monolithic template's AzMapping listed them. Three because the parent cluster's three nodes spread across them, which is what lets three karmada-apiserver replicas and their anti-affinity schedule (rules.md C-3: the zone count is decided by what the project puts in the network)"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones - an EKS cluster requires subnets in two, and so does a load balancer."
  }
}
variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the regional NAT gateway is given an address in, as the _monolithic template wired them. It also allocated a third address for the third zone and attached it to nothing, which this shape makes impossible (rules.md A-5)"

  validation {
    condition     = length(var.nat_availability_zone_suffixes) >= 1
    error_message = "nat_availability_zone_suffixes must name at least one zone."
  }
}
# ---------------------------------------------------------------------------------------------------------
# Workbench
# ---------------------------------------------------------------------------------------------------------
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair created for the workbench and attached to every node group. Null derives it from cluster_name_prefix. The _monolithic template built it from a uuid standing in for AWS::StackId, which made it unique but also unguessable when looking for the private key in SSM"

  validation {
    condition     = var.key_name == null || length(var.key_name) > 0
    error_message = "key_name must be a non-empty string, or null to derive it from cluster_name_prefix."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. It no longer builds anything - Terraform does - so it is now a place to run kubectl against four API servers rather than the machine doing the work, and could be smaller"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type, e.g. t3.large."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GB for the workbench, as the _monolithic template had it"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version path used to download kubectl onto the workbench, in <version>/<release-date> form. The _monolithic template hardcoded 1.33.3 while its cluster version defaulted to \"latest\", so the two could drift more than one minor apart and leave kubectl outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it - a bool here where that template used a string validated against [\"True\", \"False\"], so \"true\" would have been rejected. code-server has no authentication in front of it, so narrow this where possible"
}
variable "marker_file_path" {
  type        = string
  default     = "/var/lib/terraform"
  description = <<-DESC
    Directory on the workbench where the bootstrap drops its completion marker. The SSM Associations that
    follow wait for that marker rather than relying on depends_on (rules.md D-5).

    /var/lib/terraform rather than the /run/terraform the rest of this repository uses, and the difference
    is that /run is a tmpfs. A marker written there does not survive a stop and start, which is the one
    thing anyone does to a demo instance to stop paying for it overnight. The next apply whose association
    parameters have changed then re-runs the association, its wait loop looks for a marker that the running
    instance will never write again, and the apply fails with

      Error: waiting for SSM Association (...) create: timeout while waiting for state to become 'Success'
      (last state: 'Pending', timeout: 30m0s)

    thirty minutes later, naming nothing. /var/lib is on the root volume and survives a reboot, so the
    marker means what it says: this instance has finished its bootstrap, once, ever.

    This is a deliberate divergence from the other projects here rather than an oversight. They have the
    same hazard; it has simply not been hit in them yet.
  DESC

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
  validation {
    # /run and /tmp are both cleared between boots on Amazon Linux 2023, which turns the marker from a
    # record into a guess. The constraint is about where the path points, so it belongs here rather than in
    # a comment (rules.md B-1).
    condition     = var.marker_file_path == null || !can(regex("^/(run|tmp)(/|$)", var.marker_file_path))
    error_message = "marker_file_path must not be under /run or /tmp. Both are cleared when the instance restarts, so the bootstrap's completion marker disappears while the instance it describes is still running - and the SSM Association waiting for it then hangs until Terraform's own timeout and reports only \"last state: 'Pending'\". Use a path on the root volume such as /var/lib/terraform."
  }
}
variable "workbench_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long each SSM Association on the workbench may take. Both of them wait on the bootstrap's marker first, and that bootstrap installs kubectl, eksctl, helm and docker before it writes it"

  validation {
    condition     = var.workbench_timeout_seconds > 0
    error_message = "workbench_timeout_seconds must be positive."
  }
}
variable "marker_wait_timeout_seconds" {
  type        = number
  default     = 1200
  description = <<-DESC
    How long each association's wait loop looks for the marker it depends on before failing.

    It exists so that the failure has a message. Without a ceiling the loop runs until SSM or Terraform
    stops it, and what surfaces is "last state: 'Pending'" against an association UUID - true, and useless.
    With one, the step exits non-zero, SSM records Failed, and the reason is in the invocation's standard
    error where A-4's procedure can read it.
  DESC

  validation {
    condition     = var.marker_wait_timeout_seconds > 0
    error_message = "marker_wait_timeout_seconds must be positive."
  }
  validation {
    # The pair is the point: the script has to give up first, or its message never gets written. Same
    # constraint as the one rules.md E-9 states for a helm timeout inside an association (rules.md B-1).
    condition     = var.marker_wait_timeout_seconds < var.workbench_timeout_seconds
    error_message = "marker_wait_timeout_seconds must be less than workbench_timeout_seconds. The wait loop has to give up before SSM and Terraform do, or the loop is still running when they stop it and the only thing reported is \"unexpected state 'Failed'\" or \"last state: 'Pending'\" - which is the message this ceiling exists to replace."
  }
}
