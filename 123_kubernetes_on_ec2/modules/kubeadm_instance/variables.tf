variable "name" {
  type        = string
  description = "Name tag of the instance, and the prefix of its IAM role and instance profile names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.name))
    error_message = "name must start with a letter or digit and contain only letters, digits and hyphens."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name for SSH access"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "Security groups on the instance. The shared cluster group has to be among them, or the machine cannot reach the API server and the API server cannot reach its kubelet (rules.md B-6)"

  validation {
    condition     = length(var.vpc_security_group_ids) > 0 && alltrue([for id in var.vpc_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "vpc_security_group_ids must contain at least one valid security group ID (e.g. sg-0123456789abcdef0)."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type. t3.medium is the smallest type kubeadm's own preflight check accepts - it wants two CPUs - and the _monolithic template used it for all three machines"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter naming the AMI. A parameter rather than an AMI ID, so the machine always boots the current Amazon Linux 2023 image"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an SSM parameter path starting with '/'."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. Larger than the AMI default because container images accumulate on the node, and a full disk shows up as the kubelet evicting pods rather than as a disk error"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB; containerd plus the control plane images do not fit comfortably below that."
  }
}

variable "associate_public_ip_address" {
  type        = bool
  default     = false
  description = "Whether the instance gets a public address. False by default, and deliberately: the _monolithic template set it true on the control plane while placing that instance in a private subnet, where a public address has no route to the internet gateway and so does nothing at all"
}

variable "kubernetes_minor_version" {
  type        = string
  default     = "v1.34"
  description = "Kubernetes minor version, as the pkgs.k8s.io repository spells it (vMAJOR.MINOR). Pinned rather than read from dl.k8s.io/release/stable.txt at boot, so two machines booting either side of a release cannot end up on different minors - which kubeadm rejects"

  validation {
    condition     = can(regex("^v1\\.[0-9]+$", var.kubernetes_minor_version))
    error_message = "kubernetes_minor_version must look like v1.34 - a minor version, not a patch release, because that is what the package repository path takes."
  }
}

variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "Managed policies attached to the instance role. SSM Managed Instance Core is what makes the machine reachable by Session Manager and by an SSM Association. The _monolithic template also attached AmazonS3FullAccess here - account-wide read and write on every bucket, to exchange two files - which is replaced by the scoped policy the caller passes through additional_iam_policies"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "additional_iam_policies" {
  type        = map(string)
  default     = {}
  description = "Extra policies attached to the instance role, keyed by a caller-chosen label. A map rather than a list because these ARNs are usually another module's output, unknown until apply, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = alltrue([for label in keys(var.additional_iam_policies) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "additional_iam_policies keys become part of a resource address, so each must be letters, digits, dots, underscores or hyphens."
  }
}

variable "instance_metadata_http_put_response_hop_limit" {
  type        = number
  default     = 2
  description = "IMDS hop limit. Two rather than one, so a process inside a container can still reach the instance metadata service - the default of one stops at the host network namespace"

  validation {
    condition     = var.instance_metadata_http_put_response_hop_limit >= 1 && var.instance_metadata_http_put_response_hop_limit <= 64
    error_message = "instance_metadata_http_put_response_hop_limit must be between 1 and 64."
  }
}

variable "additional_user_data" {
  type        = string
  default     = ""
  description = "The role-specific half of the bootstrap, appended after the common kubeadm preparation. kubeadm init and the CNI handoff on a control plane, kubeadm join on a worker"
}

variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory where the instance touches <path>/userdata once the whole script has run. Null creates no marker. Something waiting on this machine - another instance's bootstrap, or an SSM Association - waits on that file rather than on depends_on (rules.md B-4/D-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
