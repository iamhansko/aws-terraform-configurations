variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.). Everything is built here, cluster and MWAA included - the blueprint's own region variable defaulted to us-west-2 regardless of where the workbench ran, which this configuration no longer has"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region (e.g. ap-northeast-2), or null to use the provider chain."
  }
}
variable "name" {
  type        = string
  default     = "managed-airflow-mwaa"
  description = "The blueprint's name variable: the VPC, the EKS cluster and the MWAA environment are all called this, and the names of the EMR virtual cluster, the IAM roles and the security groups are built from it"

  validation {
    # The narrowest of what it is used for: MWAA environment names start with a letter, and 40
    # characters leaves room for the suffixes appended to it (the EMR virtual cluster name is
    # <name>-emr-mwaa-team, 64 characters at most).
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,39}$", var.name))
    error_message = "name must be 1-40 characters of letters, digits and hyphens, starting with a letter."
  }
}

# --- Network -------------------------------------------------------------------------------------

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC, the blueprint's vpc_cidr. Private subnets are /20s from its start and public subnets /24s from index 48, so a /16 gives 10.0.0.0/20-10.0.32.0/20 and 10.0.48.0/24-10.0.50.0/24"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # try() because every validation block is evaluated, and a value with no "/" would fail here with
    # an index error rather than the message above.
    condition     = try(tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 20, true)
    error_message = "vpc_cidr_block must be between /16 and /20: AWS rejects a VPC larger than /16, and a smaller VPC than /20 leaves the public subnets carved from it too small to use."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = "Tags merged into every public subnet, as the blueprint tagged them. kubernetes.io/role/elb is how a load balancer controller finds subnets for an internet-facing load balancer; nothing in this project creates one, so it is kept for whatever is added later. The kubernetes.io/cluster/<name> tag is added on top in main.tf, because its key carries the cluster name"

  validation {
    condition = alltrue([
      for key, value in var.public_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "public_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
  }
}
variable "private_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  description = "Tags merged into every private subnet, as the blueprint tagged them - the internal load balancer counterpart of public_subnet_tags"

  validation {
    condition = alltrue([
      for key, value in var.private_subnet_tags :
      length(key) > 0 && length(key) <= 128 && length(value) <= 256 && !startswith(lower(key), "aws:")
    ])
    error_message = "private_subnet_tags keys must be 1-128 characters and must not use the reserved \"aws:\" prefix, and values must be 256 characters or fewer."
  }
}
variable "vpc_endpoint_services" {
  type = set(string)
  default = [
    "autoscaling",
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "ec2messages",
    "elasticloadbalancing",
    "kms",
    "logs",
    "ssm",
    "ssmmessages",
    "sts",
  ]
  description = "Interface endpoints created in the private subnets, the blueprint's vpc_endpoints list. Each costs an hourly charge per zone - eleven services in three zones is 33 endpoint ENIs - and none is needed for the network to work, because the private subnets route through the NAT gateway. Set [] to keep only the free S3 gateway endpoint"

  validation {
    condition     = alltrue([for s in var.vpc_endpoint_services : can(regex("^[a-z0-9.-]+$", s))])
    error_message = "vpc_endpoint_services entries are short service names such as ecr.api or sts, not full com.amazonaws.<region>.<name> strings."
  }
}

