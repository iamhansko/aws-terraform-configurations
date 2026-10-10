variable "region" {
  type        = string
  description = "Region the userdata's ECR and S3 calls are made against. Passed in rather than read from a data source, so this module contains no data source and nothing in it is deferred to apply when the caller orders it with depends_on (rules.md D-6)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region code such as ap-northeast-2."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the bastion security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in. A public one: the build pulls the docker package and the golang base image, and pushes to ECR and S3, all from userdata and all outbound"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the instance launches from. An Amazon Linux 2023 image, resolved in the root from a public SSM parameter and passed in so this module does not have to know where it came from (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). If the SSM parameter lookup in the root is returning something else, this is where it shows up."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type, as the _monolithic template's ResourceMap had it. The build is a single docker build of a golang image, so this is bounded by download time rather than by CPU"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "instance_name" {
  type        = string
  description = "Name tag of the instance and its elastic IP"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "key_name" {
  type        = string
  description = "Key pair placed on the instance. This is also the hop to the container instances, whose security group admits SSH from this one"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets an automatically assigned public address, as the _monolithic template set. True, and it matters even though an elastic IP is associated afterwards: the automatic address is what the instance has during the first seconds of cloud-init, which is when the first download starts"
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be gp2, gp3, io1 or io2."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. Thirty rather than the AMI's eight, which is a divergence from the _monolithic template - see the resource for why a single-stage golang build needs the headroom"

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB. The golang base image is around a gigabyte unpacked, docker keeps the pulled layers as well as the built image, and the built image carries the whole toolchain because the Dockerfile is a single stage - a build that runs the disk out of space fails in the middle of a layer."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the bastion security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\" (rules.md F-1)."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the bastion builder instance, which pushes the seed image and the pipeline source archive"
  description = "Description attached to the bastion security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects CreateSecurityGroup with InvalidParameterValue (rules.md F-1)."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the SSH rule opens, which is also the port the container instance group admits from this group"

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the SSH port. Open to the internet, as the _monolithic template had it, and worth being deliberate about: this instance holds a key pair whose private half is in Parameter Store and it is the hop to the private container instances. The instance also carries AmazonSSMManagedInstanceCore, so Session Manager works without any inbound rule at all - set this to [] to close the port and lose nothing but the ssh command in the outputs"

  validation {
    condition     = alltrue([for block in var.ssh_ingress_cidr_blocks : can(cidrhost(block, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "role_name_prefix" {
  type        = string
  description = "Prefix the instance role name is generated from, replacing the _monolithic template's Ec2AdminRole plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-38 characters from the IAM role name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "instance_profile_name_prefix" {
  type        = string
  description = "Prefix the instance profile name is generated from, replacing the _monolithic template's Ec2AdminProfile plus a uuid-derived suffix"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.instance_profile_name_prefix))
    error_message = "instance_profile_name_prefix must be 1-38 characters from the IAM name character set, leaving room for the generated suffix inside IAM's 64 character limit."
  }
}
variable "create_build_policy" {
  type        = bool
  default     = true
  description = "Whether to create the inline policy covering the four things the userdata does: put the source archive, get a registry token, push the seed image, and let the caller's completion check read ECR and S3 back. True, and turning it off means supplying an equivalent through iam_policy_arns (rules.md A-5)"
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = "Managed policies attached to the instance role, on top of the inline build policy. One, where the _monolithic template attached AdministratorAccess - see the inline policy resource for why that is narrowed here rather than exempted as a workbench (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-zA-Z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = anytrue([for arn in var.iam_policy_arns : endswith(arn, "/AmazonSSMManagedInstanceCore")])
    error_message = "iam_policy_arns must include arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore. The completion check that replaces the CloudFormation CreationPolicy is an SSM association targeting this instance, and without the agent's permissions that association never reaches the instance - which surfaces as the association timing out rather than as a missing policy."
  }
}
variable "source_bucket_name" {
  type        = string
  description = "Bucket the source archive is uploaded to, which is also the bucket the pipeline's source action reads. Taken from the bucket module so the upload target and the pipeline source are one value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.source_bucket_name))
    error_message = "source_bucket_name must be a valid S3 bucket name: 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "ARN of that bucket, which the inline policy's S3 statement is scoped to. Both the name and the ARN are taken because the policy cannot be written from the name alone and reassembling an ARN from a name is how a policy comes to point at the wrong bucket (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "source_object_key" {
  type        = string
  default     = "src.zip"
  description = "Key the archive is written under, which is also the local filename. The pipeline's source action reads exactly this key, the CloudTrail selector records writes to exactly this object, and the EventBridge pattern matches exactly this key - one value for all four (rules.md B-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9!._*'()-]+\\.zip$", var.source_object_key))
    error_message = "source_object_key must be a single .zip filename with no slashes. It is used both as a local filename and as the S3 key, and the CodePipeline S3 source action requires a zip archive."
  }
}
variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the repository, which the inline policy's push statement is scoped to"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:ecr:", var.ecr_repository_arn))
    error_message = "ecr_repository_arn must be an ECR repository ARN."
  }
}
variable "ecr_registry_url" {
  type        = string
  description = "Registry host on its own, which is what docker login takes. A login carrying a repository path is accepted and then fails to match on the push"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com$", var.ecr_registry_url))
    error_message = "ecr_registry_url must be a registry host with no repository path, such as 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com."
  }
}
variable "ecr_image_uri" {
  type        = string
  description = "Full reference the seed image is tagged and pushed as. The same value the task definition pulls, taken from the repository module so the push and the pull cannot differ (rules.md B-5)"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$", var.ecr_image_uri))
    error_message = "ecr_image_uri must be a fully qualified ECR image reference including a tag."
  }
}
variable "go_base_image" {
  type        = string
  default     = "golang:1.16"
  description = "Base image of the seed Dockerfile. golang:1.16 as the _monolithic template specified, which is the version the buildspec's Dockerfile also names. Worth knowing that it is from 2021 and long out of support, and that both Dockerfiles are single stage, so the resulting image carries the whole toolchain rather than just the binary"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[a-zA-Z0-9._-]+$", var.go_base_image))
    error_message = "go_base_image must be an image reference including a tag. An untagged reference resolves to :latest, which for golang means the build is pinned to nothing at all."
  }
}
variable "container_port" {
  type        = number
  default     = 80
  description = "Port the Go server listens on, which the Dockerfile exposes and the task definition publishes. Taken by the caller from the load balancer module so all three are one value (rules.md B-5)"

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Route the Go server answers health checks on. The same path the target groups request and the container's own health check command requests (rules.md B-5)"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with a slash."
  }
}
variable "health_response_body" {
  type        = string
  default     = "OK"
  description = "Body the health route returns, as the _monolithic template had it. The target group matches on the status code rather than the body, so this is only ever read by a person"

  validation {
    condition     = length(var.health_response_body) > 0
    error_message = "health_response_body must not be empty."
  }
}
variable "dummy_path" {
  type        = string
  default     = "/v1/dummy"
  description = "Route the demo response is served on, as the _monolithic template had it. This is the URL the project's own notes show before and after a deployment"

  validation {
    condition     = startswith(var.dummy_path, "/")
    error_message = "dummy_path must start with a slash."
  }
}
variable "dummy_response_body" {
  type        = string
  default     = "BLUE"
  description = "Body the demo route returns in the seed image, as the _monolithic template had it. The pipeline rebuilds from the archive this instance uploaded, so editing main.go in the archive and re-uploading is what makes the response change - which is the before and after the project's notes show"

  validation {
    condition     = length(var.dummy_response_body) > 0
    error_message = "dummy_response_body must not be empty."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Directory the completion marker is written to at the very end of the userdata, replacing the CloudFormation CreationPolicy's cfn-signal. When null no marker is written and the caller has nothing to wait on (rules.md B-4)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
