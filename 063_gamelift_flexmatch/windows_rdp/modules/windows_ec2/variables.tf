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
  description = "Public subnet the instance is launched in. Everything the setup does is outbound to the internet, and the participant reaches it over RDP from outside"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "Windows Server AMI id. Resolved in the root from the public SSM parameter, so this module only sees an id (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  description = "Key pair the instance is launched with. On Windows this is what encrypts the Administrator password"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "instance_name" {
  type        = string
  default     = "gamelift-flexmatch-windows"
  description = "Name tag of the instance"

  validation {
    condition     = length(var.instance_name) > 0 && length(var.instance_name) <= 256
    error_message = "instance_name must be 1-256 characters."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address. True, as the _monolithic template had it: it is the RDP target and has no other way out to the internet"
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type, as the _monolithic template had it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be gp2, gp3, io1 or io2."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB, as the _monolithic template had it"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, the size of a Windows Server Full Base root volume before anything the setup installs."
  }
}
variable "root_volume_encrypted" {
  type        = bool
  default     = false
  description = "Whether the root volume is encrypted. False, as the _monolithic template had it; an account with EBS encryption by default encrypts it anyway"
}
variable "security_group_name" {
  type        = string
  default     = "gamelift-flexmatch-windows-sg"
  description = "Name of the instance's security group. The _monolithic template used windows-sg; unique per VPC, so derived from project_name in the root mostly for findability"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set EC2 accepts for a security group name (no apostrophe) and must not start with \"sg-\"."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description of the instance's security group, as the _monolithic template had it. Changing it replaces the group (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set EC2 accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is not allowed."
  }
}
variable "rdp_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source CIDRs allowed to reach RDP. Empty creates no ingress rule. Replaces the _monolithic template's inbound_from_anywhere string: [\"0.0.0.0/0\"] is True, [] is False"

  validation {
    condition     = alltrue([for cidr in var.rdp_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "rdp_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "rdp_port" {
  type        = number
  default     = 3389
  description = "Port the security group opens for RDP. Changing it changes only the security group, not where Terminal Services listens"

  validation {
    condition     = var.rdp_port >= 1 && var.rdp_port <= 65535
    error_message = "rdp_port must be a valid TCP port."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policies attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, kept rather than narrowed:
    this instance is a human workbench - the participant sits at its desktop, and the workshop has them
    poke at GameLift, S3 and the rest from it - which is the class of role rules.md A-5 exempts (H-1
    takes the same position for vscode_ec2 and bastion_ec2). A-5's audit filters on those two names, so
    this module shows up in it; it is not a finding.

    The setup itself needs far less - secretsmanager:GetSecretValue on the workshop secret, s3:PutObject
    on the two buckets, and AmazonSSMManagedInstanceCore for the association that waits on it.
  DESC

  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "user_data_replace_on_change" {
  type        = bool
  default     = true
  description = "Whether changing the userdata rebuilds the instance. True, a divergence from the _monolithic template's provider default of false: EC2Launch runs user data once, on first boot, so with false an edit produces a plan that reports a change and does nothing to the machine"
}
variable "aws_region" {
  type        = string
  description = "Region written into the setup: the Secrets Manager call, the server's SQS_REGION, and the API host name in the client config"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2."
  }
}
variable "workshop_username" {
  type        = string
  default     = "gamelift"
  description = "Windows local account the setup creates for the RDP login, with the password read from secret_id"

  validation {
    condition     = can(regex("^[^\"/\\\\\\[\\]:;|=,+*?<>@ ]{1,20}$", var.workshop_username))
    error_message = "workshop_username must be 1-20 characters and must not contain a space, @, or any of \" / \\ [ ] : ; | = , + * ? < >, because New-LocalUser rejects those on the instance and the failure never reaches Terraform."
  }
}
variable "secret_id" {
  type        = string
  description = "Secret holding {\"username\": ..., \"password\": ...}, read at boot by Get-SECSecretValue. The caller must order this module after the secret's version, not only the secret"

  validation {
    condition     = length(var.secret_id) > 0
    error_message = "secret_id must not be empty."
  }
}
variable "workshop_dir" {
  type        = string
  default     = "C:\\ProgramData\\GameliftWorkshop"
  description = "Directory on the instance holding the setup log, the clone and the completion marker, as the _monolithic template had it. Under ProgramData because the userdata runs as SYSTEM before the workshop account's profile exists"

  validation {
    condition     = can(regex("^[A-Za-z]:\\\\[^\"<>|']*[^\"<>|'\\\\]$", var.workshop_dir))
    error_message = "workshop_dir must be an absolute Windows path with a drive letter and no trailing backslash, e.g. C:\\ProgramData\\GameliftWorkshop, and must not contain \" < > | or a single quote (it is embedded in single-quoted PowerShell strings)."
  }
}
variable "marker_file_name" {
  type        = string
  default     = "userdata.done"
  description = "File the setup creates in workshop_dir as its very last action. The root's association waits for it (rules.md D-5)"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.marker_file_name))
    error_message = "marker_file_name must be a plain file name of letters, digits, dots, hyphens and underscores."
  }
}
variable "failure_marker_file_name" {
  type        = string
  default     = "userdata.failed"
  description = "File the setup's catch block writes the error into, so the waiting association can fail at once with the reason instead of running out its attempts"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.failure_marker_file_name))
    error_message = "failure_marker_file_name must be a plain file name of letters, digits, dots, hyphens and underscores."
  }
}
variable "git_clone_url" {
  type        = string
  default     = "https://github.com/iamhansko/aws-gamelift-sample.git"
  description = "Repository the setup clones, as the _monolithic template had it. Load-bearing: Lambda/code.zip, the prebuilt server and both game clients come from it, and the paths below are its layout"

  validation {
    condition     = can(regex("^https://", var.git_clone_url)) && !strcontains(var.git_clone_url, "'")
    error_message = "git_clone_url must be an https URL without a single quote."
  }
}
variable "clone_directory_name" {
  type        = string
  default     = "aws-gamelift-sample"
  description = "Directory under workshop_dir the repository is cloned into. The _monolithic template let git name it after the URL and then hard-coded aws-gamelift-sample in a dozen paths; naming it explicitly keeps the two from disagreeing"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.clone_directory_name))
    error_message = "clone_directory_name must be a plain directory name of letters, digits, dots, hyphens and underscores."
  }
}
variable "git_available_retries" {
  type        = number
  default     = 10
  description = "How many 3-second waits the setup allows for git to appear on PATH after Chocolatey installs it, as the _monolithic template had it"

  validation {
    condition     = var.git_available_retries >= 1 && var.git_available_retries <= 200
    error_message = "git_available_retries must be between 1 and 200."
  }
}
variable "game_source_bucket_name" {
  type        = string
  description = "Bucket server.zip, client.zip and the clone (with Lambda/code.zip in it) are uploaded to"

  validation {
    condition     = length(var.game_source_bucket_name) >= 3 && length(var.game_source_bucket_name) <= 63
    error_message = "game_source_bucket_name must be a bucket name of 3-63 characters."
  }
}
variable "web_bucket_name" {
  type        = string
  description = "Bucket the patched leaderboard page is uploaded to"

  validation {
    condition     = length(var.web_bucket_name) >= 3 && length(var.web_bucket_name) <= 63
    error_message = "web_bucket_name must be a bucket name of 3-63 characters."
  }
}
variable "server_build_s3_key" {
  type        = string
  default     = "server.zip"
  description = "Key the server build is uploaded to. The GameLift build reads the same key"

  validation {
    condition     = endswith(var.server_build_s3_key, ".zip") && !startswith(var.server_build_s3_key, "/")
    error_message = "server_build_s3_key must be a .zip key without a leading slash."
  }
}
variable "client_archive_s3_key" {
  type        = string
  default     = "client.zip"
  description = "Key the two game clients are uploaded to, for a participant to download from the console"

  validation {
    condition     = endswith(var.client_archive_s3_key, ".zip") && !startswith(var.client_archive_s3_key, "/")
    error_message = "client_archive_s3_key must be a .zip key without a leading slash."
  }
}
variable "game_result_queue_url" {
  type        = string
  description = "Queue URL baked into the server's config.ini as SQS_ENDPOINT"

  validation {
    condition     = can(regex("^https://", var.game_result_queue_url))
    error_message = "game_result_queue_url must be an SQS queue URL."
  }
}
variable "fleet_role_arn" {
  type        = string
  description = "Role ARN baked into the server's config.ini as ROLE_ARN, which the server assumes to send results"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.fleet_role_arn))
    error_message = "fleet_role_arn must be an IAM role ARN."
  }
}
variable "rest_api_id" {
  type        = string
  description = "ID of the REST API, patched into the leaderboard's main.js and used to build MATCH_SERVER_API in both client configs. The id alone, not the stage's invoke URL: the stage waits on the functions, the functions wait on this instance, and the id is the one piece that exists before either"

  validation {
    condition     = can(regex("^[a-z0-9]{10}$", var.rest_api_id))
    error_message = "rest_api_id must be a 10-character API Gateway REST API id."
  }
}
variable "api_stage_name" {
  type        = string
  default     = "prod"
  description = "Stage name in the URLs the setup writes. Must match the API's stage"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.api_stage_name))
    error_message = "api_stage_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "game_client_player_names" {
  type        = list(string)
  default     = ["Amazonian", "Ahro"]
  description = "PLAYER_NAME for Client_player1 and Client_player2, as the _monolithic template had them. Each becomes a player record the first time that client requests a match"

  validation {
    condition     = length(var.game_client_player_names) == 2 && alltrue([for n in var.game_client_player_names : can(regex("^[A-Za-z0-9_-]{1,64}$", n))])
    error_message = "game_client_player_names must contain exactly two names (one per client folder) of letters, digits, hyphens and underscores."
  }
}
variable "game_client_player_password" {
  type        = string
  default     = "simplepw00"
  description = "PLAYER_PASSWD for both clients, as the _monolithic template had it. A game login, not an AWS credential, and not secret in any sense: MatchRequest.py stores it in the player table in plaintext and the client reads it from a plaintext config.ini"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,64}$", var.game_client_player_password))
    error_message = "game_client_player_password must be 1-64 letters, digits, hyphens and underscores."
  }
}