# --- EKS -----------------------------------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version of the EKS cluster. Not the blueprint's 1.26, which is past the end of EKS extended support and can no longer be created. Raise kubectl_download_version and cluster_autoscaler_chart_version with it"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.34."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet, as the blueprint set it. The Kubernetes objects and the cluster autoscaler's Helm release are applied by the kubectl and helm providers from the machine running terraform, so they need it. Narrow public_access_cidrs rather than turning it off"

  validation {
    # Pinned in the direction this configuration depends on, with the alternative named
    # (rules.md B-1/E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true here, because the Kubernetes objects and the Helm release are applied by the kubectl and helm providers from the machine running terraform. To run with a private endpoint, apply them from the workbench through an SSM Association instead, as 041_eks_private_cluster does (rules.md E-9)."
  }
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form - the machine running terraform has to stay inside it. The workbench and MWAA reach the API server through its private endpoint, so they need no entry here"

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain at least one valid IPv4 CIDR block."
  }
}
variable "cluster_log_types" {
  type        = list(string)
  default     = ["audit", "api", "authenticator"]
  description = "EKS control plane log types sent to CloudWatch Logs - the three the blueprint's EKS module enabled by default. [] turns control plane logging off"

  validation {
    condition = alltrue([for t in var.cluster_log_types : contains([
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ], t)])
    error_message = "cluster_log_types must be a subset of: api, audit, authenticator, controllerManager, scheduler."
  }
}
variable "cluster_log_retention_days" {
  type        = number
  default     = 90
  description = "Retention on the control plane log group, 90 days as the blueprint's EKS module set it. The group is a Terraform resource, so destroy removes it; left to EKS it would never expire and outlive the cluster"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cluster_log_retention_days)
    error_message = "cluster_log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the workbench, from the amazon-eks S3 bucket layout (<version>/<date>). Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["m5.xlarge"]
  description = "Instance types of the core node group, m5.xlarge as the blueprint had it"

  validation {
    condition     = length(var.node_group_instance_types) > 0 && alltrue([for t in var.node_group_instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", t))])
    error_message = "node_group_instance_types must be a non-empty list of valid EC2 instance types (e.g. m5.xlarge)."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 3
  description = "Nodes the core node group starts with, as the blueprint had it. Only the starting size: after creation the cluster autoscaler owns the group's size, and the node group ignores later changes to this value so an apply does not scale the cluster back under the autoscaler"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 3
  description = "Floor the cluster autoscaler will not scale the core node group below, as the blueprint had it"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 9
  description = "Ceiling the cluster autoscaler scales the core node group up to, as the blueprint had it"

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "node_group_max_size must be at least 1."
  }
  validation {
    # The three sizes are one constraint, so the check reads all three (rules.md B-1). EKS rejects the
    # combination at CreateNodegroup otherwise, after the cluster has already taken ten minutes.
    condition     = var.node_group_min_size <= var.node_group_desired_size && var.node_group_desired_size <= var.node_group_max_size
    error_message = "node_group sizes must satisfy min_size <= desired_size <= max_size."
  }
}
variable "node_group_root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB of each core node, gp3, as the blueprint had it. EMR's Spark images run to several gigabytes each, and the EKS AMI's own 20 GiB root fills up after a few of them"

  validation {
    condition     = var.node_group_root_volume_size >= 20 && var.node_group_root_volume_size <= 16384
    error_message = "node_group_root_volume_size must be between 20 and 16384 GiB."
  }
}
variable "node_group_labels" {
  type = map(string)
  default = {
    WorkerType    = "ON_DEMAND"
    NodeGroupType = "core"
    Environment   = "preprod"
    Zone          = "test"
  }
  description = "Kubernetes labels on the core nodes, as the blueprint set them. Nothing in this project selects on them; they are there for a workload pinned to the core group"

  validation {
    condition     = alltrue([for key in keys(var.node_group_labels) : length(key) > 0])
    error_message = "node_group_labels must not contain empty label keys."
  }
}
variable "cluster_autoscaler_chart_version" {
  type        = string
  default     = "9.53.0"
  description = "Pinned cluster-autoscaler chart version. 9.53.0 ships autoscaler 1.34.2, the same minor as kubernetes_version - eks-blueprints-addons got that match by overriding image.tag from the cluster version, and pinning a chart that already matches does the same without the override"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cluster_autoscaler_chart_version))
    error_message = "cluster_autoscaler_chart_version must be a semantic version."
  }
}

# --- MWAA ----------------------------------------------------------------------------------------

