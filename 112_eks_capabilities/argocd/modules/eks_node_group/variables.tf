variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this node group joins"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "node_group_name" {
  type        = string
  default     = "stem-app"
  description = "Name of the EKS managed node group. Also used to derive the launch template and instance Name tag"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "ami_type" {
  type        = string
  default     = "AL2023_x86_64_STANDARD"
  description = "AMI type for the node group. Ignored (forced to null) when custom_ami_id is set, because EKS rejects ami_type together with a launch template that specifies its own image_id"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64",
      "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64", "BOTTLEROCKET_ARM_64_NVIDIA", "BOTTLEROCKET_x86_64_NVIDIA",
      "WINDOWS_CORE_2019_x86_64", "WINDOWS_FULL_2019_x86_64", "WINDOWS_CORE_2022_x86_64", "WINDOWS_FULL_2022_x86_64",
      "CUSTOM"
    ], var.ami_type)
    error_message = "ami_type must be a valid EKS node group AMI type."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the node group"

  validation {
    condition     = alltrue([for t in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", t))])
    error_message = "instance_types must contain valid EC2 instance types (e.g. t3.medium)."
  }
  validation {
    # Exactly one of the two places may name a type. EKS rejects a node group that
    # sets instance_types while its launch template also sets instance_type, and a
    # node group that names one in neither place has no type at all (rules.md B-1).
    condition     = (length(var.instance_types) > 0) != (var.launch_template_instance_type != null)
    error_message = "set either instance_types or launch_template_instance_type, not both and not neither. EKS rejects a node group whose launch template also names an instance type, and a capacity reservation needs the type on the launch template so it matches the reservation."
  }
}
variable "capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity type for the node group"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be either ON_DEMAND or SPOT."
  }
}
variable "desired_size" {
  type        = number
  default     = 2
  description = "Desired number of worker nodes"

  validation {
    condition     = var.desired_size >= 0
    error_message = "desired_size must be zero or greater."
  }
}
variable "min_size" {
  type        = number
  default     = 2
  description = "Minimum number of worker nodes"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}
variable "max_size" {
  type        = number
  default     = 4
  description = "Maximum number of worker nodes"

  validation {
    condition     = var.max_size >= 0
    error_message = "max_size must be zero or greater."
  }
}
variable "labels" {
  type        = map(string)
  default     = {}
  description = "Kubernetes labels applied to nodes in this node group, used by pod nodeSelector/affinity to target it"

  validation {
    condition     = alltrue([for key in keys(var.labels) : length(key) > 0])
    error_message = "labels must not contain empty Kubernetes label keys."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where worker nodes are launched"

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must be a non-empty list of valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name attached to worker node instances through the launch template. When null, no key pair is attached and nodes are reachable only through SSM Session Manager"

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a string of printable ASCII characters (255 or fewer), or null."
  }
}
variable "vpc_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security group IDs attached to worker node instances through the launch template, on top of the cluster security group EKS attaches itself. When empty, only the cluster security group applies"

  validation {
    condition     = alltrue([for id in var.vpc_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "vpc_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "custom_ami_id" {
  type        = string
  default     = null
  description = "Optional AMI ID set as the launch template's image_id, replacing the EKS-optimized AMI that ami_type would select. When set, custom_user_data must carry the MIME multipart NodeConfig that bootstraps the node, because EKS no longer injects it (rules.md B-4)"

  validation {
    condition     = var.custom_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.custom_ami_id))
    error_message = "custom_ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0), or null."
  }
}
variable "custom_user_data" {
  type        = string
  default     = null
  description = "Optional launch template user data. EKS only accepts MIME multipart content here: a bare shell script or a bare NodeConfig document is silently ignored. When custom_ami_id is null, EKS merges its own NodeConfig boundary into this document; when custom_ami_id is set, this document must supply NodeConfig itself. When null, no user data is set on the launch template"

  validation {
    condition     = var.custom_user_data == null || can(regex("(?i)^\\s*MIME-Version:", var.custom_user_data))
    error_message = "custom_user_data must be a MIME multipart document starting with a MIME-Version header, or null. EKS silently ignores a bare shell script or a bare NodeConfig here."
  }
}
variable "instance_metadata_http_put_response_hop_limit" {
  type        = number
  default     = 2
  description = "IMDS hop limit for worker nodes. Must be at least 2 so pods using the instance role (rather than IRSA) can still reach IMDS through the container network namespace"

  validation {
    condition     = var.instance_metadata_http_put_response_hop_limit >= 1 && var.instance_metadata_http_put_response_hop_limit <= 64
    error_message = "instance_metadata_http_put_response_hop_limit must be between 1 and 64."
  }
}
variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the node group's IAM role"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "instance_tags" {
  type        = map(string)
  default     = {}
  description = "Extra AWS tags written onto the instances this node group launches, merged over the default Name tag. The Node Termination Handler's queue mode can be told to only act on instances carrying a particular tag, and the amazon-ec2-spot-interrupter CLI finds its targets by Name, so both are set through this rather than by editing the module"

  validation {
    condition     = alltrue([for key in keys(var.instance_tags) : length(key) > 0])
    error_message = "instance_tags must not contain empty AWS tag keys."
  }
}
variable "launch_template_instance_type" {
  type        = string
  default     = null
  description = "Instance type set on the launch template rather than on the node group. Null leaves it to the node group's instance_types, which is the ordinary case. It has to be set - and instance_types left empty - when a capacity reservation is targeted, because a reservation covers one exact type and EKS rejects both places naming one"

  validation {
    condition     = var.launch_template_instance_type == null || can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.launch_template_instance_type))
    error_message = "launch_template_instance_type must be a valid EC2 instance type, or null to let the node group choose."
  }
}
variable "capacity_reservation_id" {
  type        = string
  default     = null
  description = "On-Demand Capacity Reservation the nodes launch into. Null leaves the launch template with no capacity reservation specification at all, which is not the same as one set to \"none\" - see main.tf. Taken from the module that created the reservation, so the type and zone cannot drift from it (rules.md B-5)"

  validation {
    condition     = var.capacity_reservation_id == null || can(regex("^cr-[0-9a-f]+$", var.capacity_reservation_id))
    error_message = "capacity_reservation_id must be a capacity reservation ID (e.g. cr-0123456789abcdef0), or null."
  }
}
variable "capacity_reservation_preference" {
  type        = string
  default     = "capacity-reservations-only"
  description = "What the instance does when the reservation has no room. capacity-reservations-only as the _monolithic template had it: it does not launch. \"open\" falls back to ordinary On-Demand capacity, which is friendlier and defeats the purpose of reserving scarce GPU capacity in the first place"

  validation {
    condition     = contains(["capacity-reservations-only", "open", "none"], var.capacity_reservation_preference)
    error_message = "capacity_reservation_preference must be capacity-reservations-only, open or none."
  }
}
