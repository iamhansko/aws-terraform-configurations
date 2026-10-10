variable "build_bucket_name" {
  type        = string
  description = "Bucket the instance uploads server.zip to, read by the build alone. The root passes it through a waiter that has seen server.zip, which is what holds CreateBuild until the upload; the build role's grant takes build_bucket_arn instead, so it is not held with it"

  validation {
    condition     = length(var.build_bucket_name) >= 3 && length(var.build_bucket_name) <= 63
    error_message = "build_bucket_name must be a bucket name of 3-63 characters."
  }
}
variable "build_bucket_arn" {
  type        = string
  description = "ARN of the same bucket, for the build role's read grant. Taken alongside the name rather than rebuilt from it, so the grant cannot point at a different bucket from the one the build reads (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.build_bucket_arn))
    error_message = "build_bucket_arn must be an S3 bucket ARN."
  }
}
variable "build_object_key" {
  type        = string
  default     = "server.zip"
  description = "Key of the server build in the bucket. The userdata uploads to the same key, both reading the root's server_build_s3_key"

  validation {
    condition     = endswith(var.build_object_key, ".zip") && !startswith(var.build_object_key, "/")
    error_message = "build_object_key must be a .zip object key without a leading slash - GameLift only accepts a zip archive as a build from S3."
  }
}
variable "build_role_name_prefix" {
  type        = string
  default     = "gamelift-flexmatch-build-"
  description = "Prefix for the generated name of the role GameLift assumes to copy the build"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.build_role_name_prefix))
    error_message = "build_role_name_prefix must be 1-38 characters of letters, digits and +=,.@_-."
  }
}
variable "build_name" {
  type        = string
  default     = "GomokuServer-Build-1"
  description = "Name of the build, as the _monolithic template had it. GameLift names are labels, not identifiers - two builds may share one"

  validation {
    condition     = length(var.build_name) > 0 && length(var.build_name) <= 1024
    error_message = "build_name must be 1-1024 characters."
  }
}
variable "operating_system" {
  type        = string
  default     = "WINDOWS_2016"
  description = <<-DESC
    Operating system the build runs on, as the _monolithic template had it. Still accepted by the
    provider and the CreateBuild API, but on a clock: the GameLift API reference states that Windows
    Server 2016 reaches end of support on 2027-01-12, and that a server SDK 4.x build has to move to
    server SDK 5.x before it can run on WINDOWS_2022. GomokuServer.exe is a prebuilt binary linked
    against the older aws-cpp-sdk-gamelift-server, so switching this value alone is not an upgrade -
    the server has to be rebuilt first.
  DESC

  validation {
    condition     = contains(["WINDOWS_2012", "WINDOWS_2016", "WINDOWS_2022"], var.operating_system)
    error_message = "operating_system must be one of the Windows values CreateBuild accepts (WINDOWS_2012, WINDOWS_2016, WINDOWS_2022), because GomokuServer.exe is a Windows executable. WINDOWS_2022 needs the server rebuilt against server SDK 5.x first."
  }
}
variable "fleet_name" {
  type        = string
  default     = "GomokuGameServerFleet-1"
  description = "Name of the fleet, as the _monolithic template had it"

  validation {
    condition     = length(var.fleet_name) > 0 && length(var.fleet_name) <= 1024
    error_message = "fleet_name must be 1-1024 characters."
  }
}
variable "ec2_instance_type" {
  type        = string
  default     = "c5.large"
  description = "Instance type of the fleet, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.ec2_instance_type))
    error_message = "ec2_instance_type must be an EC2 instance type such as c5.large."
  }
}
variable "fleet_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "ON_DEMAND, where the _monolithic template had SPOT. The queue below has this fleet as its only destination, and GameLift drains a Spot fleet whose instance type and location it judges non-viable, so with SPOT the fleet can stay ACTIVE with no instance to place a match on - see the comment on the fleet resource"

  validation {
    condition     = var.fleet_type == "ON_DEMAND"
    error_message = "fleet_type must be ON_DEMAND in this module. Its game session queue has this one fleet as its only destination, and GameLift drains a Spot fleet it judges non-viable - the fleet stays ACTIVE with no instance, matches time out in the queue and nothing fails in Terraform. To use SPOT, give the queue an ON_DEMAND fleet as a second destination for backup capacity."
  }
}
variable "instance_role_arn" {
  type        = string
  description = "Role the fleet's instances are given, which the game server assumes to send results to SQS"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.instance_role_arn))
    error_message = "instance_role_arn must be an IAM role ARN."
  }
}
variable "ec2_inbound_permissions" {
  type = list(object({
    from_port = number
    to_port   = number
    ip_range  = string
    protocol  = string
  }))
  default = [{
    from_port = 49152
    to_port   = 60000
    ip_range  = "0.0.0.0/0"
    protocol  = "TCP"
  }]
  description = "Ports the fleet's instances accept game client connections on, as the _monolithic template had them: TCP 49152-60000 from anywhere, because the game clients connect from wherever the players are. 1026-60000 is the whole range the GameLift API accepts for a Windows fleet"

  validation {
    condition = alltrue([for p in var.ec2_inbound_permissions :
      p.from_port >= 1026 && p.from_port <= p.to_port && p.to_port <= 60000 &&
      contains(["TCP", "UDP"], p.protocol) && can(cidrhost(p.ip_range, 0))
    ])
    error_message = "ec2_inbound_permissions entries must have 1026 <= from_port <= to_port <= 60000 (the range GameLift accepts for a Windows fleet), protocol TCP or UDP, and a valid CIDR ip_range."
  }
}
variable "server_launch_path" {
  type        = string
  default     = "C:\\game\\Binaries\\Win64\\GomokuServer.exe"
  description = "Executable GameLift launches, as the _monolithic template had it. C:\\game is where GameLift unpacks a Windows build; the rest is the layout of the GomokuServer folder the userdata zips"

  validation {
    condition     = startswith(var.server_launch_path, "C:\\game\\")
    error_message = "server_launch_path must be under C:\\game\\, where GameLift installs a Windows build."
  }
}
variable "server_process_concurrent_executions" {
  type        = number
  default     = 50
  description = "Server processes per instance, as the _monolithic template had it"

  validation {
    condition     = var.server_process_concurrent_executions >= 1 && var.server_process_concurrent_executions <= 50
    error_message = "server_process_concurrent_executions must be between 1 and 50, GameLift's per-instance limit."
  }
}
variable "game_session_activation_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long a new game session may take to activate, as the _monolithic template had it"

  validation {
    condition     = var.game_session_activation_timeout_seconds >= 1 && var.game_session_activation_timeout_seconds <= 600
    error_message = "game_session_activation_timeout_seconds must be between 1 and 600."
  }
}
variable "max_concurrent_game_session_activations" {
  type        = number
  default     = 2147483647
  description = "Game sessions an instance may activate at once, as the _monolithic template had it - the API's maximum, which means no limit"

  validation {
    condition     = var.max_concurrent_game_session_activations >= 1 && var.max_concurrent_game_session_activations <= 2147483647
    error_message = "max_concurrent_game_session_activations must be between 1 and 2147483647."
  }
}
variable "alias_name" {
  type        = string
  default     = "GomokuAlias"
  description = "Name of the alias, as the _monolithic template had it"

  validation {
    condition     = length(var.alias_name) > 0 && length(var.alias_name) <= 1024
    error_message = "alias_name must be 1-1024 characters."
  }
}
variable "alias_description" {
  type        = string
  default     = "Routes the game session queue to the Gomoku game server fleet"
  description = "Description of the alias. Not optional in practice: UpdateAlias rejects an empty one, and the alias is updated whenever the fleet is replaced"

  validation {
    condition     = length(var.alias_description) > 0 && length(var.alias_description) <= 1024
    error_message = "alias_description must be 1-1024 characters - UpdateAlias rejects an empty description, so an alias without one cannot be moved to a replacement fleet."
  }
}
variable "queue_name" {
  type        = string
  default     = "gomoku-queue"
  description = "Name of the game session queue, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,128}$", var.queue_name))
    error_message = "queue_name must be 1-128 characters of letters, digits and hyphens."
  }
}
variable "queue_timeout_in_seconds" {
  type        = number
  default     = 600
  description = "How long a placement request may wait in the queue, as the _monolithic template had it"

  validation {
    condition     = var.queue_timeout_in_seconds >= 1 && var.queue_timeout_in_seconds <= 43200
    error_message = "queue_timeout_in_seconds must be between 1 and 43200."
  }
}
