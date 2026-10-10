# --- Build ----------------------------------------------------------------------------------------------------
variable "build_name" {
  type        = string
  default     = "GomokuServer-Build-1"
  description = "Name of the GameLift build, as the _monolithic template had it. Build names need not be unique"

  validation {
    condition     = length(var.build_name) > 0 && length(var.build_name) <= 1024
    error_message = "build_name must be 1-1024 characters."
  }
}
variable "build_operating_system" {
  type        = string
  default     = "WINDOWS_2016"
  description = "Operating system the server binaries run on. WINDOWS_2016 as the _monolithic template had it, and the only Windows value this server can use: GameLift retires Windows Server 2016 on 2027-01-12, an account with no active WINDOWS_2016 fleet can no longer create one from 2026-12-12, and WINDOWS_2022 requires server SDK 5 while this server is built against SDK 4"

  validation {
    condition     = contains(["WINDOWS_2016", "WINDOWS_2022"], var.build_operating_system)
    error_message = "build_operating_system must be WINDOWS_2016 or WINDOWS_2022 - the server is a Windows executable, and WINDOWS_2012 is retired. WINDOWS_2022 also needs a server rebuilt against GameLift server SDK 5, which the prebuilt GomokuServer.exe is not."
  }
}
variable "build_role_name_prefix" {
  type        = string
  description = "Prefix for the name of the role GameLift assumes to read the build from S3"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.build_role_name_prefix)) && length(var.build_role_name_prefix) <= 38
    error_message = "build_role_name_prefix must be 1-38 characters from the set IAM accepts for a role name."
  }
}
variable "source_bucket_name" {
  type        = string
  description = "Bucket holding the server build, used by the build alone. The root passes it through a waiter that has seen server.zip, which is what holds CreateBuild until the upload; the build role's grant takes source_bucket_arn instead, so it is not held with it"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+$", var.source_bucket_name)) && length(var.source_bucket_name) <= 63
    error_message = "source_bucket_name must be a valid S3 bucket name."
  }
}
variable "source_bucket_arn" {
  type        = string
  description = "ARN of that bucket, for the build role's read grant. Taken alongside the name rather than rebuilt from it (rules.md A-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]+$", var.source_bucket_arn))
    error_message = "source_bucket_arn must be an S3 bucket ARN."
  }
}
variable "server_build_s3_key" {
  type        = string
  description = "Object key of the zipped server build. GameLift reads it the moment the build is created and refuses a missing key with \"Provided resource is not accessible\", which the provider does not retry - so the root holds the build through source_bucket_name"

  validation {
    condition     = length(var.server_build_s3_key) > 0 && endswith(var.server_build_s3_key, ".zip") && !startswith(var.server_build_s3_key, "/")
    error_message = "server_build_s3_key must be a .zip object key without a leading slash - GameLift accepts a build only as a zip."
  }
}
# --- Fleet ----------------------------------------------------------------------------------------------------
variable "fleet_name" {
  type        = string
  default     = "GomokuGameServerFleet-1"
  description = "Name of the fleet, as the _monolithic template had it. Fleet names need not be unique"

  validation {
    condition     = length(var.fleet_name) > 0 && length(var.fleet_name) <= 1024
    error_message = "fleet_name must be 1-1024 characters."
  }
}
variable "fleet_role_arn" {
  type        = string
  description = "Instance role ARN - the same role whose ARN the server reads from its config.ini and assumes"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.fleet_role_arn))
    error_message = "fleet_role_arn must be an IAM role ARN."
  }
}
variable "ec2_instance_type" {
  type        = string
  default     = "c5.large"
  description = "Instance type of the fleet, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", var.ec2_instance_type))
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
variable "inbound_from_port" {
  type        = number
  default     = 49152
  description = "Lowest port players connect to, as the _monolithic template opened it. The server picks its game port in this range"

  validation {
    condition     = var.inbound_from_port >= 1026 && var.inbound_from_port <= 60000
    error_message = "inbound_from_port must be between 1026 and 60000, the range GameLift accepts for EC2 inbound permissions."
  }
}
variable "inbound_to_port" {
  type        = number
  default     = 60000
  description = "Highest port players connect to, as the _monolithic template opened it"

  validation {
    condition     = var.inbound_to_port >= var.inbound_from_port && var.inbound_to_port <= 60000
    error_message = "inbound_to_port must be no lower than inbound_from_port and no higher than 60000."
  }
}
variable "inbound_ip_range" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Addresses players may connect from, as the _monolithic template had it. Open to the internet because the players are wherever the client runs"

  validation {
    condition     = can(cidrhost(var.inbound_ip_range, 0))
    error_message = "inbound_ip_range must be a valid IPv4 CIDR block."
  }
}
variable "inbound_protocol" {
  type        = string
  default     = "TCP"
  description = "Protocol players connect with. The Gomoku server is an IOCP TCP server"

  validation {
    condition     = contains(["TCP", "UDP"], var.inbound_protocol)
    error_message = "inbound_protocol must be TCP or UDP."
  }
}
variable "server_launch_path" {
  type        = string
  default     = "C:\\game\\Binaries\\Win64\\GomokuServer.exe"
  description = "Executable GameLift starts, as the _monolithic template had it. GameLift unpacks a Windows build under C:\\game, and server.zip is zipped from inside GomokuServer/, so its Binaries/Win64 lands there"

  validation {
    condition     = startswith(var.server_launch_path, "C:\\game\\")
    error_message = "server_launch_path must be under C:\\game\\, where GameLift installs a Windows build."
  }
}
variable "concurrent_executions" {
  type        = number
  default     = 50
  description = "Server processes per instance, as the _monolithic template had it"

  validation {
    condition     = var.concurrent_executions >= 1 && var.concurrent_executions <= 50
    error_message = "concurrent_executions must be between 1 and 50."
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
  description = "Game sessions an instance may activate at once. The _monolithic template's 2147483647 is the API maximum, i.e. no limit"

  validation {
    condition     = var.max_concurrent_game_session_activations >= 1 && var.max_concurrent_game_session_activations <= 2147483647
    error_message = "max_concurrent_game_session_activations must be between 1 and 2147483647."
  }
}
# --- Alias and queue ------------------------------------------------------------------------------------------
variable "alias_name" {
  type        = string
  default     = "GomokuAlias"
  description = "Name of the alias in front of the fleet, as the _monolithic template had it"

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
  description = "Name of the game session queue the matchmaker places matches through, as the _monolithic template had it. Unique per account and region"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.queue_name)) && length(var.queue_name) <= 128
    error_message = "queue_name must be 1-128 letters, digits and hyphens."
  }
}
variable "queue_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long a placement request may wait in the queue, as the _monolithic template had it"

  validation {
    condition     = var.queue_timeout_seconds >= 1 && var.queue_timeout_seconds <= 600
    error_message = "queue_timeout_seconds must be between 1 and 600."
  }
}
