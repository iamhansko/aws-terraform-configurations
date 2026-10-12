# The blueprint's MWAA environment (mwaa.tf), which it built with aws-ia/mwaa 0.0.4 on top of a
# bucket from terraform-aws-modules/s3-bucket: the source bucket and what goes in it, the connections
# the environment's secrets backend reads, the execution role, the security group and the
# environment. One module because none of them is useful alone.
#
# What the EMR job policy and the Kubernetes access are not: they are about what the DAGs reach, not
# about the environment, so the root grants them by joining this module's role to the EMR and EKS
# modules (rules.md C-1). The connections are the opposite case - the root decides what they say, but
# where they are stored and who may read them is the environment's own configuration - so the module
# takes their content and owns the rest.

# --- Connections -----------------------------------------------------------------------------------
#
# Airflow connections in Secrets Manager rather than in the environment's metadata database. The
# blueprint left the EMR connection as a step in the Airflow UI, because the database is not
# something Terraform can write to; a secrets backend is. Airflow asks the backend first on every
# connection lookup and falls back to environment variables and then the database when the backend
# has nothing, so connections added in the UI still work alongside these.

locals {
  # Under the environment's own name, so the execution role's grant names exactly this prefix and two
  # environments in one account cannot read each other's connections. MWAA's guide uses
  # airflow/connections and a grant on every secret in the region.
  connections_prefix = "airflow/${var.name}/connections"
  secrets_backend_options = {
    "secrets.backend" = "airflow.providers.amazon.aws.secrets.secrets_manager.SecretsManagerBackend"
    "secrets.backend_kwargs" = jsonencode({
      connections_prefix = local.connections_prefix
      # null turns the variable and configuration lookups off - the backend returns before calling
      # Secrets Manager at all. Left at their defaults (airflow/variables, airflow/config) every
      # Variable.get would call GetSecretValue on a name outside the prefix granted below, and the
      # AccessDenied that comes back is not one of the errors the backend treats as "not found".
      variables_prefix = null
      config_prefix    = null
    })
  }
}
# for_each over the keys alone, unwrapped with nonsensitive(): the connection IDs are not secret, but
# keys() of a sensitive map is sensitive, and Terraform refuses a sensitive value as for_each. The
# keys come from the caller's configuration, so they are known at plan (rules.md B-8).
resource "aws_secretsmanager_secret" "connection" {
  for_each = nonsensitive(toset(keys(var.connections)))

  name                    = "${local.connections_prefix}/${each.key}"
  description             = "Airflow connection ${each.key} for the ${var.name} MWAA environment"
  recovery_window_in_days = var.secret_recovery_window_in_days
}
resource "aws_secretsmanager_secret_version" "connection" {
  for_each = aws_secretsmanager_secret.connection

  secret_id     = each.value.id
  secret_string = var.connections[each.key]
}

# --- Source bucket ---------------------------------------------------------------------------------

resource "aws_s3_bucket" "source" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy
  tags = {
    Name = "${var.name}-source"
  }
}
# Versioning, which MWAA requires of its source bucket - and which the blueprint's bucket did not
# have, because terraform-aws-modules/s3-bucket only enables it when asked. The environment also pins
# requirements.txt by version ID below, which only exists with versioning on.
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}
# All four on, which MWAA also requires and which the blueprint set.
resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# The two statements the blueprint's attach_deny_insecure_transport_policy and
# attach_require_latest_tls_policy wrote. Both are Deny, so they are not "public" in the sense the
# public access block above rejects.
resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "denyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "denyOutdatedTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
        Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
      },
    ]
  })
  # S3 evaluates a new policy against the bucket's public access block, so the block is in place
  # first rather than racing it.
  depends_on = [aws_s3_bucket_public_access_block.source]
}
# Under the DAG prefix, as the blueprint put it (it uploaded the whole dags/ folder, requirements.txt
# included). Its own resource because the environment pins its version ID: a changed file is a new
# version, and the environment update that follows is what makes MWAA reinstall.
resource "aws_s3_object" "requirements" {
  bucket       = aws_s3_bucket.source.id
  key          = "${var.dag_s3_path}/requirements.txt"
  content      = var.requirements
  content_type = "text/plain"
  # A version ID only exists once versioning is on; without the ordering the first object could land
  # unversioned and the environment would pin "null".
  depends_on = [aws_s3_bucket_versioning.source]
}
# The DAGs and the files they read. Keyed by file name, so for_each has static keys even though the
# kubeconfig's content is only known once the cluster exists (rules.md B-8). That one object waits
# for the cluster; the environment does not wait for any of these - MWAA picks DAG files up from S3
# whenever they land, so the environment and the cluster are created side by side rather than one
# after the other.
resource "aws_s3_object" "dag_files" {
  for_each = var.dag_files

  bucket  = aws_s3_bucket.source.id
  key     = "${var.dag_s3_path}/${each.key}"
  content = each.value
  # text/x-python for the DAGs and text/plain for the rest, so the console's preview shows them
  # rather than offering a download.
  content_type = endswith(each.key, ".py") ? "text/x-python" : "text/plain"
  depends_on   = [aws_s3_bucket_versioning.source]
}

