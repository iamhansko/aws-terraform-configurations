variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "project_name" {
  type        = string
  default     = "comfyui-on-ecs"
  description = "Base name for every resource here. At most 20 characters: the admin pages' target groups are named <project_name>-shutdown and the like, and ELB allows 32"

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,18}[a-z0-9])$", var.project_name))
    error_message = "project_name must be 2-20 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
  validation {
    # ECS reserves these prefixes for capacity provider names, and the GPU provider is named after this.
    condition     = !can(regex("^(aws|ecs|fargate)", var.project_name))
    error_message = "project_name must not begin with aws, ecs or fargate - ECS rejects a capacity provider whose name starts with one of them, and the GPU capacity provider is named <project_name>-gpu."
  }
}

# --- Sign-in --------------------------------------------------------------------------------------------

variable "self_sign_up" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether anyone can create an account in the Cognito user pool in front of ComfyUI, the blueprint's
    self_sign_up_enabled.

    False, as the blueprint defaulted it, and worth leaving false: the application is a ComfyUI instance on
    GPU compute, so an open sign-up is an open invitation to run someone else's workloads on it. Users are then
    added by an administrator - see the create_user_command output.
  DESC
}
variable "allowed_sign_up_email_domains" {
  type        = list(string)
  default     = []
  description = "Email domains allowed to sign up, the blueprint's allowed_sign_up_email_domains. Empty means no check, the blueprint's None; a non-empty list adds the pre sign-up function, which also applies to users an administrator creates"

  validation {
    condition     = alltrue([for domain in var.allowed_sign_up_email_domains : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", domain))])
    error_message = "allowed_sign_up_email_domains must contain bare domains such as example.co.jp, without an @ and without a scheme."
  }
  validation {
    # A pair that can be wrong rather than either value alone: self sign-up with no domain restriction is
    # exactly the open pool the self_sign_up description warns about (rules.md B-1).
    condition     = var.self_sign_up ? length(var.allowed_sign_up_email_domains) > 0 : true
    error_message = "allowed_sign_up_email_domains must name at least one domain when self_sign_up is true. Self sign-up with no domain restriction lets anyone create an account in front of GPU compute. Set self_sign_up = false and create users by hand instead, which is what the default does."
  }
}
variable "mfa_required" {
  type        = bool
  default     = false
  description = "Whether every user must set up a second factor, the blueprint's mfa_required. With false, MFA is optional - offered as an authenticator app or SMS"
}
variable "cognito_advanced_security_mode" {
  type        = string
  default     = "ENFORCED"
  description = "Cognito threat protection, ENFORCED as the blueprint set it. ENFORCED and AUDIT put the user pool on the Plus feature plan, billed per monthly active user with no free tier - which is where the blueprint's pool ended up without saying so. OFF puts it on Essentials"

  validation {
    condition     = contains(["ENFORCED", "AUDIT", "OFF"], var.cognito_advanced_security_mode)
    error_message = "cognito_advanced_security_mode must be ENFORCED, AUDIT or OFF."
  }
}

# --- Network restriction --------------------------------------------------------------------------------

variable "alb_ingress_cidr_blocks" {
  type        = list(string)
  default     = null
  description = <<-DESC
    Source addresses the load balancer's security group admits on ports 80 and 443.

    Null, the default, means "my IP": the apply looks up the address this machine appears as from outside and
    admits that one address as a /32. The blueprint opened both ports to 0.0.0.0/0 and relied on the Cognito
    login alone; this closes the door in front of that, so an unauthenticated request from anywhere else is
    not answered at all.

    Two things follow from the default that are worth knowing. The next apply from a different network - or
    after the address is reassigned - moves the rule to the new address and stops answering the old one, which
    is the point but is also how you lock yourself out of a deployment you left running. And anyone else who
    needs in has to be named here, whatever their Cognito account says.

    Name the addresses explicitly to share it: ["203.0.113.4/32", "198.51.100.0/24"]. ["0.0.0.0/0"] is the
    blueprint's behaviour, and writing it down is the only way to get it.
  DESC

  validation {
    condition     = var.alb_ingress_cidr_blocks == null || length(coalesce(var.alb_ingress_cidr_blocks, [])) > 0
    error_message = "alb_ingress_cidr_blocks must name at least one address, or be null to use this machine's own. An empty list leaves the load balancer with no inbound rule, which answers nothing from anywhere and looks like a broken deployment rather than a closed one."
  }
  validation {
    # cidrhost alone would also accept an IPv6 block, which these rules (cidr_ipv4) reject at apply.
    condition     = alltrue([for cidr in coalesce(var.alb_ingress_cidr_blocks, []) : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", cidr)) && can(cidrhost(cidr, 0))])
    error_message = "alb_ingress_cidr_blocks must contain IPv4 CIDR blocks such as 203.0.113.4/32. A single address needs the /32."
  }
}
variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Where the apply asks for its own public address when alb_ingress_cidr_blocks is null. Overridable because it is the one read in this configuration that is not an AWS API call, so a plan needs to reach it - and on a network that intercepts it, naming the addresses instead is the way out"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an https URL - the answer decides what the load balancer admits, so it is not worth taking over plain HTTP."
  }
}
variable "allowed_ipv4_address_ranges" {
  type        = list(string)
  default     = []
  description = "IPv4 CIDR blocks the WAF web ACL admits, the blueprint's allowed_ip_v4_address_ranges. A second gate behind alb_ingress_cidr_blocks rather than an alternative to it: the security group decides which addresses reach the load balancer at all, and an address named only here still never arrives. Empty means the web ACL does no address filtering, which is the blueprint's default and is no longer the same as open"

  validation {
    # cidrhost alone would also accept an IPv6 block, which would then go into the IPv4 IP set and fail at
    # apply; the pattern keeps the two lists apart.
    condition     = alltrue([for range in var.allowed_ipv4_address_ranges : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", range)) && can(cidrhost(range, 0))])
    error_message = "allowed_ipv4_address_ranges must contain valid IPv4 CIDR blocks such as 203.0.113.4/32."
  }
}
variable "allowed_ipv6_address_ranges" {
  type        = list(string)
  default     = []
  description = "IPv6 CIDR blocks allowed to reach the load balancer. The load balancer is IPv4-only, as the blueprint's was, so this list admits nothing on its own - setting it does turn the web ACL's default action to block"

  validation {
    condition     = alltrue([for range in var.allowed_ipv6_address_ranges : can(regex("^[0-9a-fA-F:]+/[0-9]{1,3}$", range)) && can(cidrhost(range, 0))])
    error_message = "allowed_ipv6_address_ranges must contain IPv6 CIDR blocks such as 2001:db8::/32."
  }
}
variable "waf_rate_limit_enabled" {
  type        = bool
  default     = false
  description = "Whether an address sending more than waf_rate_limit_requests to /api/prompt within waf_rate_limit_interval_seconds is blocked, the blueprint's waf_rate_limit_enabled. As the blueprint ordered the rules it applies only when no address list is set: an allow-listed address skips it"
}
variable "waf_rate_limit_requests" {
  type        = number
  default     = 300
  description = "Requests to /api/prompt an address may send per interval, the blueprint's waf_rate_limit_requests"

  validation {
    condition     = var.waf_rate_limit_requests >= 10 && var.waf_rate_limit_requests <= 2000000000
    error_message = "waf_rate_limit_requests must be between 10 and 2,000,000,000 - the range a WAF rate-based rule accepts."
  }
}
variable "waf_rate_limit_interval_seconds" {
  type        = number
  default     = 300
  description = "Window the rate limit counts over, the blueprint's waf_rate_limit_interval"

  validation {
    condition     = contains([60, 120, 300, 600], var.waf_rate_limit_interval_seconds)
    error_message = "waf_rate_limit_interval_seconds must be 60, 120, 300 or 600 - the evaluation windows WAF offers."
  }
}
variable "alb_ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  description = "Security policy of the HTTPS listener. The blueprint set none, which through CloudFormation means ELBSecurityPolicy-2016-08 and TLS 1.0 and 1.1 with it; this default is the one the ELB console picks"

  validation {
    condition     = startswith(var.alb_ssl_policy, "ELBSecurityPolicy-")
    error_message = "alb_ssl_policy must be the name of an ELB security policy."
  }
}
variable "certificate_import_delay" {
  type        = string
  default     = "60s"
  description = "How long to wait between generating the load balancer's self-signed certificate and importing it into ACM. A margin for clock drift, not a tuning knob - ACM rejects a certificate its own clock says is still in the future, and the certificate's notBefore is this machine's idea of now. Raise it only if an apply fails with \"The certificate is valid in the future\"; see time_sleep.certificate_valid in modules/load_balancer"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(s|m|h)$", var.certificate_import_delay))
    error_message = "certificate_import_delay must be a Go duration string such as 60s, 1.5m or 1h."
  }
}
variable "certificate_version" {
  type        = number
  default     = 1
  description = "Version of the self-signed certificate's private key. Increase it to issue a new key and certificate and swap them into the HTTPS listener - the key never reaches the state file, so this number is the only way to ask for a new one. Browsers trust neither the old nor the new one, so the only reason to is a key you believe was exposed"

  validation {
    condition     = var.certificate_version >= 1 && floor(var.certificate_version) == var.certificate_version
    error_message = "certificate_version must be a positive whole number."
  }
}

# --- Network --------------------------------------------------------------------------------------------

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC, 10.0.0.0/16 as CDK defaulted the blueprint's"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0)) && can(regex("^[0-9.]+/[0-9]+$", var.vpc_cidr_block))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "b"]
  description = "The two zone letters the VPC spans. The blueprint's max_azs=2 took the region's first two, a and b. Both zones need to offer at least one of instance_types for spot to have two places to look"

  validation {
    condition     = length(var.availability_zone_suffixes) == 2 && length(distinct(var.availability_zone_suffixes)) == 2 && alltrue([for suffix in var.availability_zone_suffixes : can(regex("^[a-z]$", suffix))])
    error_message = "availability_zone_suffixes must contain two different single lowercase letters."
  }
}
variable "nat_instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "Instance type of the two NAT instances, t4g.nano as the blueprint's cheap_vpc had it. The GPU instance pulls its plugin, its updates and its model downloads through one of these, and the image through the S3 endpoint"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*g[a-z]*\\.[a-z0-9]+$", var.nat_instance_type))
    error_message = "nat_instance_type must be a Graviton instance type such as t4g.nano - the NAT AMI is the arm64 one."
  }
}

