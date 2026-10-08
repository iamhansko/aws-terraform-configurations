variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in. Must be a public subnet: the instance pulls the docker package from the Amazon Linux repositories, pulls the amazoncorretto base image from Docker Hub and pushes the result to ECR, all from userdata and all over the internet"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = <<-DESC
    AMI for the instance, resolved by the caller. Taken as an id rather than looked up here so the module
    does not need to know that the caller reads it from an SSM public parameter (rules.md B-6).

    It has to be an arm64 image, and that is the point of the project rather than an incidental choice -
    see instance_type.
  DESC

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "instance_name" {
  type        = string
  default     = "arm64"
  description = "Name tag for the instance, as the _monolithic template had it"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t4g.medium"
  description = <<-DESC
    Instance type, as the _monolithic template had it. t4g is Graviton, and that is load-bearing: docker
    build with no --platform produces an image for the architecture of the machine doing the building, and
    the container instances that pull it are arm64 too.

    Building this on an x86 type pushes an amd64 manifest, every ECS task then stops with
    "image Manifest does not contain descriptor matching platform linux/arm64", and nothing upstream of
    that reports a problem - the push succeeded, the repository has an image, the task definition is valid.
    The validation below rejects the families that would cause it.
  DESC

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t4g.medium)."
  }

  validation {
    # Graviton families end their size-independent prefix with g, optionally followed by feature letters
    # (t4g, c7g, m8g, c7gn, r8gd). This is a shape check rather than a list of every family, so a type
    # that does not match is rejected with the explanation rather than silently producing an amd64 image.
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) family such as t4g.medium or c7g.large, because docker build here produces an image for the builder's own architecture and the ECS container instances pulling it are arm64. To build for arm64 on an x86 builder, add --platform linux/arm64 and QEMU emulation to the userdata instead."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. No port is open to this instance, so this is a fallback for the case where the SSM agent is what is broken"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address. True, as the _monolithic template had it: the build reaches Docker Hub and ECR directly rather than through the NAT gateway, since the instance is in a public subnet"
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = <<-DESC
    Root volume size in GiB. The _monolithic template left this unset, which takes the AMI's own 8 GiB.

    Raised deliberately. The build pulls the amazoncorretto:21 base image, runs a yum update inside it and
    writes a new layer, so the docker graph holds the base image, the intermediate layers and the final
    image at once. On 8 GiB that runs the root filesystem out of space partway through, and docker reports
    it as a failed layer write rather than as a full disk - and because the userdata does not stop on
    error, the script carries on to the push and the marker file regardless.
  DESC

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB to hold the base image, the intermediate layers and the built image at the same time."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2, standard."
  }
}
variable "security_group_name" {
  type        = string
  default     = "ecs-volumes-builder-sg"
  description = "Name of the security group"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the arm64 image builder instance"
  description = "Description attached to the security group. Changing it replaces the group, because AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "ssh_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Source CIDRs allowed to reach port 22. Empty creates no ingress rule at all, which is what the
    _monolithic template's security group had - it declared no ingress of any kind.

    Empty is kept as the default rather than opened, because nothing needs to reach this instance: it
    builds an image, pushes it and is then idle, and the role it carries plus the SSM agent in the AMI
    make Session Manager the way in. A list rather than a boolean so a narrower source can be given,
    which is the only form worth using if it is opened at all.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ssh_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, kept rather than narrowed. What
    the userdata actually needs is an ECR authorization token plus push permission on one repository and
    the SSM agent's own permissions, so this is far wider than the work - but narrowing it here would be
    narrowing what the original could do rather than reproducing it, and rules.md A-5 draws that line
    around the roles of controllers and agents, not around a human-facing box.

    This instance is the closest thing this project has to a workbench: it is where a failed build is
    diagnosed, which means running docker and the AWS CLI by hand over Session Manager. A-5's audit
    command filters on the names vscode_ec2 and bastion, so this module shows up in it as a finding. It is
    not one.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs."
  }
}
variable "ecr_image_uri" {
  type        = string
  description = "Full repository URL and tag the build is tagged with and pushed to, taken from the repository module so the push and the task definition's pull cannot name different things (rules.md B-5)"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9][a-z0-9._/-]*:[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.ecr_image_uri))
    error_message = "ecr_image_uri must be a full ECR reference including the tag, e.g. 111122223333.dkr.ecr.ap-northeast-2.amazonaws.com/repo:latest."
  }
}
variable "ecr_registry_url" {
  type        = string
  description = "Registry host for docker login, without the repository path. The docker CLI accepts a login against a host plus path and then does not match it on push, so the push retries unauthenticated and fails with \"no basic auth credentials\" - which reads as a permissions problem rather than a malformed login"

  validation {
    condition     = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com$", var.ecr_registry_url))
    error_message = "ecr_registry_url must be an ECR registry host with no path, e.g. 111122223333.dkr.ecr.ap-northeast-2.amazonaws.com."
  }
}
variable "container_mount_path" {
  type        = string
  default     = "/app/test"
  description = "Directory inside the container that the test script writes into. The task definition bind-mounts the host volume over exactly this path, so the two have to agree - the caller passes one value to both (rules.md B-5). If they disagree the container writes into its own writable layer instead, the task runs happily, and nothing ever appears on the host"

  validation {
    condition     = can(regex("^/[^\\s]+$", var.container_mount_path))
    error_message = "container_mount_path must be an absolute path with no whitespace."
  }
}
variable "write_size_mb" {
  type        = number
  default     = 200
  description = "Size in MiB of each file the in-container test writes, as the _monolithic template had it. This is the load the demo puts on the volume, so it is the number to change to make the difference between a bind mount and a container filesystem visible sooner"

  validation {
    condition     = var.write_size_mb >= 1
    error_message = "write_size_mb must be at least 1."
  }
}
variable "retained_file_count" {
  type        = number
  default     = 5
  description = "How many written files the test keeps before deleting the oldest, as the _monolithic template had it. This is what stops the volume filling: with 200 MiB files and a one second pause, an unbounded loop fills a host volume quickly and the task is then killed for disk pressure rather than reporting anything"

  validation {
    condition     = var.retained_file_count >= 1
    error_message = "retained_file_count must be at least 1."
  }
}
variable "java_base_image" {
  type        = string
  default     = "amazoncorretto:21"
  description = "Base image the test container is built from, as the _monolithic template had it. Nothing in the test is Java - it is dd and du in a shell - so this is here because the project's subject is an arm64 JDK image's behaviour on a bind mount"

  validation {
    condition     = can(regex("^[a-z0-9][a-zA-Z0-9._/-]*:[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.java_base_image))
    error_message = "java_base_image must be an image reference including an explicit tag, e.g. amazoncorretto:21. An untagged reference resolves to latest, so the image the demo builds would change under it without the configuration changing."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = <<-DESC
    Optional absolute directory in which the userdata writes a completion marker as its last action. Null
    creates no marker (rules.md B-4).

    This is what replaces the CreationPolicy the CloudFormation template had on this instance. That
    policy held the stack at this resource until cfn-signal reported from inside the userdata, which is
    how the task definition and service ended up being created only after the image existed. The
    conversion dropped it - its own comment says so - leaving nothing between "the RunInstances call
    returned" and "the service starts pulling an image that has not been built yet".

    The marker is the first half of getting that back; the caller polls for it from an SSM association and
    orders the service after it. Note what the marker does and does not say: it says the script reached
    its end, not that the push worked, because the script does not stop on error. Checking the repository
    is the caller's job and not something a marker file can do.
  DESC

  validation {
    condition     = var.marker_file_path == null || can(regex("^/[^\\s]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
