variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID, e.g. vpc-0123456789abcdef0."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance launches in. Has to be a public subnet with a route to an internet gateway: the seed script reaches github.com and the public S3 endpoint, and a private subnet without a NAT gateway leaves it hanging until the HTTP timeout"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID, e.g. subnet-0123456789abcdef0."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI the instance boots. Resolved from an SSM public parameter by the root and passed in as an id, so this module does not have to know where it came from (rules.md B-6). The userdata is written for Amazon Linux 2023 - it calls dnf"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID, e.g. ami-0123456789abcdef0. An SSM parameter path belongs in the root's data source, not here."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type, as the _monolithic template had it. Generous for a script that downloads a zip and makes a few dozen PUT calls, and inherited rather than chosen - the Development Tools group install is the only part that benefits"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be an EC2 instance type, e.g. t3.medium."
  }
}
variable "instance_name" {
  type        = string
  description = "Name tag of the instance. The _monolithic template tagged it bastion-ec2, which describes something it never was - see the note at the top of main.tf"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "security_group_name" {
  type        = string
  description = "Name of the security group. The _monolithic template created none and used the VPC's default group instead"

  validation {
    # AWS accepts a-zA-Z0-9, space and . _-:/()#,@[]+=&;{}!$* in a security group name, and nothing else -
    # an apostrophe is rejected. Terraform passes the value through unchecked, so without this the failure
    # is an InvalidParameterValue partway through apply rather than a plan error, and the value cannot be
    # corrected in place afterwards because changing it replaces the group (rules.md F-1).
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Outbound only, for the instance that seeds the website bucket and is then terminated"
  description = "Description of the security group. Written without an apostrophe on purpose: the obvious phrasing here is \"the bucket's content\", and that single character is what the validation below exists to catch"

  validation {
    # Same charset as the name, same reason, same cost to get wrong: a description change replaces the
    # group, because AWS has no API for editing one (rules.md F-1).
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time."
  }
}
variable "egress_cidr_ipv4" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Destination the egress rule allows. The whole internet, because the seed script fetches a GitHub release asset and an image from raw.githubusercontent.com as well as calling S3 - narrowing this to the S3 prefix list would leave the download failing"

  validation {
    condition     = can(cidrhost(var.egress_cidr_ipv4, 0))
    error_message = "egress_cidr_ipv4 must be a valid IPv4 CIDR block, e.g. 0.0.0.0/0."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the instance on the SSH port. Empty, which is the normal state and what the _monolithic template effectively had - it created no key pair, so there is nothing to authenticate with even if a rule is added. Session Manager is the route that works without opening anything; see iam_policy_arns"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks, e.g. 203.0.113.4/32."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the optional ingress rules open. Only used when ingress_cidr_blocks is non-empty"

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security groups attached to the instance alongside the one this module creates. Empty here; the input exists so a caller can attach a group it owns without this module learning about it (rules.md B-6)"

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs, e.g. sg-0123456789abcdef0."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address, as the _monolithic template had it. The subnet also defaults to true; both are kept because this is the one that applies to this instance regardless of the subnet it is pointed at. False means an instance that cannot reach github.com, which surfaces as an empty bucket rather than a failed apply"
}
variable "bucket_name" {
  type        = string
  description = "Name of the bucket the seed script writes into, injected rather than discovered (rules.md B-6)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name: 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending alphanumeric."
  }
}
variable "bucket_arn" {
  type        = string
  description = "ARN of the same bucket, used to scope the instance's s3:PutObject permission to it. Taken as a second input rather than built from bucket_name, because an assembled ARN that is wrong produces AccessDenied on every upload and looks identical to a missing policy"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN, e.g. arn:aws:s3:::my-bucket."
  }
}
variable "game_source_url" {
  type        = string
  default     = "https://github.com/iamhansko/escape-room-workshop/releases/download/test/game.zip"
  description = "Zip the seed script downloads and unpacks onto the bucket, as the _monolithic template had it. The src/ directory in this project is the same content before it was released - Terraform does not upload it, and this URL is what actually ends up on the site"

  validation {
    condition     = can(regex("^https://", var.game_source_url))
    error_message = "game_source_url must be an https URL."
  }
}
variable "backend_config_key" {
  type        = string
  default     = "data/lambda.json"
  description = "Key the backend's URL is written to, as the _monolithic template had it. The page fetches this object to find the endpoint, so the key is load-bearing: changing it here without changing the page leaves the game unable to check a password, with every other part of the stack healthy"

  validation {
    condition     = can(regex("^[^/][^\\s]*\\.json$", var.backend_config_key))
    error_message = "backend_config_key must be a .json key without a leading slash, e.g. data/lambda.json."
  }
}
variable "backend_function_url" {
  type        = string
  description = "The backend Lambda's function URL, written into the object above. A value rather than something the script derives, because it does not exist until Lambda creates the URL - which is also why this instance has to be ordered after the function (rules.md B-6)"

  validation {
    condition     = can(regex("^https://", var.backend_function_url))
    error_message = "backend_function_url must be an https URL. Null is not accepted: an instance seeding a site whose page cannot reach its backend is worth failing at plan time."
  }
}
variable "content_types" {
  type = map(string)
  default = {
    html = "text/html"
    css  = "text/css"
    js   = "text/javascript"
    txt  = "text/plain"
    sh   = "text/x-sh"
    png  = "image/png"
    jpg  = "image/jpeg"
    webp = "image/webp"
    svg  = "image/svg+xml"
    gif  = "image/gif"
    json = "application/json"
  }
  description = "Content type per file extension, carried over from the _monolithic template's TYPE_MAP. Needed because S3 stores an object with no content type as application/octet-stream, and a browser downloads that instead of rendering it - so an index.html uploaded without this looks like a broken site rather than a missing header"

  validation {
    condition     = length(var.content_types) > 0
    error_message = "content_types must not be empty, or every uploaded object falls back to default_content_type."
  }
  validation {
    condition     = alltrue([for extension in keys(var.content_types) : can(regex("^[a-z0-9]+$", extension))])
    error_message = "content_types keys are bare lowercase extensions without the dot, e.g. html - the script lowercases the extension it finds and looks it up directly."
  }
}
variable "default_content_type" {
  type        = string
  default     = "application/octet-stream"
  description = "Content type for a file whose extension is not in the map. The _monolithic template had no fallback: it indexed TYPE_MAP directly, so one unexpected extension in the zip raised a KeyError that its blanket except swallowed - leaving a partly uploaded site and an exit code of 0"

  validation {
    condition     = can(regex("^[a-z]+/[a-zA-Z0-9.+-]+$", var.default_content_type))
    error_message = "default_content_type must be a media type, e.g. application/octet-stream."
  }
}
variable "text_objects" {
  type        = map(string)
  default     = {}
  description = "Text objects written into the bucket, keyed by key with the body as the value. The hint files in this project. A map rather than a put_object call per file, which is what the _monolithic template had - five near-identical copies of the same call"

  validation {
    condition     = alltrue([for key in keys(var.text_objects) : can(regex("^[^/]", key))])
    error_message = "text_objects keys must not start with a slash."
  }
}
variable "image_objects" {
  type        = map(string)
  default     = {}
  description = "Objects fetched from a URL and copied into the bucket, keyed by destination key with the source URL as the value. The _monolithic template pulled one hint image straight from a raw.githubusercontent.com path this way"

  validation {
    condition     = alltrue([for key in keys(var.image_objects) : can(regex("^[^/]", key))])
    error_message = "image_objects keys must not start with a slash."
  }
  validation {
    condition     = alltrue([for url in values(var.image_objects) : can(regex("^https://", url))])
    error_message = "image_objects values must be https URLs the instance can reach."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = <<-DESC
    Managed policies attached to the instance's role, on top of the s3:PutObject statement the module
    writes itself.

    The _monolithic template attached AdministratorAccess and nothing else. That is narrowed here, which
    rules.md A-5 allows for an automated role as long as the change is written down - see the policy
    resource in main.tf for what the script actually calls.

    AmazonSSMManagedInstanceCore is not inherited from the template; it is what makes Session Manager work,
    and Session Manager is the only way onto an instance that has no key pair and no inbound rule. With
    AdministratorAccess that worked by accident. Drop it and a failed seed can only be investigated from
    the console log.
  DESC

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "iam_policy_arns must contain IAM policy ARNs, e.g. arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore."
  }
}
variable "additional_policy_statements" {
  type        = list(any)
  default     = []
  description = "Statements added to the instance role's inline policy beyond writing to the bucket. Empty here; supplied by the caller because only the caller knows what else the instance would call (rules.md B-6)"

  validation {
    condition     = alltrue([for statement in var.additional_policy_statements : can(statement.Effect) && can(statement.Action) && can(statement.Resource)])
    error_message = "additional_policy_statements entries must each have Effect, Action and Resource. A statement missing one is accepted by jsonencode and rejected by IAM during apply with MalformedPolicyDocument."
  }
}
variable "inline_policy_name" {
  type        = string
  default     = "seed-website-bucket"
  description = "Name of the inline policy on the instance role. Local to the role, so it only has to be readable"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.inline_policy_name))
    error_message = "inline_policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "instance_profile_name_prefix" {
  type        = string
  default     = "escape-room-seeder-"
  description = "Prefix for the generated instance profile name. A prefix rather than the _monolithic template's literal Ec2AdminProfile-: instance profile names are account-wide, so a literal one fails the second apply in an account with EntityAlreadyExists"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,96}$", var.instance_profile_name_prefix))
    error_message = "instance_profile_name_prefix must be 1-96 characters from the set IAM accepts for a name, leaving room for the generated suffix inside the 128 character limit."
  }
}
variable "python_package" {
  type        = string
  default     = "python3.13"
  description = "Python the seed script runs under, as the _monolithic template had it. Installed from the Amazon Linux 2023 repositories and symlinked to /usr/bin/python. A package name that does not exist there leaves every later line failing on a missing interpreter"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.python_package))
    error_message = "python_package must be a python3.x package name, e.g. python3.13."
  }
}
variable "python_requirements" {
  type        = list(string)
  default     = ["requests", "boto3"]
  description = "Packages pip installs before the seed script runs, as the _monolithic template had it. Both are pure-Python wheels, which is why the Development Tools group below is not actually needed for them"

  validation {
    condition     = length(var.python_requirements) > 0 && alltrue([for requirement in var.python_requirements : can(regex("^[A-Za-z0-9._<>=!-]+$", requirement))])
    error_message = "python_requirements entries must be pip requirement specifiers without spaces, e.g. boto3 or boto3==1.35.0. The list cannot be empty - the script imports boto3 and requests."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["git"]
  description = "Packages installed before Python, as the _monolithic template had it. git is inherited and unused by the seed script; it is kept because the template installed it and someone shelling in to debug will expect it"

  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[A-Za-z0-9._+-]+$", package))])
    error_message = "dnf_packages entries must be package names without spaces."
  }
}
variable "dnf_groups" {
  type        = list(string)
  default     = ["Development Tools"]
  description = "Package groups installed before Python, as the _monolithic template had it. Nothing in the seed script needs a compiler - requests and boto3 ship as wheels - so this is several minutes of boot time inherited from the original. Set it to [] to drop it; the default keeps the original behaviour"

  validation {
    condition     = alltrue([for group in var.dnf_groups : length(group) > 0 && !strcontains(group, "\"")])
    error_message = "dnf_groups entries must be non-empty and must not contain a double quote - the group name is interpolated into a quoted shell argument."
  }
}
variable "script_path" {
  type        = string
  default     = "/root/seed_website.py"
  description = "Where the seed script is written on the instance. The _monolithic template wrote it to index.py in whatever directory cloud-init happened to be in, which is / - an absolute path says where to look for it"

  validation {
    condition     = can(regex("^/[^\\s]*\\.py$", var.script_path))
    error_message = "script_path must be an absolute path ending in .py."
  }
}
variable "http_timeout_seconds" {
  type        = number
  default     = 60
  description = "Timeout on each HTTP fetch the seed script makes. The _monolithic template passed none, so a stalled connection to GitHub would have hung the script until the instance was terminated under it - with no error anywhere"

  validation {
    condition     = var.http_timeout_seconds >= 1 && var.http_timeout_seconds <= 600
    error_message = "http_timeout_seconds must be between 1 and 600."
  }
}
variable "completion_marker" {
  type        = string
  default     = "escape-room-seeder: complete"
  description = "Line echoed to the console log when the seed script succeeds. Everything this instance does happens after apply has returned, on a host with no inbound access that is about to be terminated, so the console log is the only record - and a fixed string to grep for beats reading it. Re-exposed as an output so the root's check command and this line cannot drift apart (rules.md B-5)"

  validation {
    condition     = length(var.completion_marker) > 0 && !strcontains(var.completion_marker, "\"")
    error_message = "completion_marker must be non-empty and must not contain a double quote - it is echoed from a double-quoted shell string."
  }
}
variable "failure_marker" {
  type        = string
  default     = "escape-room-seeder: FAILED"
  description = "Line echoed to standard error when the seed script exits non-zero. The pair matters more than either line: a console log with neither marker means the script never got as far as running, which points at the dnf or pip steps rather than at S3"

  validation {
    condition     = length(var.failure_marker) > 0 && !strcontains(var.failure_marker, "\"")
    error_message = "failure_marker must be non-empty and must not contain a double quote - it is echoed from a double-quoted shell string."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDS requires a session token, i.e. IMDSv2 only. The _monolithic template left this at the default of optional. boto3 negotiates the token itself so the seed script is unaffected, and this role can write to the website bucket - a token-less metadata read is the shape an SSRF uses to reach that"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional."
  }
}
variable "metadata_hop_limit" {
  type        = number
  default     = 1
  description = "IMDS response hop limit. One, which is right for a script running directly on the host - a container would need two, and nothing here runs in one"

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "metadata_hop_limit must be between 1 and 64."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Shell appended after the seed script runs. Null renders nothing at all rather than an empty line, through a template directive rather than plain interpolation (rules.md B-4). Note it runs after the exit on failure, so it is not reached when seeding fails"

  validation {
    condition     = var.additional_user_data == null || length(var.additional_user_data) > 0
    error_message = "additional_user_data must be a non-empty script or null."
  }
}
