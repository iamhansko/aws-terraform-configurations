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
  description = "Subnet the instance is launched in. Must be a public subnet: the instance is reached over RDP from outside the VPC, and its userdata reaches the PowerShell Gallery, Chocolatey, GitHub, bun.sh and the Kiro download host"

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID (e.g. subnet-0123456789abcdef0)."
  }
}
variable "ami_id" {
  type        = string
  description = "AMI for the instance, resolved by the caller. Taken as an id rather than looked up here, so this module does not have to know that the caller reads it from an SSM public parameter (rules.md B-6)"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI ID (e.g. ami-0123456789abcdef0). A value starting with a slash is the SSM parameter path, which the caller has to resolve through a data source first."
  }
}
variable "key_name" {
  type        = string
  description = "Name of the EC2 key pair to attach. Not optional on Windows the way it is on Linux: EC2 encrypts the generated Administrator password with this key pair at launch, and an instance launched without one has no retrievable Administrator password at all"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters."
  }
}
variable "instance_name" {
  type        = string
  default     = "windows"
  description = "Name tag for the instance, as the _monolithic template had it"

  validation {
    condition     = length(var.instance_name) > 0
    error_message = "instance_name must not be empty."
  }
}
variable "instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = "Instance type, as the _monolithic template had it. The workload is a Windows Server desktop plus Chocolatey installing Git, the AWS CLI, Node and Python, plus the Kiro IDE, plus two bun dev servers - this is deliberately not a small type"

  validation {
    condition     = can(regex("^[a-z0-9]+[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g. m5.2xlarge)."
  }
}
variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the instance gets a public address. True: the RDP client connects to it from outside the VPC, and rdp_endpoint is built from it"
}
variable "security_group_name" {
  type        = string
  default     = "windows-sg"
  description = "Name of the security group, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name)) && !startswith(var.security_group_name, "sg-")
    error_message = "security_group_name must be 1-255 characters from the set AWS accepts for a security group name (a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*, no apostrophe) and must not start with \"sg-\", which EC2 reserves for security group IDs."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for the Windows workshop instance reached over RDP"
  description = <<-DESC
    Description attached to the security group. The _monolithic template said "Security Group", which
    says nothing; this is a deliberate divergence and the reason it is worth making up front is that
    AWS has no API to modify a security group description, so changing it later replaces the group
    (rules.md F-1) - and a group being replaced while an instance references it is a dependency the
    replacement has to work around.

    An apostrophe in this value is rejected by EC2, not by Terraform. "the instance's security group"
    reads naturally and fails at apply time with InvalidParameterValue, which is what the validation
    below exists to catch at plan time.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. An apostrophe is NOT allowed - EC2 rejects the CreateSecurityGroup call with InvalidParameterValue, which otherwise only surfaces at apply time (rules.md F-1)."
  }
}
variable "revoke_rules_on_delete" {
  type        = bool
  default     = false
  description = "Whether Terraform revokes the group's rules before deleting it. False, because nothing adds rules to this group behind Terraform's back - there is no load balancer controller here and EC2 adds nothing on its own (rules.md F-2 requires true only for groups a controller writes to)"
}
variable "rdp_port" {
  type        = number
  default     = 3389
  description = "Port the security group opens for RDP. 3389 is where Windows Terminal Services listens; changing this here only changes the security group, so the Terminal Server registry configuration would have to be changed to match"

  validation {
    condition     = var.rdp_port > 0 && var.rdp_port <= 65535
    error_message = "rdp_port must be between 1 and 65535."
  }
}
variable "ingress_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = <<-DESC
    Source CIDRs allowed to reach rdp_port. An empty list creates no ingress rule, which leaves the
    instance reachable only through SSM Session Manager.

    This replaces the _monolithic template's InboundFromAnywhere parameter, a string constrained to
    "True" and "False" because CloudFormation parameters have no boolean type. A list says the same
    thing and more: ["0.0.0.0/0"] is that parameter set to True, [] is False, and anything narrower is
    the case the string could not express.

    RDP open to the whole internet is the default only because that is what the template did. Windows
    Server answers 3389 from first boot, before any of the setup below has run, so this is reachable and
    being brute-forced for the entire several-minute setup window - narrowing it to the address you
    connect from is the single most useful change to make here.
  DESC

  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks must contain valid IPv4 CIDR blocks (e.g. 203.0.113.0/24)."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policy ARNs attached to the instance role.

    AdministratorAccess, which is what the _monolithic template attached, and it is kept rather than
    narrowed. This instance is a human workbench: a workshop participant sits at the desktop and builds
    an application against Cognito, DynamoDB and Bedrock from it, and the game server it runs reads the
    instance role credentials. rules.md H-1 takes the same position for vscode_ec2 and bastion_ec2, and
    A-5 excludes that class of role from its audit for this reason.

    A-5's audit command filters on the names vscode_ec2 and bastion, so this module appears in it as a
    finding. It is not one. Narrowing the policy here would narrow what the original could do rather
    than reproduce it - and the narrowest honest replacement is not small: secretsmanager:GetSecretValue
    on the workshop secret, dynamodb:* on six tables, cognito-idp:* on the pool, plus whatever the
    participant is asked to build next.
  DESC

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", arn))])
    error_message = "iam_policy_arns must be a non-empty list of IAM policy ARNs. The list cannot be empty: the userdata's first real action is Get-SECSecretValue, and without a policy that call fails inside its try block and no workshop account is ever created."
  }
}
variable "root_volume_size" {
  type        = number
  default     = 100
  description = "Root volume size in GiB, as the _monolithic template had it. Windows Server 2025 Full Base starts around 30 GiB before Chocolatey, Node, Python, the Kiro IDE and two node_modules trees are added"

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size must be at least 30 GiB, which is the size of the Windows Server Full Base root volume before anything this userdata installs."
  }
}
variable "root_volume_type" {
  type        = string
  default     = "gp3"
  description = "Root volume type, as the _monolithic template had it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2, standard."
  }
}
variable "root_volume_encrypted" {
  type        = bool
  default     = false
  description = "Whether the root volume is encrypted. False reproduces the _monolithic template. True is the better default for anything holding real data and costs nothing here"
}
variable "aws_region" {
  type        = string
  description = <<-DESC
    Region written into the game server's environment as AWS_REGION.

    Passed in rather than read from a data source in this module, because the module carries depends_on
    at its call site and a data source inside it would be deferred to apply (rules.md D-6). The value is
    also needed at plan time to assemble the diagnostic commands in the outputs.

    The userdata separately discovers the region from the instance metadata service for its own
    Get-SECSecretValue call. That is not duplication to be collapsed: the discovered value lives in the
    setup script's process, and the server script is written as a single-quoted PowerShell here-string
    that a different process runs later, so it needs a literal.
  DESC

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2."
  }
}
variable "workshop_username" {
  type        = string
  default     = "kiro"
  description = "Windows local account the userdata creates and the RDP login uses. The same value is stored in the workshop secret, so that the credential pair matches the account that exists"

  validation {
    # New-LocalUser rejects a name over 20 characters and rejects the characters
    # below outright. Both failures land inside the userdata's try block, so apply
    # reports the instance as created and the only symptom is RDP refusing a
    # password that looks correct.
    condition     = can(regex("^[^\"/\\\\\\[\\]:;|=,+*?<>@ ]{1,20}$", var.workshop_username))
    error_message = "workshop_username must be 1-20 characters and must not contain a space, @, or any of \" / \\ [ ] : ; | = , + * ? < >, because New-LocalUser rejects those and the failure only surfaces on the instance."
  }
}
variable "workshop_dir" {
  type        = string
  default     = "C:\\ProgramData\\KiroWorkshop"
  description = "Directory on the instance holding the setup log, the clone, the generated launcher scripts and the virtualenv. Under ProgramData rather than a user profile, as the _monolithic template had it, because the userdata runs as SYSTEM before the workshop account's profile exists"

  validation {
    condition     = can(regex("^[A-Za-z]:\\\\[^\"<>|]*[^\"<>|\\\\]$", var.workshop_dir))
    error_message = "workshop_dir must be an absolute Windows path with a drive letter and no trailing backslash, e.g. C:\\ProgramData\\KiroWorkshop. A trailing backslash would double up when paths are built from it, and the characters \" < > | are not legal in a Windows path."
  }
}
variable "git_clone_url" {
  type        = string
  default     = "https://github.com/iamhansko/spirit-of-kiro.git"
  description = "Repository the userdata clones, as the _monolithic template had it"

  validation {
    condition     = can(regex("^https://[^\\s\"']+$", var.git_clone_url))
    error_message = "git_clone_url must be an https URL. The clone runs unattended with no credential helper, so an ssh or authenticated URL hangs on a prompt the instance cannot answer - and because the clone is inside a try block, that surfaces as a missing project directory rather than an error."
  }
}
variable "git_clone_branch" {
  type        = string
  default     = "challenge"
  description = "Branch to clone, as the _monolithic template had it. It is also used as the directory name the clone lands in, so it appears in the launcher scripts and the desktop shortcut paths"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]{1,255}$", var.git_clone_branch))
    error_message = "git_clone_branch must be 1-255 characters of letters, digits, dots, underscores, slashes and hyphens. It is used as a directory name as well as a branch name, so characters Windows rejects in a path are rejected here."
  }
}
variable "secret_id" {
  type        = string
  description = "Identifier the userdata passes to Get-SECSecretValue to read the workshop credential. The caller passes the secret ARN; the secret must already have a version holding the password, which is why the call site orders this module after the whole secret module and not just after the secret resource"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:", var.secret_id)) || can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.secret_id))
    error_message = "secret_id must be a Secrets Manager ARN or a secret name."
  }
}
variable "cognito_user_pool_id" {
  type        = string
  description = "User pool id written into the game server environment as COGNITO_USER_POOL_ID"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]_[A-Za-z0-9]+$", var.cognito_user_pool_id))
    error_message = "cognito_user_pool_id must look like ap-northeast-2_AbC123xyz."
  }
}
variable "cognito_user_pool_arn" {
  type        = string
  description = "User pool ARN written into the game server environment as COGNITO_USER_POOL_ARN. The server needs this as well as the id: the id addresses the pool in API calls, the ARN is what an IAM policy or authorizer names"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:cognito-idp:", var.cognito_user_pool_arn))
    error_message = "cognito_user_pool_arn must be a Cognito user pool ARN."
  }
}
variable "cognito_client_id" {
  type        = string
  description = "App client id written into the game server environment as COGNITO_CLIENT_ID"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{20,32}$", var.cognito_client_id))
    error_message = "cognito_client_id must be 20-32 alphanumeric characters."
  }
}
variable "dynamodb_table_names" {
  type        = map(string)
  description = <<-DESC
    Table name per logical key. Each entry becomes a DYNAMODB_TABLE_<KEY-UPPERCASED> environment
    variable in the generated server launcher, replacing the six hardcoded lines the _monolithic
    template carried - so adding a table in the caller adds its environment variable here with no edit
    to this module.

    A map rather than six separate variables because the table names come from another module and are
    unknown until apply; the keys are configuration literals and are known at plan time, which is what
    lets them be iterated (rules.md B-8). Note which half is validated below: the keys are checked
    immediately, the values only once they are known.
  DESC

  validation {
    # upper(key) becomes part of a PowerShell environment variable name, so a key
    # with a hyphen or a dot renders $Env:DYNAMODB_TABLE_ITEM-IMAGES - which
    # PowerShell parses as a subtraction against an undefined variable and
    # assigns nothing. The server then reads an empty table name and fails at
    # runtime with a ValidationException on its first query.
    condition     = alltrue([for key in keys(var.dynamodb_table_names) : can(regex("^[a-z][a-z0-9_]*$", key))])
    error_message = "dynamodb_table_names keys must start with a lowercase letter and contain only lowercase letters, digits and underscores, because each is uppercased into a PowerShell environment variable name - a hyphen or dot there parses as an operator and silently assigns nothing."
  }
  validation {
    condition     = alltrue([for name in values(var.dynamodb_table_names) : length(name) >= 3])
    error_message = "dynamodb_table_names values must be DynamoDB table names, which are at least 3 characters."
  }
}
variable "item_images_service_url" {
  type        = string
  default     = "https://d16sw0kh78rbrs.cloudfront.net"
  description = <<-DESC
    Image service the game client calls, written into the server environment as
    ITEM_IMAGES_SERVICE_URL.

    This is the one value in this project that nothing here creates. The default is the CloudFront
    distribution the original workshop ran, carried over from the _monolithic template as a literal; it
    belongs to someone else's account, so it can disappear without anything in this configuration
    changing. It is a variable rather than a literal mainly so that the fact is visible, and so a
    replacement can be pointed at without editing the userdata.
  DESC

  validation {
    condition     = can(regex("^https?://[^\\s\"']+$", var.item_images_service_url))
    error_message = "item_images_service_url must be an http or https URL with no trailing whitespace."
  }
}
variable "game_server_port" {
  type        = number
  default     = 8080
  description = "Port the game server listens on. The client's websocket URL is derived from this rather than taken as a second variable, because the two cannot usefully disagree - the _monolithic template wrote 8080 into VITE_WS_URL as a literal with nothing tying it to the server"

  validation {
    condition     = var.game_server_port > 0 && var.game_server_port <= 65535
    error_message = "game_server_port must be between 1 and 65535."
  }
}
variable "client_dev_port" {
  type        = number
  default     = 5173
  description = "Port the client dev server listens on. 5173 is Vite's default, which is what \"bun run dev\" starts; it is declared here only so the readiness check in the outputs can name it"

  validation {
    condition     = var.client_dev_port > 0 && var.client_dev_port <= 65535
    error_message = "client_dev_port must be between 1 and 65535."
  }
}
variable "nodejs_version" {
  type        = string
  default     = "22.19.0"
  description = "Exact nodejs-lts version Chocolatey installs, pinned as the _monolithic template pinned it. Unpinned, the package floats and a workshop that worked last month installs a different Node this month"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nodejs_version))
    error_message = "nodejs_version must be a three-part version such as 22.19.0, the form Chocolatey's --version argument takes."
  }
}
variable "python_package" {
  type        = string
  default     = "python313"
  description = "Chocolatey package providing Python, as the _monolithic template had it. Chocolatey versions Python by package name rather than by --version, so this is a name and not a number"

  validation {
    condition     = can(regex("^python[0-9]{2,3}$", var.python_package))
    error_message = "python_package must be a Chocolatey Python package name such as python313."
  }
}
variable "python_packages" {
  type        = list(string)
  default     = ["boto3", "requests", "requests_aws4auth"]
  description = "Packages installed into the virtualenv the userdata creates, as the _monolithic template had them"

  validation {
    condition     = alltrue([for package in var.python_packages : can(regex("^[A-Za-z0-9._-]+$", package))])
    error_message = "python_packages entries must be bare package names - this list is interpolated into a pip command line, so a version specifier or a URL would need quoting that is not applied."
  }
}
variable "kiro_installer_url" {
  type        = string
  default     = "https://prod.download.desktop.kiro.dev/releases/stable/win32-x64/signed/0.7.45/kiro-ide-0.7.45-stable-win32-x64.exe"
  description = <<-DESC
    Installer the userdata downloads for the Kiro IDE, pinned to the version the _monolithic template
    pinned.

    Pinned rather than following a "latest" redirect, so the workshop installs the same IDE every time.
    The cost of pinning is the other direction: a version that gets withdrawn makes Invoke-WebRequest
    fail, and because that call is inside the try block the symptom is a desktop with no Kiro shortcut
    rather than an error.
  DESC

  validation {
    condition     = can(regex("^https://[^\\s\"']+\\.exe$", var.kiro_installer_url))
    error_message = "kiro_installer_url must be an https URL ending in .exe - it is downloaded and run with /VERYSILENT, so an installer in another format would be started and never complete."
  }
}
variable "git_available_retries" {
  type        = number
  default     = 10
  description = "How many times the userdata re-reads the machine PATH waiting for git to appear after Chocolatey installs it, as the _monolithic template had it. Chocolatey writes PATH to the registry and the running process does not inherit it, which is what the retry loop is working around"

  validation {
    condition     = var.git_available_retries >= 1
    error_message = "git_available_retries must be at least 1."
  }
}
variable "reboot_delay_seconds" {
  type        = number
  default     = 5
  description = "Delay on the shutdown command that ends the setup, as the _monolithic template had it. The reboot is what makes the machine PATH, the Kiro install and the all-users logon script take effect for an interactive session"

  validation {
    condition     = var.reboot_delay_seconds >= 0
    error_message = "reboot_delay_seconds must not be negative."
  }
}
variable "additional_user_data" {
  type        = string
  default     = null
  description = "Extra PowerShell injected at the end of the try block, after the Kiro IDE install and before the reboot. Null adds nothing. Rendered through a conditional interpolation rather than through the template if directive rules.md B-4 prescribes - main.tf explains why that directive form is wrong for this particular template"

  validation {
    # A carriage return is the rules.md A-4 failure, arriving through the one
    # door a correctly stored .tf file cannot close: a value typed into a
    # .tfvars file or an environment variable on Windows. Every literal line of
    # the injected block would end in \r, so a here-string terminator in it
    # becomes '@\r and stops terminating anything, and the script swallows the
    # rest of itself. Nothing in the EC2 console output explains that.
    condition     = var.additional_user_data == null || !can(regex("\r", var.additional_user_data))
    error_message = "additional_user_data must not contain a carriage return. It is interpolated into a PowerShell script, where a \\r makes every here-string terminator and block keyword fail to match, so the whole script fails to parse and no line of the setup runs (rules.md A-4)."
  }
}
variable "setup_log_tail_lines" {
  type        = number
  default     = 40
  description = "How many lines from the end of the setup log the setup_log check association prints. The whole log of a successful run is about 30 lines"

  validation {
    condition     = var.setup_log_tail_lines >= 1 && floor(var.setup_log_tail_lines) == var.setup_log_tail_lines
    error_message = "setup_log_tail_lines must be a whole number of at least 1."
  }
}
variable "setup_wait_seconds" {
  type        = number
  default     = 2400
  description = <<-DESC
    How long each setup_check association waits on the instance for the setup script's status marker
    before checking anyway. setup_log then fails on the missing marker; rdp_status and app_status
    report what exists at that point.

    Counted from when the command starts on the instance, which is when SSM Agent first registers. So
    far that has been after the setup's reboot, with nothing left to wait for; if the agent comes up
    earlier, a complete setup takes about ten minutes (Chocolatey, Git, the AWS CLI, Node, Python, bun
    and the Kiro IDE all download at boot), and 40 minutes leaves room for slow package mirrors without
    hiding a hung step for long.
  DESC

  validation {
    # The upper bound keeps executionTimeout (this plus 120) inside the
    # 172800 seconds AWS-RunPowerShellScript accepts.
    condition     = var.setup_wait_seconds >= 60 && var.setup_wait_seconds <= 172680
    error_message = "setup_wait_seconds must be between 60 and 172680, so that the command's executionTimeout - this value plus 120 - stays within the 172800 seconds AWS-RunPowerShellScript accepts."
  }
}
variable "association_name_prefix" {
  type        = string
  default     = "windows"
  description = "Prefix for the names of the setup_check associations, which become <prefix>-setup-log, <prefix>-rdp-status and <prefix>-app-status. A name is what tells the three apart in the State Manager console, where each otherwise shows only as AWS-RunPowerShellScript and an id"

  validation {
    # State Manager accepts 3-128 characters from this set; 100 leaves room for
    # the longest suffix added in main.tf.
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,100}$", var.association_name_prefix))
    error_message = "association_name_prefix must be 1-100 letters, digits, underscores, hyphens or dots - the characters State Manager accepts in an association name, which is at most 128 characters including the suffix this module adds."
  }
}
variable "user_data_replace_on_change" {
  type        = bool
  default     = true
  description = "Whether changing the userdata rebuilds the instance. True, which is a divergence from the _monolithic template - it left the provider default of false, and with false an edit to the setup script produces a plan that reports a change and does nothing to the machine, because EC2Launch runs user data only on first boot. See main.tf"
}
