variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION), as the _monolithic template had it"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like an AWS region (e.g. ap-northeast-2), or null to use the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "instance-profile-governance"
  description = "Name this project puts in front of the things it names itself - the Config delivery bucket prefix and the README heading. Replaces the _monolithic template's stack_name parameter, which existed to stand in for AWS::StackName and fed a fabricated stack ARN that nothing here needs"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}$", var.project_name))
    error_message = "project_name must be 2-39 characters of lowercase letters, digits and hyphens, so it can be used as an S3 bucket name prefix with room for the generated suffix."
  }
}
# --- The network ---
#
# These replace the _monolithic template's default_vpc_id and default_vpc_public_subnet_id
# parameters. That template ran in the account's default VPC; this project builds its own VPC and
# public subnet in modules/network, whose main.tf records why it diverges from the original.
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC this project builds. The public subnet is its first /24. Nothing here peers or routes to another network, so the only reason to change it is an overlap with a range already in use in the account"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
  validation {
    # try() because every validation block is evaluated, and a value with no "/" would fail here with
    # an index error rather than the message above.
    condition     = try(tonumber(split("/", var.vpc_cidr_block)[1]) >= 16 && tonumber(split("/", var.vpc_cidr_block)[1]) <= 24, true)
    error_message = "vpc_cidr_block must be between /16 and /24: AWS rejects a VPC larger than /16, and the public subnet is carved out of it as a /24."
  }
}
variable "availability_zone_suffix" {
  type        = string
  default     = "a"
  description = "Letter of the availability zone the public subnet is created in, appended to the region. Every instance in this project lands in that zone - the workbench and the test instances alike - so it has to be a zone that offers vscode_instance_type and test_instance_type. That is not checked at plan: an instance type a zone does not offer fails RunInstances with Unsupported partway through apply"

  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone_suffix))
    error_message = "availability_zone_suffix must be a single lowercase letter (e.g. a)."
  }
}
variable "ami_ssm_parameter_name" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
  description = "SSM public parameter resolved to the workbench AMI, as the _monolithic template had it. An Amazon Linux 2023 image specifically: the bootstrap uses dnf and installs code-server from the AL2023 layout"

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path starting with '/'."
  }
}
# --- AWS Config recorder, delivery channel and its bucket ---
variable "config_recorder_name" {
  type        = string
  default     = "default"
  description = <<-DESC
    Name of the configuration recorder, as the _monolithic template had it.

    Worth knowing before the first apply: AWS Config allows exactly one customer managed
    configuration recorder per account per region. A second copy of this project in the same region
    fails at apply with MaxNumberOfConfigurationRecordersExceededException, and - worse - an account
    that already has a recorder (Control Tower, Security Hub and a conformance pack all create one)
    will have this apply either collide with it or quietly take it over by name, because
    PutConfigurationRecorder is an upsert. To deploy this anywhere shared, check
    "aws configservice describe-configuration-recorders" first.

    The recorder also bills per configuration item delivered, and the recording group below records
    everything except four IAM types, so leaving this project running costs money per change in the
    account rather than per resource in this project.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.config_recorder_name))
    error_message = "config_recorder_name must be 1-256 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "config_recorder_enabled" {
  type        = bool
  default     = true
  description = "Whether to start the recorder once the delivery channel exists. True because a stopped recorder produces no configuration items, and a change-triggered rule with no configuration items never evaluates anything - the demo would look like a broken Lambda. The _monolithic template had no equivalent switch because CloudFormation starts the recorder for you; Terraform does not (see main.tf in modules/config_recorder)"
}
variable "config_delivery_channel_name" {
  type        = string
  default     = "default"
  description = "Name of the delivery channel. One per account per region, same as the recorder, and the provider's own default is this string"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,256}$", var.config_delivery_channel_name))
    error_message = "config_delivery_channel_name must be 1-256 characters of letters, digits, dots, underscores and hyphens."
  }
}
variable "config_snapshot_delivery_frequency" {
  type        = string
  default     = "One_Hour"
  description = "How often Config writes a full configuration snapshot to the bucket. One_Hour, which is the value the _monolithic template carried in a ConfigSnapshotDeliveryProperties block that cfn2tf left as a TODO comment because it had no mapping for it - aws_config_delivery_channel does have one, so the setting is restored here rather than lost"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.config_snapshot_delivery_frequency)
    error_message = "config_snapshot_delivery_frequency must be one of One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}