# --- Execution role -------------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  # Generated, because AWS asks that a deleted execution role's name not be reused for a new one, and
  # a fixed name is reused on every destroy-and-apply.
  name_prefix = "${substr(var.name, 0, 32)}-exec-"
  description = "Execution role for the ${var.name} MWAA environment"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["airflow.amazonaws.com", "airflow-env.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# AWS's documented execution role policy for an environment that uses an AWS owned key, scoped to
# this environment, this bucket and this environment's log groups.
#
# Narrower than what the blueprint's aws-ia/mwaa 0.0.4 module wrote, on purpose. That module trusted
# batch, ssm, lambda and s3 as well as airflow, and granted s3:* on the bucket, eks:*, batch:*, ssm:*
# on every parameter and logs:* on every Lambda log group - for DAGs this project does not have. What
# the blueprint's own DAGs need beyond the baseline is EMR job submission, which the root attaches as
# its own policy exactly as the blueprint did, and Kubernetes access, which is an access entry and a
# Role rather than an IAM permission. eks:* in particular buys nothing: aws eks get-token, which the
# kubeconfig runs, presigns an STS call and needs no EKS permission at all (rules.md A-5 - narrowing
# what the original granted is a change, and this is where it is recorded).
resource "aws_iam_role_policy" "execution" {
  name = "mwaa-execution"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "airflow:PublishMetrics"
        Resource = "arn:aws:airflow:${var.region}:${var.account_id}:environment/${var.name}"
      },
      {
        Effect   = "Deny"
        Action   = "s3:ListAllMyBuckets"
        Resource = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject*", "s3:GetBucket*", "s3:List*"]
        Resource = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:GetLogRecord",
          "logs:GetLogGroupFields",
          "logs:GetQueryResults",
        ]
        # MWAA names its log groups airflow-<environment>-<component>.
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:airflow-${var.name}-*"
      },
      {
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetAccountPublicAccessBlock"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      },
      {
        # The Celery queue MWAA owns. It lives in an MWAA service account, which is why the account
        # in the ARN is a wildcard.
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
        ]
        Resource = "arn:aws:sqs:${var.region}:*:airflow-celery-*"
      },
      {
        # The AWS owned key that encrypts that queue - any key outside this account, and only when SQS
        # is the caller.
        Effect      = "Allow"
        Action      = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:Encrypt"]
        NotResource = "arn:aws:kms:*:${var.account_id}:key/*"
        Condition = {
          StringLike = { "kms:ViaService" = ["sqs.${var.region}.amazonaws.com"] }
        }
      },
      {
        # The secrets backend's one call, on this environment's prefix. MWAA's guide grants
        # SecretsManagerReadWrite, or GetSecretValue on every secret in the region plus ListSecrets;
        # SecretsManagerBackend in the provider this environment installs calls GetSecretValue and
        # nothing else (rules.md A-5).
        #
        # The wildcard also covers connection IDs that have no secret - aws_default, which the Amazon
        # operators look up before falling back to the execution role's own credentials. Those have
        # to come back as ResourceNotFoundException, which the backend treats as "not here, ask the
        # next one"; an AccessDenied would fail the lookup outright. The secrets are encrypted with the
        # aws/secretsmanager key, which needs no KMS grant of its own.
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${local.connections_prefix}/*"
      },
    ]
  })
}

# --- Security group --------------------------------------------------------------------------------

resource "aws_security_group" "mwaa" {
  name        = "${var.name}-sg"
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = "${var.name}-sg"
  }
}
# Standalone rules rather than inline blocks, as the upstream module wrote them (rules.md F-2). The
# self rule is what MWAA's own components use to reach each other through their ENIs.
resource "aws_vpc_security_group_ingress_rule" "mwaa_self" {
  security_group_id            = aws_security_group.mwaa.id
  description                  = "Amazon MWAA inbound access"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.mwaa.id
}
resource "aws_vpc_security_group_ingress_rule" "mwaa_https" {
  for_each = toset(var.webserver_ingress_cidr_blocks)

  security_group_id = aws_security_group.mwaa.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}
resource "aws_vpc_security_group_egress_rule" "mwaa_all" {
  security_group_id = aws_security_group.mwaa.id
  description       = "Amazon MWAA outbound access"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Environment -----------------------------------------------------------------------------------

resource "aws_mwaa_environment" "mwaa" {
  name                  = var.name
  airflow_version       = var.airflow_version
  environment_class     = var.environment_class
  min_workers           = var.min_workers
  max_workers           = var.max_workers
  webserver_access_mode = var.webserver_access_mode
  execution_role_arn    = aws_iam_role.execution.arn
  source_bucket_arn     = aws_s3_bucket.source.arn
  dag_s3_path           = var.dag_s3_path
  # Pinned by version, unlike the upstream module, which ignored changes to this attribute. Ignoring
  # it means an edited requirements.txt lands in S3 and is never installed; pinning it means the
  # change shows in plan as an environment update - which takes MWAA 20-30 minutes, and is the honest
  # cost of changing a requirement.
  requirements_s3_path           = aws_s3_object.requirements.key
  requirements_s3_object_version = aws_s3_object.requirements.version_id

  # The caller's options plus the secrets backend, which the caller is not allowed to set (see the
  # variable's validation), so the merge order cannot matter.
  airflow_configuration_options = merge(var.airflow_configuration_options, local.secrets_backend_options)

  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = var.subnet_ids
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = var.log_level
    }
    scheduler_logs {
      enabled   = true
      log_level = var.log_level
    }
    task_logs {
      enabled   = true
      log_level = var.log_level
    }
    webserver_logs {
      enabled   = true
      log_level = var.log_level
    }
    worker_logs {
      enabled   = true
      log_level = var.log_level
    }
  }

  # MWAA requires the bucket's versioning and public access block, and the environment's first act
  # is to assume the role and read the bucket - none of which the references above order (rules.md
  # D-1). The egress rule is here because the group starts with none: the AWS provider removes the
  # default allow-all egress rule when it creates a group, and without a way out the environment
  # cannot reach S3, SQS or CloudWatch.
  depends_on = [
    aws_iam_role_policy.execution,
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_public_access_block.source,
    aws_s3_bucket_policy.source,
    aws_vpc_security_group_ingress_rule.mwaa_self,
    aws_vpc_security_group_egress_rule.mwaa_all,
  ]
}
