variable "name" {
  type        = string
  description = "Name of the MWAA environment. Also the prefix of the names derived from it - the execution role, the security group, and the airflow-<name>-* log groups MWAA creates for itself"
  validation {
    condition     = can(regex("^[a-zA-Z][0-9a-zA-Z_-]{0,79}$", var.name))
    error_message = "name must be 1-80 characters, start with a letter, and contain only letters, digits, hyphens and underscores, which is what MWAA accepts for an environment name."
  }
}
variable "account_id" {
  type        = string
  description = "Account the environment is in, for the ARNs in the execution role's policy. Passed in rather than read with data.aws_caller_identity, because this module is called with depends_on and a data source inside it would be deferred to apply (rules.md D-6)"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "region" {
  type        = string
  description = "Region the environment is in, for the ARNs and the kms:ViaService condition in the execution role's policy. Passed in for the same reason as account_id"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "airflow_version" {
  type        = string
  description = "Apache Airflow version of the environment"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.airflow_version))
    error_message = "airflow_version must be a three-part version such as 2.11.2."
  }
}
variable "environment_class" {
  type        = string
  description = "Environment class, which sizes the scheduler, the web server and each worker"
  validation {
    condition     = contains(["mw1.micro", "mw1.small", "mw1.medium", "mw1.large", "mw1.xlarge", "mw1.2xlarge"], var.environment_class)
    error_message = "environment_class must be one of mw1.micro, mw1.small, mw1.medium, mw1.large, mw1.xlarge or mw1.2xlarge."
  }
}
variable "min_workers" {
  type        = number
  description = "Workers MWAA keeps running even when no task is queued"
  validation {
    # No fixed upper bound of its own: max_workers is at least this and at most the account's quota.
    condition     = var.min_workers >= 1
    error_message = "min_workers must be at least 1."
  }
}
variable "max_workers" {
  type        = number
  description = "Upper bound MWAA scales workers to when tasks queue up. At most max_workers_quota"
  validation {
    condition     = var.max_workers >= 1
    error_message = "max_workers must be at least 1."
  }
  validation {
    # A pair, so the check reads both (rules.md B-1). MWAA rejects the combination at CreateEnvironment
    # otherwise, after the bucket, the role and the security group already exist.
    condition     = var.max_workers >= var.min_workers
    error_message = "max_workers must be greater than or equal to min_workers."
  }
  validation {
    # The account's quota rather than a fixed 25. MWAA's API sets no maximum of its own - the 25 in
    # its documentation is the quota's default - and CreateEnvironment's "MaxWorkers has a limit of
    # N" is that quota, enforced at apply after the bucket, the role and the security group already
    # exist (rules.md B-1). The quota is per region, hence --region in the message.
    condition     = var.max_workers <= var.max_workers_quota
    error_message = "max_workers must not exceed this account's MWAA Workers per environment quota (L-78AC1883) in ${var.region}, which is ${var.max_workers_quota} - CreateEnvironment would reject it at apply with \"MaxWorkers has a limit of ${var.max_workers_quota}\". Lower max_workers, or raise the quota first: aws service-quotas request-service-quota-increase --region ${var.region} --service-code airflow --quota-code L-78AC1883 --desired-value ${var.max_workers}"
  }
}
variable "max_workers_quota" {
  type        = number
  description = "The account's applied MWAA Workers per environment quota (L-78AC1883) in this region, which max_workers may not exceed. Passed in rather than read here, because this module is called with depends_on, which defers a data source inside it to apply whenever a dependency has changes pending - too late for the validation it feeds (rules.md D-6)"
  validation {
    condition     = var.max_workers_quota >= 1
    error_message = "max_workers_quota must be at least 1."
  }
}
variable "webserver_access_mode" {
  type        = string
  description = "Whether the Airflow web server has a public endpoint. Either way, signing in goes through IAM (airflow:CreateWebLoginToken); PUBLIC_ONLY only decides whether the login page is reachable from outside the VPC"
  validation {
    condition     = contains(["PUBLIC_ONLY", "PRIVATE_ONLY"], var.webserver_access_mode)
    error_message = "webserver_access_mode must be PUBLIC_ONLY or PRIVATE_ONLY."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the environment's security group is created in"
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets the environment's ENIs go in. MWAA takes exactly two, in different availability zones, and they need a route out - a NAT gateway or VPC endpoints - to reach S3, SQS and CloudWatch"
  validation {
    condition     = length(var.subnet_ids) == 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain exactly two valid subnet IDs; MWAA rejects any other count."
  }
}
variable "webserver_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the environment on 443 through its security group - the blueprint's source_cidr. That rule only governs the private web server endpoint and the environment's own ENIs; with PUBLIC_ONLY the login page is reached through MWAA's public endpoint, which this group does not front. Pass values known at plan time, because they are for_each keys (rules.md B-8)"
  validation {
    condition     = alltrue([for c in var.webserver_ingress_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "webserver_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "security_group_description" {
  type        = string
  default     = "Security group for MWAA environment"
  description = "Description of the environment's security group, as the blueprint's MWAA module worded it. Changing it replaces the group (rules.md F-1)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_description))
    error_message = "security_group_description must be 1-255 characters from the set AWS accepts for a security group description: a-zA-Z0-9, space, and . _-:/()#,@[]+=&;{}!$*. No apostrophe (rules.md F-1)."
  }
}
variable "dag_s3_path" {
  type        = string
  default     = "dags"
  description = "Prefix in the source bucket that MWAA syncs into /usr/local/airflow/dags on every scheduler, worker and web server"
  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.*'()-]+(/[a-zA-Z0-9!_.*'()-]+)*$", var.dag_s3_path))
    error_message = "dag_s3_path must be a relative S3 prefix with no leading or trailing slash (e.g. dags)."
  }
}
variable "dag_files" {
  type        = map(string)
  description = "Files placed under dag_s3_path, keyed by file name with the file's content as the value - DAGs and anything a DAG reads from its own folder, such as a kubeconfig. A map so the keys are static even when a value is only known after apply (rules.md B-8)"
  validation {
    condition     = alltrue([for name in keys(var.dag_files) : can(regex("^[A-Za-z0-9._-]+$", name))])
    error_message = "dag_files keys must be bare file names of letters, digits, dots, underscores and hyphens."
  }
  validation {
    # requirements.txt lives under the same prefix and is managed below as its own object, because
    # its version ID is what the environment pins.
    condition     = !contains(keys(var.dag_files), "requirements.txt")
    error_message = "dag_files must not contain requirements.txt; pass its content as requirements instead."
  }
}
variable "requirements" {
  type        = string
  description = "Content of requirements.txt, which MWAA installs on every component with pip at startup and on every update. From Airflow 2.7.2 on, a file without a --constraint line is given one by MWAA - the constraints of the environment's own Airflow version"
}
variable "airflow_configuration_options" {
  type        = map(string)
  default     = {}
  description = "Airflow configuration overrides, as section.key = value. The secrets backend options are not among them: the module sets those itself, because the execution role's Secrets Manager grant is scoped to the prefix they name"
  validation {
    condition     = alltrue([for key in keys(var.airflow_configuration_options) : can(regex("^[a-z_]+\\.[a-z0-9_]+$", key))])
    error_message = "airflow_configuration_options keys must be section.key in lowercase, e.g. core.load_examples."
  }
  validation {
    # A caller's value here would silently replace the module's, pointing the backend at a prefix the
    # execution role cannot read - and every connection lookup would then fail with AccessDenied
    # rather than falling through to the metadata database.
    condition     = !contains(keys(var.airflow_configuration_options), "secrets.backend") && !contains(keys(var.airflow_configuration_options), "secrets.backend_kwargs")
    error_message = "airflow_configuration_options must not set secrets.backend or secrets.backend_kwargs; the module configures the Secrets Manager backend itself, scoped to the prefix its execution role may read. Pass connections through the connections variable instead."
  }
}
variable "connections" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Airflow connections stored in Secrets Manager under this environment's prefix, keyed by connection ID, each value the connection as Airflow's JSON form ({\"conn_type\": ..., \"extra\": {...}} with host, login, password, schema and port as needed). Sensitive, because a connection usually carries a password even though this project's does not"
  validation {
    # Secrets Manager accepts these in a secret name, and Airflow reads the ID back out of it.
    condition     = alltrue([for id in keys(var.connections) : can(regex("^[A-Za-z0-9_.-]{1,200}$", id))])
    error_message = "connections keys must be connection IDs of letters, digits, underscores, dots and hyphens."
  }
  validation {
    # The JSON form, not a URI: the backend only standardises a value that starts with "{", and the
    # JSON form keeps the extra dict as a dict instead of percent-encoding every ARN into a query
    # string.
    condition     = alltrue([for value in values(var.connections) : can(jsondecode(value).conn_type)])
    error_message = "Each connections value must be a JSON object with at least a conn_type key - Airflow's JSON connection form."
  }
}
variable "secret_recovery_window_in_days" {
  type        = number
  default     = 0
  description = "Recovery window for the connection secrets on destroy. 0 deletes them at once. Secrets Manager's own default is 30 days, during which the name stays reserved - so a destroy followed by an apply within the month fails with \"a secret with this name is already scheduled for deletion\". Nothing in these secrets is irreplaceable: they are rebuilt from the configuration on the next apply"
  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 (delete immediately) or between 7 and 30, which is what Secrets Manager accepts."
  }
}
variable "log_level" {
  type        = string
  default     = "INFO"
  description = "Level for all five of the environment's CloudWatch log streams - DAG processing, scheduler, task, web server and worker - which the blueprint set to INFO alike"
  validation {
    condition     = contains(["CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"], var.log_level)
    error_message = "log_level must be one of CRITICAL, ERROR, WARNING, INFO or DEBUG."
  }
}
variable "bucket_prefix" {
  type        = string
  default     = "mwaa-"
  description = "Prefix for the generated source bucket name. A prefix rather than a fixed name because bucket names are globally unique - the blueprint appended a random suffix by hand for the same reason"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots and hyphens, starting with a letter or digit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy deletes every object version in the source bucket along with it, as the blueprint set. The bucket is versioned, which MWAA requires, so without this destroy stops here with BucketNotEmpty on the old versions even after the current objects are gone"
}