variable "config_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the Config delivery bucket before deleting it. True, and the cost is explicit: Config writes configuration history and snapshots that Terraform never created and does not track, so with this false a destroy stops at BucketNotEmpty with the recorder, the rule, the Lambda and the workbench already gone - leaving a bucket to empty by hand before the destroy can be rerun. True throws away the recorded history, which for a demo is the right trade and for anything audited is not"
}
variable "config_excluded_resource_types" {
  type = list(string)
  default = [
    "AWS::IAM::Policy",
    "AWS::IAM::User",
    "AWS::IAM::Role",
    "AWS::IAM::Group",
  ]
  description = <<-DESC
    Resource types the recorder does not record, as the _monolithic template had them. Everything
    else in the account is recorded, which is what the exclusion recording strategy means.

    These four are not an arbitrary cost saving. The rule's handler remediates by detaching and
    attaching role policies, so recording AWS::IAM::Role and AWS::IAM::Policy would turn every
    remediation into fresh configuration items - a stream of recorded changes caused by the thing
    reading the stream.
  DESC

  validation {
    condition     = alltrue([for type in var.config_excluded_resource_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", type))])
    error_message = "config_excluded_resource_types must contain AWS::Service::Resource type names (e.g. AWS::IAM::Role)."
  }
}
variable "config_service_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"]
  description = <<-DESC
    Managed policies attached to the role AWS Config assumes.

    The _monolithic template attached AdministratorAccess here. That is narrowed, and the narrowing
    is recorded because it is a deliberate divergence from what the original did (rules.md A-5):
    AWS_ConfigRole is AWS's own policy for this exact role and grants the Describe and List
    permissions a recorder needs, and nothing else. It replaced AWSConfigRole, which AWS deprecated
    in July 2022 - the older name still works for already attached roles and should not be used for
    new ones.

    AWS_ConfigRole does not grant write access to the delivery bucket, so narrowing to it alone
    would break delivery. modules/config_recorder adds that as an inline policy scoped to this one
    bucket; see the comment there.
  DESC

  validation {
    condition     = length(var.config_service_role_policy_arns) > 0
    error_message = "config_service_role_policy_arns must not be empty. Without a recording policy the recorder starts and records nothing, which looks exactly like a rule that never fires."
  }
  validation {
    condition     = alltrue([for arn in var.config_service_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "config_service_role_policy_arns must contain IAM policy ARNs."
  }
}
# --- The custom rule and its Lambda ---
variable "config_rule_name" {
  type        = string
  default     = "governance-role"
  description = "Name of the Config rule, as the _monolithic template had it. This is the name every verification command in the outputs passes to --config-rule-name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.config_rule_name))
    error_message = "config_rule_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "config_rule_resource_types" {
  type        = list(string)
  default     = ["AWS::EC2::Instance"]
  description = <<-DESC
    Resource types the rule's scope narrows evaluation to, as the _monolithic template had it.

    This has to match the handler, not just be a reasonable scope. lambda_src/lambda_function/index.py
    returns before evaluating anything whose configurationItem resourceType is not
    AWS::EC2::Instance, so widening the scope here does not widen the rule: Config would invoke the
    function for the extra types and the function would return None without calling put_evaluations,
    leaving those resources permanently in "No results available" with no error anywhere.
  DESC

  validation {
    # Length and membership rather than == ["AWS::EC2::Instance"]. The literal on the right is a
    # tuple and this variable is a list(string), and Terraform's == compares types as well as
    # contents, so the direct form is false for the one value it is supposed to accept.
    condition     = length(var.config_rule_resource_types) == 1 && contains(var.config_rule_resource_types, "AWS::EC2::Instance")
    error_message = "config_rule_resource_types must stay [\"AWS::EC2::Instance\"], because lambda_src/lambda_function/index.py returns early for every other resourceType. To evaluate another type, add a branch to the handler first - widening only this list produces invocations that report nothing and fail nothing."
  }
}
variable "lambda_function_name" {
  type        = string
  default     = "governance-lambda"
  description = "Name of the function backing the rule, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.lambda_function_name))
    error_message = "lambda_function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime, as the _monolithic template had it. Must stay a Python runtime: the deployment package is one .py file and boto3 is on the path only because the Python runtimes bundle it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "lambda_runtime must be a python3.x runtime, because the handler is Python and relies on the boto3 those runtimes provide."
  }
}
variable "lambda_handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point as module.function. Has to match the Python: lambda_src/lambda_function/index.py defines lambda_handler and archive_file zips it as index.py. A mismatch is not a plan error - Config invokes the function, Lambda answers Runtime.HandlerNotFound, and the only place that shows is the function's log"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+\\.[A-Za-z0-9_]+$", var.lambda_handler))
    error_message = "lambda_handler must be of the form module.function (e.g. index.lambda_handler)."
  }
}
variable "lambda_timeout_seconds" {
  type        = number
  default     = 60
  description = "How long the function may run, as the _monolithic template had it. The handler walks an instance profile's role and its attached policies with paginated IAM calls and may then detach and attach policies, so this is sized for IAM round trips rather than for compute"

  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "lambda_timeout_seconds must be between 1 and 900, the range Lambda accepts."
  }
}
variable "lambda_log_group_name" {
  type        = string
  default     = "/korea/governance/cloudwatch"
  description = "CloudWatch log group the function writes to, as the _monolithic template had it - an unconventional name for a Lambda log group, kept because it is the one the original chose and the outputs point at it. This log is the only evidence a rule that never evaluates leaves behind"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.lambda_log_group_name))
    error_message = "lambda_log_group_name must be 1-512 characters from the set CloudWatch Logs accepts for a log group name (letters, digits and _ . / # -)."
  }
}
variable "create_lambda_log_group" {
  type        = bool
  default     = true
  description = "Whether Terraform creates the log group rather than letting the function create it on first invocation. True, so retention is bounded and destroy removes it - a Lambda-created group outlives the stack forever at infinite retention. The cost: if a previous apply of this project left such a group behind, creating it fails with ResourceAlreadyExistsException, and the way out is to delete that group or set this false"
}
variable "lambda_log_retention_days" {
  type        = number
  default     = 14
  description = "Retention for that log group. Only has an effect when create_lambda_log_group is true; a group the function creates itself never expires"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.lambda_log_retention_days)
    error_message = "lambda_log_retention_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