variable "airflow_version" {
  type        = string
  default     = "2.11.2"
  description = "Apache Airflow version of the MWAA environment. Not the blueprint's 2.5.1: MWAA ended support for it on December 30, 2025 and no longer creates environments on it. 2.11.2 is the newest 2.x MWAA offers, and the DAGs are Airflow 2 code"

  validation {
    condition     = can(regex("^2\\.[0-9]+\\.[0-9]+$", var.airflow_version))
    error_message = "airflow_version must be a 2.x version such as 2.11.2. The DAGs in dags/ are written for Airflow 2 - Airflow 3 changes the DAG and operator imports and how top-level code may reach connections - so moving to 3.x means rewriting them first. MWAA still creates 2.7.2 through 2.11.2."
  }
}
variable "mwaa_environment_class" {
  type        = string
  default     = "mw1.medium"
  description = "MWAA environment class, mw1.medium as the blueprint had it. It sizes the scheduler, the web server and every worker, and it is the largest line on the bill: the environment is charged by the hour whether or not a DAG runs"

  validation {
    condition     = contains(["mw1.micro", "mw1.small", "mw1.medium", "mw1.large", "mw1.xlarge", "mw1.2xlarge"], var.mwaa_environment_class)
    error_message = "mwaa_environment_class must be one of mw1.micro, mw1.small, mw1.medium, mw1.large, mw1.xlarge or mw1.2xlarge."
  }
}
variable "mwaa_min_workers" {
  type        = number
  default     = 1
  description = "Workers MWAA keeps running when nothing is queued, as the blueprint had it"

  validation {
    # No fixed upper bound: it can be no higher than mwaa_max_workers, and that is bounded by the
    # account's quota.
    condition     = var.mwaa_min_workers >= 1
    error_message = "mwaa_min_workers must be at least 1."
  }
}
variable "mwaa_max_workers" {
  type        = number
  default     = 10
  description = "Upper bound MWAA scales workers to. 10 rather than the blueprint's 25, because the ceiling is the account's Workers per environment quota (L-78AC1883): 25 by AWS's default, but an account can be given less, and CreateEnvironment rejects a higher value only at apply - \"MaxWorkers has a limit of 10\" in the account this first failed in, after the rest of the stack was built. 10 fits under both, and the two DAGs here run one task each. modules/mwaa_environment checks this against the quota read at plan, so a value above this account's quota fails there and needs a quota increase first"

  validation {
    condition     = var.mwaa_max_workers >= var.mwaa_min_workers
    error_message = "mwaa_max_workers must be greater than or equal to mwaa_min_workers."
  }
}
variable "mwaa_webserver_access_mode" {
  type        = string
  default     = "PUBLIC_ONLY"
  description = "Whether the Airflow web server has a public endpoint, PUBLIC_ONLY as the blueprint set it. Signing in still goes through IAM either way; PRIVATE_ONLY would leave the UI reachable only from inside the VPC, such as from the workbench"

  validation {
    condition     = contains(["PUBLIC_ONLY", "PRIVATE_ONLY"], var.mwaa_webserver_access_mode)
    error_message = "mwaa_webserver_access_mode must be PUBLIC_ONLY or PRIVATE_ONLY."
  }
}
variable "airflow_configuration_options" {
  type = map(string)
  default = {
    "core.load_default_connections" = "false"
    "core.load_examples"            = "false"
    # The blueprint set "tree", the view Airflow 2.3 renamed to grid.
    "webserver.dag_default_view" = "grid"
    "webserver.dag_orientation"  = "TB"
    "logging.logging_level"      = "INFO"
  }
  description = "Airflow configuration overrides, as the blueprint set them - except dag_default_view, whose old value \"tree\" names a view Airflow 2.3 replaced with grid. secrets.backend and secrets.backend_kwargs are not accepted here: modules/mwaa_environment sets them, scoped to the prefix its execution role may read"

  validation {
    condition     = alltrue([for key in keys(var.airflow_configuration_options) : can(regex("^[a-z_]+\\.[a-z0-9_]+$", key))])
    error_message = "airflow_configuration_options keys must be section.key in lowercase, e.g. core.load_examples."
  }
}
variable "mwaa_namespace" {
  type        = string
  default     = "mwaa"
  description = "Namespace the KubernetesPodOperator DAG runs its pod in, as the blueprint named it. Rendered into the DAG from here, so the DAG and the Role granting it access cannot name different namespaces (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.mwaa_namespace)) && length(var.mwaa_namespace) <= 63
    error_message = "mwaa_namespace must be a valid lowercase RFC 1123 label of 63 characters or fewer."
  }
}

