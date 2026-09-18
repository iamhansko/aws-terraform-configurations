data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# The key encrypting the domain's data at rest. Its own resource in this module
# rather than a separate one: the domain cannot be created without it, and nothing
# else in the project uses it (rules.md C-2).
resource "aws_kms_key" "opensearch" {
  description             = "Encrypts data at rest in the ${var.domain_name} OpenSearch domain"
  is_enabled              = true
  enable_key_rotation     = var.enable_key_rotation
  deletion_window_in_days = var.kms_deletion_window_in_days

  tags = {
    Name = "${var.domain_name}-kms"
  }
}
resource "aws_opensearch_domain" "opensearch" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.instance_type
    instance_count           = var.instance_count
    dedicated_master_enabled = var.dedicated_master_enabled
    zone_awareness_enabled   = var.zone_awareness_enabled
    warm_enabled             = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.volume_type
    volume_size = var.volume_size
    # gp3 accepts an explicit IOPS figure; gp2 derives it from the volume size and
    # rejects one, so it is dropped rather than left to fail at apply.
    iops = var.volume_type == "gp3" ? var.volume_iops : null
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.opensearch.key_id
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = var.tls_security_policy
  }

  # Fine-grained access control with an internal user database, which is what lets
  # the OpenSearch Dashboards login work with a username and password. Required by
  # AWS whenever advanced security is on: enforce_https and node_to_node_encryption
  # above are preconditions, and the domain create call is rejected without them.
  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.master_user_name
      master_user_password = var.master_user_password
    }
  }

  advanced_options = var.advanced_options

  software_update_options {
    auto_software_update_enabled = var.auto_software_update_enabled
  }

  # Left as the _monolithic template had it: any principal in the account may call
  # the HTTP API, with fine-grained access control above deciding what they can
  # actually do. It is wide, and it is the reason this domain must not be reused
  # outside a demo - the Resource is domain/* rather than this domain, so the policy
  # would cover any domain in the account.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.access_policy_principal
      }
      Action   = "es:ESHttp*"
      Resource = "arn:aws:es:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:domain/${var.domain_name}/*"
    }]
  })

  tags = {
    Name = var.domain_name
  }
}