# --- GPU capacity ---------------------------------------------------------------------------------------

variable "ecs_gpu_ami_parameter" {
  type        = string
  default     = "/aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended/image_id"
  description = "Public SSM parameter of the GPU instance AMI - the ECS-optimized Amazon Linux 2 GPU AMI, as the blueprint's EcsOptimizedImage.amazon_linux2(GPU). Amazon Linux 2 has reached the end of its standard support; the AL2023 equivalent is /aws/service/ecs/optimized-ami/amazon-linux-2023/gpu/recommended/image_id, untested with the blueprint's REX-Ray user data"

  validation {
    condition     = startswith(var.ecs_gpu_ami_parameter, "/aws/service/ecs/optimized-ami/")
    error_message = "ecs_gpu_ami_parameter must be an ECS-optimized AMI parameter under /aws/service/ecs/optimized-ami/."
  }
}
variable "instance_types" {
  type        = list(string)
  default     = ["g4dn.xlarge", "g5.xlarge", "g6.xlarge"]
  description = "GPU instance types the Auto Scaling group may launch, the blueprint's instance_types. The task's memory reservation is sized from the smallest of them"

  validation {
    condition     = length(var.instance_types) > 0 && alltrue([for type in var.instance_types : can(regex("^(g|p)[0-9][a-z0-9-]*\\.[a-z0-9]+$", type))])
    error_message = "instance_types must contain at least one G or P (NVIDIA GPU) instance type such as g5.xlarge - the AMI is the GPU one and the task reserves a GPU."
  }
}
variable "use_spot" {
  type        = bool
  default     = true
  description = "Whether the GPU instance is spot, the blueprint's use_spot. Spot is much cheaper and can be reclaimed; ComfyUI's data is on a separate EBS volume and survives that"
}
variable "spot_max_price" {
  type        = string
  default     = "0.752"
  description = "Highest hourly spot price paid, in US dollars - the blueprint's spot_price. While every listed type costs more, no instance launches"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.spot_max_price)) && tonumber(var.spot_max_price) > 0
    error_message = "spot_max_price must be a positive decimal number of US dollars, such as 0.752."
  }
}
variable "auto_scale_down" {
  type        = bool
  default     = true
  description = "Whether the GPU instance is stopped after an hour of CPU below 1%, the blueprint's auto_scale_down. Scale Up on the /admin page starts it again"
}
variable "schedule_auto_scaling" {
  type        = bool
  default     = false
  description = "Whether the GPU instance is also stopped and started on a schedule, the blueprint's schedule_auto_scaling"
}
variable "schedule_timezone" {
  type        = string
  default     = "UTC"
  description = "IANA time zone of the schedule, the blueprint's timezone"

  validation {
    condition     = can(regex("^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$", var.schedule_timezone))
    error_message = "schedule_timezone must be an IANA time zone name such as Asia/Seoul or UTC."
  }
}
variable "schedule_scale_up" {
  type        = string
  default     = "0 9 * * 1-5"
  description = "Cron expression for starting the GPU instance, the blueprint's schedule_scale_up"

  validation {
    condition     = length(split(" ", trimspace(var.schedule_scale_up))) == 5
    error_message = "schedule_scale_up must be a five-field Unix cron expression such as \"0 9 * * 1-5\"."
  }
}
variable "schedule_scale_down" {
  type        = string
  default     = "0 18 * * *"
  description = "Cron expression for stopping the GPU instance, the blueprint's schedule_scale_down"

  validation {
    condition     = length(split(" ", trimspace(var.schedule_scale_down))) == 5
    error_message = "schedule_scale_down must be a five-field Unix cron expression such as \"0 18 * * *\"."
  }
}
variable "root_volume_size_gib" {
  type        = number
  default     = 50
  description = "Root volume of the GPU instance in GiB, 50 as the blueprint had it. Docker keeps the ComfyUI image here"

  validation {
    condition     = var.root_volume_size_gib >= 30
    error_message = "root_volume_size_gib must be at least 30 - the GPU AMI's own root snapshot is that size."
  }
}
variable "comfyui_volume_size_gib" {
  type        = number
  default     = 250
  description = "Size of the EBS volume ComfyUI, its models and its outputs live on, 250 GiB as the blueprint had it. Used only when the volume is first created"

  validation {
    condition     = var.comfyui_volume_size_gib >= 30 && var.comfyui_volume_size_gib <= 16384
    error_message = "comfyui_volume_size_gib must be between 30 and 16384 - the volume starts as a copy of the ComfyUI installation in the image."
  }
}
variable "comfyui_volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS type of that volume, gp3 as the blueprint had it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.comfyui_volume_type)
    error_message = "comfyui_volume_type must be gp2, gp3, io1 or io2."
  }
}

