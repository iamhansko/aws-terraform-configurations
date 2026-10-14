data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Discovery stays at the root so it runs during plan. An empty result is now a creation decision rather than
# an error; the identity_center_instance module receives only plan-known existing identifiers (rules.md D-6).
data "aws_ssoadmin_instances" "current" {}

# Read the public AMI parameter at the root during plan and inject the resolved ID into the EC2 component.
data "aws_ssm_parameter" "bootstrap_ami" {
  name = var.bootstrap_ami_ssm_parameter_name
}

locals {
  existing_identity_center_instance_arns = tolist(data.aws_ssoadmin_instances.current.arns)
  existing_identity_store_ids            = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)
  existing_identity_center_instance_arn  = try(one(local.existing_identity_center_instance_arns), null)
  existing_identity_store_id             = try(one(local.existing_identity_store_ids), null)
  identity_center_instance_arn           = module.identity_center_instance.instance_arn
  identity_store_id                      = module.identity_center_instance.identity_store_id
  availability_zone                      = var.availability_zone != null ? var.availability_zone : try(data.aws_availability_zones.available.names[0], null)
  bootstrap_name                         = "${var.name_prefix}-bootstrap"
}

resource "terraform_data" "prerequisites" {
  lifecycle {
    precondition {
      condition     = var.expected_account_id == null || data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "The active AWS credentials do not belong to expected_account_id. Load the intended account credentials before planning or applying this root."
    }

    precondition {
      condition = (
        length(local.existing_identity_center_instance_arns) <= 1 &&
        length(local.existing_identity_store_ids) <= 1 &&
        length(local.existing_identity_center_instance_arns) == length(local.existing_identity_store_ids)
      )
      error_message = "IAM Identity Center discovery must return at most one consistently paired instance ARN and Identity Store ID."
    }

    precondition {
      condition     = try(contains(data.aws_availability_zones.available.names, local.availability_zone), false)
      error_message = "availability_zone must be one of the currently available zones in the provider region, or null to select the first available zone."
    }

    precondition {
      condition     = can(regex("^ami-[0-9a-f]+$", data.aws_ssm_parameter.bootstrap_ami.insecure_value))
      error_message = "bootstrap_ami_ssm_parameter_name must resolve to a syntactically valid AMI ID."
    }
  }
}

module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  availability_zone        = local.availability_zone
  vpc_name                 = "${var.name_prefix}-vpc"
  internet_gateway_name    = "${var.name_prefix}-igw"
  public_subnet_name       = "${var.name_prefix}-public-subnet"
  public_route_table_name  = "${var.name_prefix}-public-rt"
  private_subnet_name      = "${var.name_prefix}-private-subnet"
  private_route_table_name = "${var.name_prefix}-private-rt"
  nat_gateway_name         = "${var.name_prefix}-nat"
  nat_eip_name             = "${var.name_prefix}-nat-eip"

  depends_on = [terraform_data.prerequisites]
}

module "identity_center_instance" {
  source = "./modules/identity_center_instance"

  existing_instance_arn      = local.existing_identity_center_instance_arn
  existing_identity_store_id = local.existing_identity_store_id

  # Root data has already made the create/reuse decision during plan. Keeping this module after network also
  # satisfies the repository-wide module ordering rule without delaying discovery itself (rules.md D-3/D-6).
  depends_on = [module.network]
}

module "kiro_user" {
  source = "./modules/identity_center_user"

  identity_store_id = local.identity_store_id
  user_name         = var.user_name
  display_name      = var.user_display_name
  given_name        = var.user_given_name
  family_name       = var.user_family_name
  email             = var.user_email

  depends_on = [module.identity_center_instance]
}

module "kiro_bootstrap" {
  source = "./modules/kiro_bootstrap_ec2"

  name                                 = local.bootstrap_name
  vpc_id                               = module.network.vpc_id
  subnet_id                            = module.network.private_subnet_a_id
  security_group_name                  = "${local.bootstrap_name}-sg"
  ami_id                               = data.aws_ssm_parameter.bootstrap_ami.insecure_value
  instance_type                        = var.bootstrap_instance_type
  aws_region                           = data.aws_region.current.region
  identity_center_instance_arn         = local.identity_center_instance_arn
  user_id                              = module.kiro_user.user_id
  disable_mfa                          = var.disable_mfa
  acknowledge_mfa_disable              = var.acknowledge_instance_wide_mfa_disable
  password_parameter_name              = var.password_parameter_name
  create_kiro_subscription             = var.create_kiro_subscription
  acknowledge_subscription_cost        = var.acknowledge_monthly_kiro_subscription
  kiro_region                          = var.kiro_region
  kiro_subscription_plan               = var.kiro_subscription_plan
  subscribe_attempts                   = var.subscribe_attempts
  additional_iam_policy_arns           = var.additional_iam_policy_arns
  stop_after_bootstrap                 = var.stop_after_bootstrap
  bootstrap_timeout_seconds            = var.bootstrap_timeout_seconds
  subscription_cleanup_generation      = var.subscription_cleanup_generation
  subscription_cleanup_timeout_seconds = var.subscription_cleanup_timeout_seconds

  depends_on = [module.network]
}

# CloudFormation returned the password after its EC2 CreationPolicy completed. This read follows the whole
# bootstrap module for the same ordering and exposes the requested compatibility output as sensitive. Unlike
# the write-only resource argument, a decrypted data source value is stored in Terraform state.
data "aws_ssm_parameter" "kiro_password" {
  name            = module.kiro_bootstrap.password_parameter_name
  with_decryption = true

  depends_on = [module.kiro_bootstrap]
}

# Preserve state addresses for installations that used the partially modularized configuration before the
# completion gate and stop operation moved into the bootstrap component.
moved {
  from = aws_ssm_association.kiro_bootstrap_complete
  to   = module.kiro_bootstrap.aws_ssm_association.bootstrap_complete
}

moved {
  from = aws_ec2_instance_state.kiro_bootstrap
  to   = module.kiro_bootstrap.aws_ec2_instance_state.bootstrap
}
