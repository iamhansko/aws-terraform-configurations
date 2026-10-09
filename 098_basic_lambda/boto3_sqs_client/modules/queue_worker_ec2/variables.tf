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
  description = "Subnet the instance is launched in. The _monolithic template put it in the same public subnet as the workbench, which this reproduces - it needs outbound access for packages, the CloudWatch agent, and SQS, and there is no NAT gateway here to give it that from a private subnet"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0)."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. This is the only interactive way onto this host other than SSM Session Manager, and the SSH rule below admits only the workbench's security group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "instance_name" {
  type        = string
  default     = "queue-ec2"
  description = "Name tag of the instance, as the _monolithic template tagged it"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type, as the _monolithic template had it - larger than the workbench because this host is the one doing work. The worker opens a thread pool and deletes messages as fast as the queue hands them over, which is the only CPU-bound part of the project"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "security_group_name" {
  type        = string
  default     = "queue-ec2-sg"
  description = "Name of the security group, matching the Name tag the _monolithic template used"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the SQS worker instance, reachable over SSH from the workbench only"
  description = "Description attached to the security group. The _monolithic template said only \"Security Group\". Changing this replaces the group, because AWS has no API to modify a description (rules.md F-1)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "Port the SSH rules open. 22, which is what the _monolithic template opened on this group and what sshd actually listens on - the workbench's group is the one where the template opened 2222 instead and admitted nothing"

  validation {
    condition     = var.ssh_port > 0 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}