# --- EMR on EKS ----------------------------------------------------------------------------------

variable "emr_namespace" {
  type        = string
  default     = "emr-mwaa"
  description = "Namespace the EMR on EKS virtual cluster is bound to and its Spark pods run in, as the blueprint named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.emr_namespace)) && length(var.emr_namespace) <= 63
    error_message = "emr_namespace must be a valid lowercase RFC 1123 label of 63 characters or fewer."
  }
}
variable "emr_release_label" {
  type        = string
  default     = "emr-7.5.0-latest"
  description = "EMR release the example DAG's Spark job runs on, rendered into the DAG. Not the blueprint's emr-6.3.0-latest, whose Java 8 predates cgroup v2 support on the AL2023 nodes; 7.5 is Spark 3.5 on Java 17, and the release 030_emr_on_eks uses"

  validation {
    condition     = can(regex("^emr-[0-9]+\\.[0-9]+\\.[0-9]+(-latest|-[0-9]{8})?$", var.emr_release_label))
    error_message = "emr_release_label must look like emr-7.5.0-latest."
  }
}
variable "emr_job_role_additional_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  description = "Managed policies attached to the EMR job execution role on top of its CloudWatch Logs policy. AmazonS3FullAccess is what the blueprint attached, so a DAG can read and write any bucket in the account. The example job reads nothing from S3 - pi.py ships inside the EMR image - so [] works for it, and is the better default for anything kept running"

  validation {
    condition     = alltrue([for arn in var.emr_job_role_additional_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "emr_job_role_additional_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "emr_connection_id" {
  type        = string
  default     = "emr_eks"
  description = "Connection ID the example EMR DAG reads its virtual cluster ID and job role ARN from. Rendered into the DAG and used as the name of the Secrets Manager secret that holds the connection, so the two cannot disagree. The blueprint left creating this connection as a step in the Airflow UI; here it is a secret under the environment's prefix, which its secrets backend reads"

  validation {
    # Rendered into a Jinja attribute access ({{ conn.<id>.extra_dejson }}) in the DAG, which only
    # parses for a Python identifier - a hyphen would make it subtraction.
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]*$", var.emr_connection_id))
    error_message = "emr_connection_id must be a Python identifier (letters, digits and underscores, not starting with a digit), because the DAG reads it as conn.<id> in a Jinja template."
  }
}

# --- Workbench -----------------------------------------------------------------------------------

variable "instance_name" {
  type        = string
  default     = "airflow-on-eks-vscode"
  description = "Name tag for the workbench instance"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "key_name" {
  type        = string
  default     = "airflow-on-eks-key"
  description = "Name of the EC2 key pair created for the workbench instance"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "security_group_name" {
  type        = string
  default     = "airflow-on-eks-vscode-sg"
  description = "Name of the workbench instance's security group. Named per project rather than the _monolithic template's plain \"vscode-sg\" so it can be told apart in a console listing every project's groups"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, t3.medium as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size of the workbench in GiB. Back to the usual workbench size: the 50 GiB this used to be was for the nested Terraform run's provider binaries, and that run is gone"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.104.1"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.104.1)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module and the SSM association that polls for them (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1200
  description = "How long the README association waits. Its first act is to poll for the user data marker, and user data installs code-server, docker, kubectl, eksctl and helm before writing it"

  validation {
    condition     = var.readme_timeout_seconds >= 600
    error_message = "readme_timeout_seconds must be at least 600; the bootstrap downloads several tools before the marker appears."
  }
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
