variable "aws_region" {
  type        = string
  default     = null
  description = "Region this account's cluster and bucket are created in. When null, falls back to the provider default chain. This should differ from the region secondary_account uses - that difference is the cross-region part of the project, and nothing here enforces it because neither root can see the other's configuration (rules.md I-1)"
}
variable "primary_account_id" {
  type        = string
  description = "Account ID this root is meant to be applied into. Compared against the credentials actually in use by a precondition in main.tf, because applying this root into the other account creates the source bucket and the replication role in the wrong place - and the only symptom is replication that never happens (rules.md I-2)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.primary_account_id))
    error_message = "primary_account_id must be a 12-digit AWS account ID."
  }
}
variable "secondary_account_id" {
  type        = string
  description = "Account ID the backups are replicated into. S3 refuses a cross-account replication configuration that does not name the destination account explicitly"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.secondary_account_id))
    error_message = "secondary_account_id must be a 12-digit AWS account ID."
  }
  validation {
    # A constraint about the pair, so a cross-variable condition (rules.md B-1). Equal IDs mean the two
    # roots were applied with the same credentials, which makes the replication a same-account copy and
    # the whole demo vacuous.
    condition     = var.secondary_account_id != var.primary_account_id
    error_message = "secondary_account_id must differ from primary_account_id. To rehearse in a single account use the cluster variant, which builds both clusters in one account by design (rules.md I-1)."
  }
}
variable "primary_bucket_name" {
  type        = string
  description = "Name of this account's backup bucket. Required rather than generated, unlike the cluster variant's: a bucket name is global, and nothing outside this root has to name this one - but keeping both bucket names explicit makes the pair readable, and it is the name that appears in the other account's replication reporting"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.primary_bucket_name))
    error_message = "primary_bucket_name must be 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending alphanumerically."
  }
}
variable "secondary_bucket_name" {
  type        = string
  description = "Name of the bucket in the other account, which the replication rule writes into. One of the two names the two accounts have to agree on: a literal string here, because that bucket is in a different state file and there is nothing to reference (rules.md I-2). A value that does not match what that account created is accepted by plan and fails at apply with AccessDenied, which reads as a permissions problem rather than a typo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.secondary_bucket_name))
    error_message = "secondary_bucket_name must be a valid S3 bucket name."
  }
  validation {
    condition     = var.secondary_bucket_name != var.primary_bucket_name
    error_message = "secondary_bucket_name must differ from primary_bucket_name; S3 bucket names are globally unique, so these being equal means one of the two roots was given the wrong value."
  }
}
variable "replication_role_name" {
  type        = string
  default     = "VeleroDrS3ReplicationRole"
  description = "Name of the replication role this root creates. The other name the two accounts agree on: secondary_account assembles this role's ARN for its aws:PrincipalArn condition, so its replication_source_role_name variable must carry the same string (rules.md I-2/I-4). The bucket policy Principal is the source account root rather than this not-yet-created role, which lets secondary_account apply first. The fixed name is why this project cannot be deployed twice into one account - the second apply fails with EntityAlreadyExists"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.replication_role_name))
    error_message = "replication_role_name must be 1-64 characters of the set IAM accepts for a role name."
  }
}
variable "replication_time_minutes" {
  type        = number
  default     = 15
  description = "Replication Time Control window, fifteen minutes as the _monolithic template had it. S3 commits to replicating 99.99% of objects within it and publishes metrics when it does not - and charges extra per gigabyte replicated, which the original turned on without mentioning. Null turns it off and replicates on a best-effort basis"

  validation {
    condition     = var.replication_time_minutes == null || var.replication_time_minutes == 15
    error_message = "replication_time_minutes must be 15, the only value S3 accepts for Replication Time Control, or null to turn it off."
  }
}
variable "prefix" {
  type        = string
  default     = "velero-primary"
  description = "Prefix for the network resources' Name tags and for generated role names"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for this account's VPC. The two accounts' VPCs never talk to each other - the backups travel through S3, not through the network - so the two roots may use the same block without conflict"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "cluster_name" {
  type        = string
  default     = "velero-dr-primary"
  description = "Name of this account's EKS cluster, the one the backup is taken from"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS Kubernetes version. Keep it equal to the version secondary_account runs: Velero restores Kubernetes objects, and an API version removed between the two would fail the restore rather than the backup. Nothing here can check that, because the other root is a separate state file (rules.md I-1)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the cluster's API server endpoint is reachable from the public internet. Required here, because the helm and kubectl providers that install Velero, the controller, the storage classes and the workload run from the machine executing terraform apply rather than from inside the VPC (rules.md E-1/E-2). Narrow public_access_cidrs rather than turning this off"

  validation {
    # Constant condition, because the constraint really is "only this value in this variant"
    # (rules.md B-1). Turning it off passes plan and fails partway through apply with a connection
    # timeout that reads like a dependency ordering problem (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because its Kubernetes objects are applied by the helm and kubectl providers from the machine running terraform. To run with a private endpoint, apply them from the bastion through SSM Associations instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the cluster's public endpoint. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "velero-primary-key"
  description = "Name of the EC2 key pair created for the workbench instance and the node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "core-nodegroup"
  description = "Name of the managed node group, as the _monolithic template named it"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it. Two matters for the volumes: with WaitForFirstConsumer binding each pod's volume is created in its own node's zone, so two nodes across two zones means the StatefulSet's volumes are not both in one availability zone"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count for the managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count for the managed node group"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "aws_load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller chart, pinned where the _monolithic template's helm install pinned nothing. Chart 1.14.1 carries controller v2.14.1 - the chart's version is not the controller's"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_chart_version))
    error_message = "aws_load_balancer_controller_chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the load balancer controller installs its mservice.elbv2.k8s.aws mutating webhook. Off: the demo Service names the controller explicitly with the aws-load-balancer-type annotation, so the webhook has nothing to mutate - and its failurePolicy: Fail with no namespaceSelector would gate every Service creation in the cluster behind a controller pod being Ready (rules.md G-4)"
}
variable "velero_chart_version" {
  type        = string
  default     = "12.2.0"
  description = "Version of the Velero chart. Chart 12.2.0 carries Velero 1.18.2, where the _monolithic template installed the CLI at v1.17.0 and let it apply the CRDs. Keep it equal to what secondary_account runs: a restore is performed by that side's Velero reading this side's backup, and a server two minor versions apart may not understand the backup format"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.velero_chart_version))
    error_message = "velero_chart_version must be a semantic version (e.g. 12.2.0)."
  }
}
variable "velero_plugin_image_tag" {
  type        = string
  default     = "v1.14.3"
  description = "Version of velero-plugin-for-aws, which has to match the Velero version the chart carries: the plugin's compatibility table pairs v1.14.x with Velero v1.18.x"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.velero_plugin_image_tag))
    error_message = "velero_plugin_image_tag must be a v-prefixed semantic version (e.g. v1.14.3)."
  }
}
variable "backup_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the backups along with the bucket. True for a demo, and stated here rather than left to the module's default because of what it means: with it false a destroy fails with BucketNotEmpty once any backup exists, and with it true every backup and every version of every backup is deleted irrecoverably. Destroying this root first is also the required order - the replication configuration has to go before the destination bucket (rules.md I-4)"
}
variable "workload_name" {
  type        = string
  default     = "web"
  description = "Name of the demo StatefulSet, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo workload runs in, and the namespace the backup includes"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 2
  description = "Pods in the demo StatefulSet, two as the _monolithic template had it - and therefore two volumes to snapshot"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.29.5-alpine"
  description = "Container image for the demo StatefulSet. The _monolithic template used registry.k8s.io/nginx-slim:0.8 from the upstream StatefulSet tutorial - a 2016 build, amd64-only, with no security updates since"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$", var.workload_image))
    error_message = "workload_image must carry an explicit tag."
  }
}
variable "workload_volume_size" {
  type        = string
  default     = "1Gi"
  description = "Size of each pod's volume, as the _monolithic template had it. Small on purpose: the backup moves this data through the node agent into S3 and then S3 replicates it across a region boundary, and a large volume makes the demo slow without making it clearer"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.workload_volume_size))
    error_message = "workload_volume_size must be a binary quantity such as 1Gi."
  }
}
variable "public_subnet_tags" {
  type        = map(string)
  default     = { "kubernetes.io/role/elb" = "1" }
  description = "Tags on the public subnets. kubernetes.io/role/elb is how the load balancer controller finds where to put an internet-facing load balancer; without it the demo Service fails with \"couldn't auto-discover subnets\" (rules.md G-1). The _monolithic template tagged no subnets at all"

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0])
    error_message = "public_subnet_tags must not contain empty tag keys."
  }
}
variable "private_subnet_tags" {
  type        = map(string)
  default     = { "kubernetes.io/role/internal-elb" = "1" }
  description = "Tags on the private subnets, for an internal-scheme load balancer"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0])
    error_message = "private_subnet_tags must not contain empty tag keys."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) from 0.0.0.0/0, as the _monolithic template's InboundFromAnywhere parameter did. Set false and reach it through SSM Session Manager port forwarding instead"
}
variable "velero_cli_version" {
  type        = string
  default     = "v1.18.2"
  description = "Version of the velero CLI installed on the workbench. Velero is installed by a Helm release now, so the CLI is only used to take backups by hand - but it should match the server version the chart carries"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.velero_cli_version))
    error_message = "velero_cli_version must be a v-prefixed semantic version (e.g. v1.18.2)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>). Keep within one minor version of kubernetes_version"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