# --- Image build ----------------------------------------------------------------------------------------

variable "build_image_on_apply" {
  type        = bool
  default     = true
  description = "Whether the apply builds the ComfyUI image and waits for it before defining the task. True, so one apply deploys everything. False creates the build project without running it - the task then names a tag that is not pushed yet and cannot start until restart_image_build_command has run (rules.md B-4)"
}
variable "image_build_compute_type" {
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  description = "CodeBuild compute type of the image build. The build compiles Python with pyenv and installs PyTorch into a CUDA base image, and the apply waits for it"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.image_build_compute_type)
    error_message = "image_build_compute_type must be one of the BUILD_GENERAL1_* Linux container compute types."
  }
}
variable "image_build_timeout_minutes" {
  type        = number
  default     = 90
  description = "How long the image build may run. The apply waits up to this plus fifteen minutes"

  validation {
    condition     = var.image_build_timeout_minutes >= 5 && var.image_build_timeout_minutes <= 480
    error_message = "image_build_timeout_minutes must be between 5 and 480."
  }
}
variable "ecr_force_delete" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes the image repository with the images in it. Every image was pushed by a build Terraform does not track, so with false destroy stops on RepositoryNotEmptyException"
}

# --- Logs -----------------------------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  default     = 731
  description = "Retention of every log group here - ComfyUI's, the flow log's, the image build's and the functions'. Two years, as CDK gave the blueprint's ComfyUI and flow log groups; the blueprint left its functions' groups to Lambda, which never expires them"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts."
  }
}