variable "lambda_source_relative_path" {
  type        = string
  default     = "lambda_src/lambda_function/index.py"
  description = "Path, relative to this root, of the Python the deployment package is built from. Relative because archive_file resolves it against path.module, and a variable so the layout is stated rather than assumed"

  validation {
    condition     = can(regex("^[^/].*\\.py$", var.lambda_source_relative_path))
    error_message = "lambda_source_relative_path must be a relative path to a .py file."
  }
}
variable "lambda_build_relative_path" {
  type        = string
  default     = "build/lambda_function.zip"
  description = "Path, relative to this root, where the built deployment package is written. build/ is a product of reading the configuration rather than something to edit - archive_file writes the zip during plan"

  validation {
    condition     = can(regex("^[^/].*\\.zip$", var.lambda_build_relative_path))
    error_message = "lambda_build_relative_path must be a relative path to a .zip file."
  }
}
# --- The demo fixtures ---
variable "governed_instance_profiles" {
  type = map(object({
    instance_profile_name = string
    role_name             = string
    policy_arns           = list(string)
    demonstrates          = string
  }))
  default = {
    broad_permissions = {
      instance_profile_name = "governance-instance-profile-1"
      role_name             = "governance-instance-profile-1"
      policy_arns           = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      demonstrates          = "Non-compliant because its role carries a policy other than AmazonS3ReadOnlyAccess. The handler reports NON_COMPLIANT, then detaches AdministratorAccess, attaches AmazonS3ReadOnlyAccess and reports COMPLIANT - so this fixture can only be seen failing once"
    }
    no_permissions = {
      instance_profile_name = "governance-instance-profile-2"
      role_name             = "governance-instance-profile-2"
      policy_arns           = []
      demonstrates          = "Non-compliant for the opposite reason: no policies at all. The handler requires the attached set to be exactly AmazonS3ReadOnlyAccess and treats an empty set as failing, then attaches it"
    }
  }
  description = <<-DESC
    The instance profiles this demo exists to govern, keyed by what each one demonstrates.

    A map with one entry per fixture rather than two near-identical copies of a role plus a profile
    plus an attachment, because the fixtures differ only in their attached policies (rules.md B-7).
    The keys and the policy ARNs are literals in configuration, so they are known at plan time and
    can be for_each keys - the map-with-static-keys form that rules.md B-8 calls for applies to
    values that come from another module, which these do not.

    Both defaults are non-compliant, which is what the _monolithic template created. There is no
    compliant fixture to compare against, and adding one is a single entry here with
    policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"] - left out rather than invented,
    so the modular version builds what the original built.

    Neither profile is attached to anything. That is the shape of the demo, not an omission: the
    rule is change-triggered on AWS::EC2::Instance, so it evaluates an instance that carries one of
    these profiles, and launching that instance is the operator's step. See
    launch_test_instance_commands in the outputs.

    On the AdministratorAccess in broad_permissions: it is kept, and it is the one attachment in this
    project where keeping it is not a judgement call (rules.md A-5). It is not a permission anything
    uses - no instance carries this profile and nothing assumes this role as part of the apply - it is
    the input the rule is supposed to object to. Narrowing it to something harmless would delete the
    non-compliant case and leave a rule with nothing to find. The audit command in rules.md A-5 flags
    this file, so this paragraph is the answer to it.
  DESC

  validation {
    condition     = alltrue([for key in keys(var.governed_instance_profiles) : can(regex("^[a-zA-Z0-9_-]+$", key))])
    error_message = "governed_instance_profiles keys become part of resource addresses and of IAM policy attachment keys, so each must be letters, digits, underscores or hyphens."
  }
  validation {
    condition = alltrue([for profile in values(var.governed_instance_profiles) :
      can(regex("^[\\w+=,.@-]{1,64}$", profile.role_name)) && can(regex("^[\\w+=,.@-]{1,128}$", profile.instance_profile_name))
    ])
    error_message = "role_name must be 1-64 and instance_profile_name 1-128 characters from the set IAM accepts for names (letters, digits and _+=,.@-)."
  }
  validation {
    condition = alltrue(flatten([for profile in values(var.governed_instance_profiles) :
      [for arn in profile.policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))]
    ]))
    error_message = "policy_arns must contain IAM policy ARNs."
  }
  validation {
    condition     = alltrue([for profile in values(var.governed_instance_profiles) : length(profile.demonstrates) > 0])
    error_message = "demonstrates must not be empty. It is rendered into the workbench README, which is the only place the fixtures explain themselves to whoever is running the demo."
  }
}
variable "test_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type in the run-instances command the outputs hand to the operator. Those instances exist only to be recorded and evaluated, so the smallest thing that boots is the right size - and they are not Terraform resources, so nothing here terminates them"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.test_instance_type))
    error_message = "test_instance_type must be a valid EC2 instance type (e.g. t3.micro)."
  }
}
# --- The workbench ---
variable "key_name" {
  type        = string
  default     = "instance-profile-governance-key"
  description = "Name of the generated EC2 key pair. A fixed name rather than one sliced out of a fabricated stack ARN, which is what the _monolithic template did - key pair names are unique per account per region, so this would collide with a second copy of the project, and the single configuration recorder already rules that out (see config_recorder_name)"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "vscode_instance_name" {
  type        = string
  default     = "governance-bastion"
  description = <<-DESC
    Name tag of the workbench instance. Load-bearing, not cosmetic.

    lambda_src/lambda_function/index.py returns early for an instance whose Name tag is exactly
    "governance-bastion", and that early return is the only thing keeping the rule from evaluating
    the workbench itself. The workbench's role carries AdministratorAccess and IAMFullAccess, which
    is precisely what the handler strips: it would detach both, attach AmazonS3ReadOnlyAccess and
    report the instance compliant.
  DESC

  validation {
    condition     = var.vscode_instance_name == "governance-bastion"
    error_message = "vscode_instance_name must stay \"governance-bastion\". The handler exempts that exact Name tag, so renaming the instance does not fail the apply - a few minutes later the rule evaluates the workbench, strips AdministratorAccess and IAMFullAccess off its role and leaves terraform plan wanting to reattach them. To rename it, change the literal in lambda_src/lambda_function/index.py in the same commit."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Instance type for the workbench, as the _monolithic template had it. t3.micro is 2 vCPU and 1 GiB, and code-server plus a dnf groupinstall of Development Tools is a tight fit - t3.small is the first comfortable size if the IDE feels unusable"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.micro)."
  }
}
variable "vscode_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
  ]
  description = <<-DESC
    Managed policies attached to the workbench's role, as the _monolithic template had them.

    Kept broad deliberately. This is the human workbench rules.md H-1 is written around, and the
    demo run from it is: launch an instance with one of the governed profiles, read the rule's
    evaluation, attach and detach role policies by hand to watch the rule react. Narrowing this is
    narrowing the demo.

    IAMFullAccess is redundant underneath AdministratorAccess. It is kept because the original listed
    both, and because it records what this instance is actually expected to do.
  DESC

  validation {
    condition     = alltrue([for arn in var.vscode_iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "vscode_iam_policy_arns must contain IAM policy ARNs."
  }
}
variable "vscode_security_group_name" {
  type        = string
  default     = "governance-bastion-sg"
  description = "Name of the workbench's security group. The _monolithic template let CloudFormation generate one; a readable name makes the group findable in the console next to the groups the demo's test instances get"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.vscode_security_group_name)) && !startswith(var.vscode_security_group_name, "sg-")
    error_message = "vscode_security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "vscode_security_group_description" {
  type        = string
  default     = "Security Group"
  description = "Description attached to that group. The _monolithic template's literal string, kept rather than improved so the modular version describes the same group - and because changing it replaces the group (rules.md F-1). The charset validation on it is the part that matters"

  validation {
    condition     = length(var.vscode_security_group_description) > 0
    error_message = "vscode_security_group_description must not be empty. EC2 rejects an empty description, and omitting it entirely makes the provider write \"Managed by Terraform\"."
  }
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.vscode_security_group_description))
    error_message = "vscode_security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - a possessive in an English sentence is the usual way this happens, and EC2 rejects the CreateSecurityGroup call with InvalidParameterValue partway through apply, after the bucket, the roles and the recorder already exist."
  }
}
variable "vscode_ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Source ranges allowed to reach SSH and code-server on the workbench, as the _monolithic template had them. code-server runs with auth disabled, so 0.0.0.0/0 means anyone who finds the address gets a root-capable shell in a browser - narrow this to an office range, or set it to a range that reaches nothing and use the session_manager_command output instead"

  validation {
    condition     = length(var.vscode_ingress_cidr_blocks) > 0 && alltrue([for cidr in var.vscode_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "vscode_ingress_cidr_blocks must be a non-empty list of IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "vscode_ssh_port" {
  type        = number
  default     = 22
  description = "SSH port opened on the workbench, as the _monolithic template had it. Needed only for the generated key pair; Session Manager does not use it"

  validation {
    condition     = var.vscode_ssh_port > 0 && var.vscode_ssh_port <= 65535
    error_message = "vscode_ssh_port must be a valid TCP port."
  }
}
variable "vscode_code_server_port" {
  type        = number
  default     = 8000
  description = "Port code-server binds to and the port opened for it, as the _monolithic template had it. One variable feeding the listener, the security group rule and the URL in the outputs, so the three cannot disagree (rules.md B-5)"

  validation {
    condition     = var.vscode_code_server_port > 0 && var.vscode_code_server_port <= 65535
    error_message = "vscode_code_server_port must be a valid TCP port."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.100.3"
  description = "code-server release to install, as the _monolithic template had it. That template repeated the version in three places in one shell script - the download URL, the tarball name and the directory it unpacks to - so a bump had to be made three times or the mv failed with \"No such file or directory\""

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.100.3)."
  }
}
variable "vscode_associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the workbench gets a public IP, as the _monolithic template had it. Has to stay true: the subnet modules/network builds routes only to an internet gateway, which carries nothing for an instance without a public address"

  validation {
    # A constraint of this root's network rather than of the pair of variables, so the constant
    # condition is the right form (rules.md B-1). With false, plan and apply both succeed: the
    # instance boots with no path out, the bootstrap cannot download code-server, the SSM agent never
    # registers, and the README association waits out readme_timeout_seconds before failing with
    # "unexpected state 'Failed'" - and Session Manager, the one way in that needs no open port, is
    # the thing that cannot work.
    condition     = var.vscode_associate_public_ip_address
    error_message = "vscode_associate_public_ip_address must be true, because the VPC this project builds has no NAT gateway and no VPC endpoints - a public address through the internet gateway is the workbench's only route to the dnf mirrors, GitHub and the SSM endpoints. To run it without one, add a NAT gateway or the ssm, ssmmessages and ec2messages interface endpoints to modules/network first, and route the code-server download through them."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker. The README association waits on <this>/userdata rather than on depends_on or a timeout (rules.md D-5), so this root requires a real path - the module itself treats it as optional"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'. This root always needs one: the README association's until loop interpolates it, and a null would make that loop wait on \"/userdata\" forever."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take to report success. It has to cover the whole bootstrap, because the command spends almost all of that time in the until loop waiting for the marker - a dnf update plus Development Tools plus the code-server download on a t3.micro is the slow part"

  validation {
    condition     = var.readme_timeout_seconds >= 60 && var.readme_timeout_seconds <= 3600
    error_message = "readme_timeout_seconds must be between 60 and 3600."
  }
}
