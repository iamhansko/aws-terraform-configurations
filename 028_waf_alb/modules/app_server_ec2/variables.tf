variable "vpc_id" {
  type        = string
  description = "VPC the security group is created in. Taken as an id so this module does not need to know how the caller found it (rules.md B-6)"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_id" {
  type        = string
  description = "Subnet the instance is launched in. It has to be one of the subnets the load balancer was given, or at least reachable from them, and it has to have a route to the internet - the userdata installs the interpreter and Flask over it"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. An id rather than an SSM parameter path, so this module does not need to know that the caller reads it from a public parameter (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). An unresolved SSM parameter path passed here fails the plan rather than launching an instance from nothing."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. Nothing in this project uses it on this host - the security group opens no SSH port and Session Manager is the way in - but it is attached so that an instance whose bootstrap failed before the SSM agent registered can still be reached by temporarily opening 22"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "instance_name" {
  type        = string
  default     = "app-server"
  description = "Name tag of the instance, as the _monolithic template tagged it. Unlike the other instance's tag this one is accurate, which is why the module keeps the name"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Instance type, as the _monolithic template had it. The workload is one Flask development server against a SQLite file, so this is generous already"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}
variable "app_port" {
  type        = number
  default     = 5000
  description = "Port the Flask app binds and the security group admits, as the _monolithic template had it. The same number has to be the load balancer's target port, so the caller passes one value into both modules and this one hands it back out (rules.md B-5) - a mismatch is accepted by both APIs and then shows up only as a target that never passes a health check"

  validation {
    condition     = var.app_port > 1024 && var.app_port <= 65535
    error_message = "app_port must be between 1025 and 65535. The unit runs as ec2-user, which cannot bind a privileged port - systemd would report the service failing to start with Permission denied."
  }
}
variable "app_directory" {
  type        = string
  default     = "/home/ec2-user"
  description = "Directory main.py, utils/ and the SQLite database live in, as the _monolithic template had it. It is also the unit's WorkingDirectory, and main.py's import of utils.query_builder depends on utils/ being a subdirectory of wherever main.py is"

  validation {
    condition     = can(regex("^/[^ ]*[^/ ]$", var.app_directory))
    error_message = "app_directory must be an absolute path with no spaces and no trailing slash - it is interpolated into shell redirections, a chown and a systemd unit."
  }
}
variable "security_group_name" {
  type        = string
  default     = null
  description = "Exact name for the security group. Null generates one from security_group_name_prefix, which is the default. The _monolithic template left this group unnamed, so EC2 generated a name for it"

  validation {
    condition     = var.security_group_name == null || (can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-"))
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs (rules.md F-1)."
  }
}
variable "security_group_name_prefix" {
  type        = string
  default     = "app-server-sg-"
  description = "Prefix for the generated security group name, used when security_group_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,100}$", var.security_group_name_prefix))
    error_message = "security_group_name_prefix must be 1-100 characters from the set AWS accepts for a security group name, leaving room for the generated suffix."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the Flask app server behind the WAF-protected ALB"
  description = "Description attached to the security group. The _monolithic template said only \"Security Group\". Changing it replaces the group, which replaces the instance's network interface attachment and deregisters it from the target group - AWS has no API to modify a security group description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Security groups allowed to reach app_port, keyed by a label the caller chooses. The load balancer's
    frontend group goes here, and it is what carries both the forwarded requests and the health checks.

    A map rather than a list because these ids are another module's output and so are unknown until apply,
    while for_each keys have to be known at plan time (rules.md B-8). An empty map leaves the load balancer
    unable to reach the target, which reads as every target unhealthy with reason Target.Timeout.
  DESC

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels used in rule descriptions and resource addresses, so each must be a non-empty string of letters, digits, dots, underscores or hyphens. The description also has to stay inside the character set EC2 accepts, which excludes apostrophes (rules.md F-1)."
  }
  validation {
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Sources allowed to reach app_port directly, bypassing the load balancer. Empty by default, and that is a
    deliberate departure from the _monolithic template, which opened this port to 0.0.0.0/0.

    A web ACL associated with a load balancer filters what arrives through that load balancer and nothing
    else. With this port open to the world, the 403 this project exists to produce can be stepped around
    with one curl straight at the instance - and the application behind it concatenates query parameters
    into SQL, so the bypass is not academic. The same argument is made for the website endpoint in
    097_cloudfront_s3_static_website.

    Setting it back to ["0.0.0.0/0"] restores the original's behaviour and turns the bypass into part of the
    demo: the root publishes a direct URL for exactly that comparison, and the point lands harder when the
    unfiltered path is shown to work rather than described.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  description = <<-DESC
    Managed policy ARNs attached to this instance's role.

    SSM access only. The _monolithic template gave this instance no role at all, which is why this is a
    departure rather than a narrowing: there was nothing to narrow. The template also opened no SSH port on
    this host, so an instance whose Flask process failed to start could not be reached by any route and a
    503 had no explanation available.

    Narrow rather than broad because this is an automated host, not a workbench - rules.md A-5 applies here
    in the direction it normally does, where it does not for the code-server instance. Nothing in the
    userdata or the application calls AWS, so Session Manager is the only thing these permissions buy.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. An empty list leaves the SSM agent unable to register the instance, which makes aws ssm start-session report the instance as not connected and removes the only way onto this host."
  }
}
variable "python_command" {
  type        = string
  default     = "python3.13"
  description = <<-DESC
    Interpreter used to install Flask and to run the app, named explicitly rather than reached through a
    symlink.

    The _monolithic template installed python3.13 and then created /usr/bin/python pointing at it. That link
    does get created on Amazon Linux 2023, where /usr/bin/python does not exist - so unlike the same trick
    against /usr/bin/python3 it did not fail. It is still the wrong move, because dnf is a Python program
    bound to the system interpreter and a repointed python breaks any later dnf call on the host.

    The value is interpolated into a shell command line and into the unit's ExecStart as
    /usr/bin/<value>, which is why the validation is narrow.
  DESC

  validation {
    condition     = can(regex("^python3(\\.[0-9]+)?$", var.python_command))
    error_message = "python_command must be python3 or python3.<minor> (e.g. python3.13). It is interpolated into shell commands and into a systemd ExecStart line, so an arbitrary string here would be an injection point."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["python3.13"]
  description = "Packages installed with dnf. python3.13 is what the _monolithic template installed; pip comes from the interpreter's own ensurepip rather than from a package, which is also what the template relied on"

  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "dnf_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "dnf_groups" {
  type        = list(string)
  default     = ["Development Tools"]
  description = "Package groups installed with dnf groupinstall, as the _monolithic template installed them. An empty list skips the step: Flask and everything it depends on publish manylinux wheels, so nothing here compiles, and dropping the group takes several minutes off the boot - the group is kept by default only because that is what the original did"

  validation {
    condition     = alltrue([for group in var.dnf_groups : can(regex("^[a-zA-Z0-9 ._+-]+$", group))])
    error_message = "dnf_groups entries must be plain group names - they are quoted and interpolated into a dnf command line."
  }
}
variable "pip_packages" {
  type        = list(string)
  default     = ["flask"]
  description = "Python packages the app imports, as the _monolithic template installed them. flask brings werkzeug, jinja2, click, itsdangerous, markupsafe and blinker with it; sqlite3 is in the standard library"

  validation {
    condition     = length(var.pip_packages) > 0 && alltrue([for package in var.pip_packages : can(regex("^[a-zA-Z0-9._\\[\\]=<>!-]+$", package))])
    error_message = "pip_packages must be a non-empty list of plain requirement specifiers - they are interpolated into a pip command line. An empty list leaves the app unable to import flask, which systemd reports as the service restarting in a loop."
  }
}
variable "flask_debug" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the app runs with Flask's debug mode on. False, where the _monolithic template hardcoded True.

    Two reasons, and the first is the one that matters. Debug mode turns on the Werkzeug interactive
    debugger, which renders a traceback with an in-browser console on any unhandled exception - on a host
    whose only inbound path is a public load balancer and whose application evaluates query parameters as
    SQL. Modern Werkzeug gates the console behind a PIN printed to the server's log, so this is a narrowed
    hazard rather than an open shell, but it is still a debugger reachable from the internet.

    The second is that debug mode starts the reloader, which re-executes the script - so init() runs again
    and drops and recreates the table, and the process tree has a parent and a child where the unit expects
    one process.

    True is still useful when the demo is being developed: an unhandled exception then shows where it came
    from instead of a bare 500.
  DESC
}
variable "service_name" {
  type        = string
  default     = "flask-app"
  description = "Name of the systemd unit the app runs under. The _monolithic template started it with nohup and so had no unit name - see main.tf for why there is one now"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.@-]{1,64}$", var.service_name))
    error_message = "service_name must be 1-64 characters of letters, digits, dots, underscores, at signs and hyphens - it becomes a systemd unit file name and is interpolated into systemctl commands."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address, as the _monolithic template had it. In a default VPC this is what makes outbound internet work at all - there is an internet gateway and no NAT gateway, so without an address the userdata's dnf and pip calls time out and the end state is the same as a revoked egress rule. It does not make the instance reachable: the security group admits the load balancer's group and, by default, nothing else"
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. The _monolithic template set none, which means the AMI's own 8GiB; 30 is the free-tier allowance and leaves room for the Development Tools group and a pip cache"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the Amazon Linux 2023 root image."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is enforced. required, where the _monolithic template left the provider default of optional. Nothing on this host reads the metadata service over IMDSv1 - the SSM agent and the SDKs handle the token themselves and the app makes no AWS calls - and the application here evaluates attacker-supplied strings as SQL, which is as close to a server-side request forgery surface as a demo gets"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional (IMDSv1 allowed)."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra shell appended after the app and its unit are in place. Null adds nothing (rules.md B-4)"

  validation {
    # Null rather than "" is how to add nothing, which is what the template directive in main.tf tests. An
    # empty string renders a blank line and reads, in a plan, like a value someone meant to set.
    condition     = var.additional_user_data == null || length(trimspace(var.additional_user_data)) > 0
    error_message = "additional_user_data must be a non-empty script, or null to add nothing."
  }
}
