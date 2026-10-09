variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region, as the conversion had it. Null falls through to the provider chain (AWS_REGION or the shared config), which is how every other root in this repository is run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "common-rule-set"
  description = "Name used as the heading of the README written onto the workbench and as the prefix for generated names. The conversion called this stack_name, standing in for AWS::StackName; nothing here builds a CloudFormation ARN out of it any more (see providers.tf)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be 2-31 characters of lowercase letters, digits and hyphens, starting with a letter or digit - it becomes part of a key pair name prefix."
  }
}
variable "al2023_ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "Public SSM parameter holding the latest Amazon Linux 2023 AMI id, as the conversion had it. Both instances launch from whatever this resolves to, so two applies weeks apart can produce instances from different images - pinning an ami id here is how to stop that"

  validation {
    condition     = can(regex("^/[^ ]+$", var.al2023_ami_ssm_parameter_name))
    error_message = "al2023_ami_ssm_parameter_name must be an absolute SSM parameter path."
  }
}
variable "vpc_id" {
  type        = string
  default     = null
  description = <<-DESC
    VPC everything is placed in. Null discovers the account's default VPC, which is the default.

    The _monolithic template declared DefaultVpcId, DefaultVpcPublicSubnet1Id and DefaultVpcPublicSubnet2Id
    as stack parameters with no defaults, so whoever ran it had to look three ids up and paste them in. This
    project has no network module and creates no VPC of its own - that is deliberate, since a VPC is not
    what it is demonstrating - so the root resolves the default VPC instead and hands the ids to the modules
    (rules.md B-6). Setting this is how to point the whole thing at a VPC of your own.

    Both this and public_subnet_ids have to be set together; see the validation on public_subnet_ids.
  DESC

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0), or null to use the account's default VPC."
  }
}
variable "public_subnet_ids" {
  type        = list(string)
  default     = null
  description = <<-DESC
    Public subnets the load balancer and the instances go in. Null discovers the default subnets of
    whichever VPC is in use - one per availability zone - which is the default.

    They have to be public in the sense of having a route to an internet gateway, both because the load
    balancer is internet-facing and because the instances install packages over it. A default VPC's subnets
    are public in that sense: the main route table carries a default route to the gateway and every default
    subnet sets map_public_ip_on_launch.
  DESC

  validation {
    condition     = var.public_subnet_ids == null || alltrue([for subnet in coalesce(var.public_subnet_ids, []) : can(regex("^subnet-[0-9a-f]+$", subnet))])
    error_message = "public_subnet_ids must contain valid subnet IDs (e.g. subnet-0123456789abcdef0), or be null to discover the default subnets."
  }
  validation {
    condition     = var.public_subnet_ids == null || length(coalesce(var.public_subnet_ids, [])) >= 2
    error_message = "public_subnet_ids must contain at least two subnets in different availability zones, which is what an application load balancer requires."
  }
  validation {
    # A caller-supplied VPC with discovered subnets, or the reverse, is almost certainly a mistake: the
    # discovery filters on whichever VPC is in use, so one of the two would be describing a different
    # network. The failure mode is a load balancer create that is refused because its subnets are not in the
    # VPC its target group names - during apply, with the VPC ids in the message but not the reason. This is
    # a constraint about the pair rather than about either value, which is what a cross-variable validation
    # is for (rules.md B-1).
    condition     = (var.vpc_id == null) == (var.public_subnet_ids == null)
    error_message = "vpc_id and public_subnet_ids must be set together, or both left null to discover the account's default VPC and its default subnets. Setting one and discovering the other mixes two networks, which fails during apply rather than at plan time."
  }
}
variable "app_port" {
  type        = number
  default     = 5000
  description = "The port the Flask app binds, the port its security group admits, the target group's port and the port the registration uses - one value, passed into both modules and into the registration in main.tf, because four places that could disagree is four places where a health check fails for no visible reason (rules.md B-5). 5000 is what the _monolithic template used, Flask's development server default"

  validation {
    condition     = var.app_port > 1024 && var.app_port <= 65535
    error_message = "app_port must be between 1025 and 65535. The app runs as ec2-user, which cannot bind a privileged port."
  }
}
variable "listener_port" {
  type        = number
  default     = 80
  description = "Port the load balancer's HTTP listener binds and its security group opens, as the _monolithic template had it. Also what the demo's URLs are built from"

  validation {
    condition     = var.listener_port > 0 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}
variable "health_check_path" {
  type        = string
  default     = "/"
  description = <<-DESC
    Path the target group's health check requests. "/" as the _monolithic template had it, which is the route
    the Flask app serves its form on.

    This is a root variable rather than a value taken from the app server module, and that is not an
    oversight. The load balancer module's security group is the app server module's ingress source, so a
    reference back the other way would close a cycle between the two modules and Terraform would refuse to
    plan. The app server module exposes its index route as an output so the two can be compared by eye - see
    main.tf.
  DESC

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with a slash."
  }
}
variable "load_balancer_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach the listener. 0.0.0.0/0, as the _monolithic template had it, and appropriate here rather than merely inherited: the project is about a web ACL filtering an internet-facing endpoint, and narrowing this would make the web ACL the second line of defence in a demo about the first"

  validation {
    condition     = length(var.load_balancer_ingress_cidr_blocks) > 0 && alltrue([for cidr in var.load_balancer_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "load_balancer_ingress_cidr_blocks must be a non-empty list of valid IPv4 CIDR blocks. An empty list leaves the listener unreachable and every demo request times out."
  }
}
variable "web_acl_name" {
  type        = string
  default     = "waf"
  description = "Name of the web ACL, as the _monolithic template named it. Also the WebACL dimension on its CloudWatch metrics, which is why the metric commands in the outputs are built from it"

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,128}$", var.web_acl_name))
    error_message = "web_acl_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "web_acl_metric_name" {
  type        = string
  default     = "waf"
  description = "CloudWatch metric name for the web ACL as a whole, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]{1,128}$", var.web_acl_metric_name))
    error_message = "web_acl_metric_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "web_acl_default_action" {
  type        = string
  default     = "allow"
  description = "What happens to a request no rule matched. allow, as the _monolithic template had it - and the value the whole demo rests on, since the comparison it draws is between an allowed request and a blocked one through the same endpoint. The module's variables.tf explains what block would do instead"

  validation {
    condition     = contains(["allow", "block"], var.web_acl_default_action)
    error_message = "web_acl_default_action must be allow or block."
  }
}
variable "managed_rule_groups" {
  type = map(object({
    priority                   = number
    vendor_name                = optional(string, "AWS")
    version                    = optional(string)
    metric_name                = string
    override_action            = optional(string, "none")
    rule_action_overrides      = optional(map(string), {})
    sampled_requests_enabled   = optional(bool, true)
    cloudwatch_metrics_enabled = optional(bool, true)
  }))
  default = {
    AWSManagedRulesSQLiRuleSet = {
      priority    = 1
      metric_name = "sqli-rule"
    }
    AWSManagedRulesCommonRuleSet = {
      priority    = 2
      metric_name = "base-rule"
    }
  }
  description = <<-DESC
    The AWS managed rule groups the web ACL runs, keyed by rule group name. These two, at these priorities,
    with these metric names, are exactly what the _monolithic template declared - they are the content of
    this project.

    Promoted to the root rather than left at the module default because they are the thing someone running
    this project will want to change: adding a group, moving a priority, or setting one rule inside a group
    to count. modules/web_application_firewall/variables.tf carries the full explanation of every field and
    the complete set of validations; the two below are repeated here only so that the most common copy-paste
    mistakes fail before the module is even reached.
  DESC

  validation {
    condition     = length(var.managed_rule_groups) > 0
    error_message = "managed_rule_groups must contain at least one rule group. An empty map produces a web ACL that filters nothing and reports no error."
  }
  validation {
    condition     = length(distinct([for group in values(var.managed_rule_groups) : group.priority])) == length(var.managed_rule_groups)
    error_message = "managed_rule_groups priorities must be unique. WAF refuses a web ACL with two rules at the same priority, during apply rather than at plan time."
  }
}
variable "app_server_instance_name" {
  type        = string
  default     = "app-server"
  description = "Name tag of the instance running the Flask app, as the _monolithic template tagged it"

  validation {
    condition     = length(var.app_server_instance_name) > 0
    error_message = "app_server_instance_name must not be empty."
  }
}
variable "app_server_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the app server, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.app_server_instance_type))
    error_message = "app_server_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "app_server_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Sources allowed to reach the app server's port directly, going around the load balancer and therefore
    around the web ACL. Empty, which is a deliberate departure from the _monolithic template's 0.0.0.0/0.

    A web ACL associated with a load balancer filters requests arriving through that load balancer and
    nothing else. With this open, the 403 this project exists to produce is one curl away from being
    stepped around - against an application that concatenates query parameters into SQL.

    Setting it to ["0.0.0.0/0"] restores the original and turns the bypass into part of the demo: the
    outputs publish a direct request command for exactly that comparison, which with this empty times out
    instead.
  DESC

  validation {
    condition     = alltrue([for cidr in var.app_server_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "app_server_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "flask_debug" {
  type        = bool
  default     = false
  description = "Whether the Flask app runs in debug mode. False, where the _monolithic template hardcoded True - which puts the Werkzeug interactive debugger behind a public load balancer and starts the reloader. The module's variables.tf sets out both consequences"
}
variable "vscode_instance_name" {
  type        = string
  default     = "bastion"
  description = "Name tag of the code-server instance, as the _monolithic template tagged it. The tag is kept for continuity even though the module is called vscode_ec2 - nothing bastions through this host, and modules/vscode_ec2/main.tf shows how the two userdata scripts settle that"

  validation {
    condition     = length(var.vscode_instance_name) > 0
    error_message = "vscode_instance_name must not be empty."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type for the code-server workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds and its security group opens, as the _monolithic template had it"

  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part version (e.g. 4.100.3)."
  }
}
variable "vscode_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Sources allowed to reach code-server and SSH on the workbench. 0.0.0.0/0, as the _monolithic template had it, and the one default in this project most worth narrowing: code-server here runs with authentication disabled on a host whose instance role is AdministratorAccess"

  validation {
    condition     = alltrue([for cidr in var.vscode_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "vscode_ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "vscode_associate_elastic_ip" {
  type        = bool
  default     = false
  description = "Whether the workbench gets an Elastic IP. False, as the _monolithic template had it. True is right if the instance will be stopped and started, because the code-server URL is written into a README on its own disk as well as into terraform output, and an auto-assigned address does not survive a stop (rules.md H-2)"
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory the workbench's bootstrap writes its completion marker into, and that the README association waits on. Under /run so it is tmpfs and disappears on reboot, which is correct - the marker means \"this boot's userdata finished\", and userdata only runs on the first boot (rules.md D-5)"

  validation {
    condition     = can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = <<-DESC
    How long Terraform waits for the README association to report success.

    It has to cover the whole of the workbench's bootstrap, because the association's command begins by
    waiting for that bootstrap's marker file - dnf update, the Development Tools group and the code-server
    download all happen before the marker appears. Too short and the apply fails with "unexpected state
    'Failed'" on a host where nothing is actually wrong, and the diagnosis takes three CLI calls
    (rules.md A-4 sets them out).
  DESC

  validation {
    condition     = var.readme_timeout_seconds >= 300 && var.readme_timeout_seconds <= 7200
    error_message = "readme_timeout_seconds must be between 300 and 7200. Below about 600 the association regularly times out while dnf groupinstall is still running, which looks like a failure but is not one."
  }
}
variable "demo_allowed_value" {
  type        = string
  default     = "1"
  description = "The benign value sent to the app's lookup route, which should come back 200. It is a row id that exists in the app's table, so the response is a real answer rather than an empty list - which matters when the point being made is that the endpoint works for ordinary requests"

  validation {
    condition     = can(regex("^[A-Za-z0-9 ._=/,:-]+$", var.demo_allowed_value))
    error_message = "demo_allowed_value must consist of letters, digits, spaces and . _ = / , : - only. It is interpolated into a shell command published as an output, and a double quote, backslash, backtick or dollar sign there would change what that command runs."
  }
}
variable "demo_sqli_payload" {
  type        = string
  default     = "1' OR '1'='1"
  description = <<-DESC
    The SQL injection probe sent to the app's lookup route, which AWSManagedRulesSQLiRuleSet should answer
    with a 403.

    It is a real injection rather than a string that happens to match a pattern: the app concatenates this
    parameter into "SELECT id, name, secret FROM secret_users WHERE id = ..." with no quoting, so with the
    web ACL overridden to count the same request returns every row in the table.

    Single quotes are part of the payload, which is why the generated command wraps it in double quotes -
    and why the validation refuses a double quote, a backslash, a backtick or a dollar sign.
  DESC

  validation {
    condition     = length(var.demo_sqli_payload) > 0 && !can(regex("[\"\\\\`$]", var.demo_sqli_payload))
    error_message = "demo_sqli_payload must be non-empty and must not contain a double quote, backslash, backtick or dollar sign. It is interpolated into a double-quoted argument of a shell command published as an output, where any of those four would end the quoting or be expanded by the shell."
  }
}
variable "demo_path_traversal_payload" {
  type        = string
  default     = "../../../../etc/passwd"
  description = <<-DESC
    The path traversal probe, which AWSManagedRulesCommonRuleSet should answer with a 403 - its
    GenericLFI_QUERYARGUMENTS rule is the one that looks for this shape in a query argument.

    Included because it exercises the second rule group. With only the SQLi probe, a demo in which
    AWSManagedRulesCommonRuleSet was never installed would look identical.

    curl percent-encodes this before sending it; the managed rule applies a URL-decode transformation
    before matching, so it still matches. A 200 here is worth checking against the sampled requests rather
    than assumed to mean the rule group is absent.
  DESC

  validation {
    condition     = length(var.demo_path_traversal_payload) > 0 && !can(regex("[\"\\\\`$]", var.demo_path_traversal_payload))
    error_message = "demo_path_traversal_payload must be non-empty and must not contain a double quote, backslash, backtick or dollar sign, for the same reason as demo_sqli_payload - it is interpolated into a double-quoted shell argument."
  }
}