variable "ingress_source_security_groups" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Security groups allowed to SSH in, keyed by a label the caller chooses. Empty admits nobody, leaving SSM
    Session Manager as the only way on.

    A map rather than a list, and that is not a style choice. These IDs come from another module's output, so
    their values are unknown until apply - and toset(list) makes the value the for_each key, which Terraform
    has to know at plan time to build a resource address. The list form fails the plan with:

      Error: Invalid for_each argument
      The "for_each" set includes values derived from resource attributes that cannot be determined until
      apply, and so Terraform cannot determine the full set of keys

    A map's keys are literals in the root's configuration, so only the values are unknown, which is allowed
    (rules.md B-8). The label also lands in each rule's description, so a plan says which group each rule
    admits rather than showing an opaque sg- id.
  DESC

  validation {
    condition     = alltrue([for label in keys(var.ingress_source_security_groups) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "ingress_source_security_groups keys are labels that appear in rule descriptions and resource addresses, so each must be letters, digits, dots, underscores or hyphens - in particular not an apostrophe, which EC2 rejects in a rule description (rules.md F-1)."
  }
  validation {
    # Checked on keys above and values here, deliberately split: a value that is unknown until apply defers
    # this check to apply, while the key check runs at plan time (rules.md B-8).
    condition     = alltrue([for id in values(var.ingress_source_security_groups) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "ingress_source_security_groups values must be security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "Source CIDRs allowed to SSH in, on top of the security groups above. Empty, which is what the _monolithic template had for this host - it was reachable only from the workbench's group. A CIDR here opens this instance to an address range directly"

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = <<-DESC
    Managed policies attached to the instance role.

    A deliberate narrowing: the _monolithic template attached AdministratorAccess to this role. Keeping it
    would have been reproducing the original rather than converting it, so this is a change, and rules.md A-5
    requires saying why rather than only doing it.

    The reason is that this host is not a workbench. Nobody sits at it - there is no IDE and the only inbound
    rule admits the workbench's security group - and what runs on it is enumerable: the CloudWatch agent ships
    one log file, and the worker script receives and deletes messages on one queue. CloudWatchAgentServerPolicy
    covers the first, AmazonSSMManagedInstanceCore gives Session Manager a way in without a key, and the queue
    access is an inline policy below scoped to one ARN. rules.md A-5 excludes vscode_ec2 and bastion_ec2 from
    its audit because a human workbench is broad on purpose; that exclusion does not extend to an agent host.

    If a demo step needs something else from this host, add it here rather than reaching for the original
    policy - the failure will be a named AccessDenied for one API call, which is a better starting point than
    a role that can do anything.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. Dropping CloudWatchAgentServerPolicy leaves the agent unable to publish, which looks exactly like a worker that is not processing anything."
  }
}
variable "queue_url" {
  type        = string
  description = "URL of the queue the worker drains. Used to build the module's verification commands; the worker script itself is rendered by the caller and already carries it (rules.md B-6)"

  validation {
    condition     = can(regex("^https://sqs\\.[a-z0-9-]+\\.amazonaws\\.com(\\.cn)?/[0-9]{12}/[a-zA-Z0-9_.-]+$", var.queue_url))
    error_message = "queue_url must be an SQS queue URL (e.g. https://sqs.ap-northeast-2.amazonaws.com/123456789012/queue)."
  }
}
variable "queue_arn" {
  type        = string
  description = "ARN of the same queue, which the inline consume policy narrows itself to. Both forms are needed because an IAM Resource element takes an ARN while the SDK call takes a URL - and passing two different queues here is the kind of mistake the cross-check below exists to catch"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_.-]+$", var.queue_arn))
    error_message = "queue_arn must be an SQS queue ARN (e.g. arn:aws:sqs:ap-northeast-2:123456789012:queue)."
  }
  validation {
    # A cross-variable condition, available since Terraform 1.9 and the right shape here because the
    # constraint is about the pair rather than either value alone (rules.md B-1). Both values are unknown
    # until apply, so this is evaluated then - still before anything is created. Without it, a root that
    # wires the ARN of one queue and the URL of another produces a worker with permission on a queue it never
    # reads, and the only symptom is a message count that never drops.
    condition     = endswith(var.queue_url, "/${element(split(":", var.queue_arn), 5)}")
    error_message = "queue_arn and queue_url must refer to the same queue - the last element of the ARN must be the last path segment of the URL."
  }
}
variable "log_group_name" {
  type        = string
  default     = "queue-log-group"
  description = "Log group the CloudWatch agent ships the worker's log file to. Taken from the module that declares the group rather than restated, so the agent cannot be configured against a group nothing created (rules.md B-5) - an agent pointed at a non-existent group creates it itself, outside Terraform's state and with no retention"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters of letters, digits and the characters _ . / # - that CloudWatch Logs allows."
  }
}
variable "log_file_path" {
  type        = string
  default     = "/var/log/Gwangju_queue.log"
  description = "File the worker writes to and the agent tails, as the _monolithic template named it. It is created and chowned during the bootstrap because the worker runs as ec2-user and cannot create a file in /var/log itself - without that, logging silently discards every line and the metric filter never matches"

  validation {
    condition     = can(regex("^/[^ ]*$", var.log_file_path))
    error_message = "log_file_path must be an absolute path with no spaces - it is interpolated into shell commands and a JSON agent configuration."
  }
}
variable "worker_script" {
  type        = string
  default     = null
  description = "Body of the worker, rendered by the caller and written to worker_script_path on first boot. Null writes no script, which leaves an instance with a CloudWatch agent and nothing to log. Passed in rather than templated here because the caller is the only place that holds both the queue URL and the region (rules.md B-6)"

  validation {
    condition     = var.worker_script == null || length(var.worker_script) > 0
    error_message = "worker_script must be a non-empty script, or null to write none. An empty string produces an empty file and a systemd unit that exits successfully having done nothing."
  }
  validation {
    # The body goes into a quoted heredoc terminated by TFWORKER. A line equal to that word would close the
    # heredoc early and the rest of the Python would be handed to the shell - no plan error, no apply error,
    # just a bootstrap that did something other than what it says.
    condition     = var.worker_script == null || !can(regex("(?m)^TFWORKER\\s*$", var.worker_script))
    error_message = "worker_script must not contain a line consisting of TFWORKER, which is the heredoc terminator the user data writes it with - such a line would close the heredoc early and the remainder would be run as shell commands."
  }
}
variable "worker_script_path" {
  type        = string
  default     = "/home/ec2-user/worker.py"
  description = "Absolute path the worker is written to. Re-exposed as an output so the systemd unit, the run command and the root all read one value (rules.md B-5)"

  validation {
    condition     = can(regex("^/[^ ]*$", var.worker_script_path))
    error_message = "worker_script_path must be an absolute path with no spaces - it is interpolated into shell redirections and a systemd ExecStart line."
  }
}
variable "worker_service_name" {
  type        = string
  default     = "queue-worker"
  description = "Name of the systemd unit that runs the worker. The _monolithic template had no unit at all - it left the run commented out in the user data, so the worker was something a person started by hand in an SSH session and which died with that session"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.worker_service_name))
    error_message = "worker_service_name must be letters, digits, dots, underscores or hyphens - it becomes a systemd unit file name."
  }
}
variable "start_worker" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the worker starts at boot. False reproduces the _monolithic template, where the run line was
    commented out: the queue fills up when the generator runs and nothing drains it until a person says so,
    which is what makes the message count visible as a number that climbs.

    The unit file is written either way, so false still leaves "sudo systemctl start <worker_service_name>" as
    a one-line step instead of a backgrounded python process in an SSH session that dies with it. True is for
    an unattended run where the interesting measurement is the metric rather than the backlog.
  DESC
}
variable "python_command" {
  type        = string
  default     = "python3"
  description = "Interpreter used to install boto3 and to run the worker. python3, the distribution's own - see the same variable in the vscode_ec2 module for why the _monolithic template's symlink to 3.13 never took effect and must not be forced here: a dnf call follows it on this host, and breaking dnf means the CloudWatch agent is never installed"

  validation {
    condition     = can(regex("^python3(\\.[0-9]+)?$", var.python_command))
    error_message = "python_command must be python3 or python3.<minor> (e.g. python3.13). It is interpolated into shell commands in the user data."
  }
}
variable "dnf_packages" {
  type        = list(string)
  default     = ["python3.13", "amazon-cloudwatch-agent"]
  description = "Packages installed with dnf. Both are what the _monolithic template installed, in that order - note that the agent install is a dnf call that comes after the template's python symlink attempt, which is why forcing that symlink would break this host specifically"

  validation {
    condition     = alltrue([for package in var.dnf_packages : can(regex("^[a-zA-Z0-9._+-]+$", package))])
    error_message = "dnf_packages entries must be plain package names - they are interpolated into a dnf command line."
  }
}
variable "pip_packages" {
  type        = list(string)
  default     = ["boto3"]
  description = "Python packages the worker imports beyond the standard library. boto3 only - concurrent.futures and logging ship with Python"

  validation {
    condition     = alltrue([for package in var.pip_packages : can(regex("^[a-zA-Z0-9._\\[\\]=<>!-]+$", package))])
    error_message = "pip_packages entries must be plain requirement specifiers - they are interpolated into a pip command line."
  }
}
variable "timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Timezone set on the instance, as the _monolithic template set it. It decides the timestamps on the worker's log lines, which are the lines the metric filter counts - so comparing them against the metric means allowing for this offset, since CloudWatch timestamps are UTC"

  validation {
    condition     = can(regex("^[A-Za-z]+(/[A-Za-z0-9_+-]+)+$|^UTC$", var.timezone))
    error_message = "timezone must be a tz database name (e.g. Asia/Seoul) or UTC."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra shell appended after the worker and the agent are in place and before the marker file. Null adds nothing (rules.md B-4)"

  validation {
    condition     = var.additional_user_data == null || length(trimspace(var.additional_user_data)) > 0
    error_message = "additional_user_data must be a non-empty script, or null to add nothing."
  }
}
variable "marker_file_path" {
  type        = string
  default     = null
  description = "Directory a completion marker is written into as the last act of the user data, or null for none. Nothing waits on this host's marker today - the root's associations target the workbench - but it is here so an association that needs to run here has something to wait for rather than racing the bootstrap (rules.md D-5)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/[^ ]*$", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path with no spaces, or null to write no marker."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GiB. The _monolithic template set none, taking the AMI's 8GiB; 30 leaves room for the Development Tools group, the agent and a log file that grows by one line per message processed"

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB, the size of the Amazon Linux 2023 root image."
  }
}
variable "metadata_http_tokens" {
  type        = string
  default     = "required"
  description = "Whether IMDSv2 is enforced. Required, where the _monolithic template set nothing for this host and took the account default. Nothing on this instance reads the metadata service directly - boto3 and the CloudWatch agent both handle the token themselves - so there is no cost here, unlike on the workbench, where the load generator's region lookup is a plain IMDSv1 request"

  validation {
    condition     = contains(["required", "optional"], var.metadata_http_tokens)
    error_message = "metadata_http_tokens must be required (IMDSv2 only) or optional (IMDSv1 allowed)."
  }
}
