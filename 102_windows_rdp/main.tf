data "aws_region" "current" {}
# The AMI id, from the public parameter AWS maintains per Windows release.
#
# insecure_value rather than value: the provider marks value sensitive for every
# parameter whatever its type, and a sensitive value cannot be used as an
# instance's ami attribute without nonsensitive(). insecure_value is the
# provider's own accessor for a parameter that is not a secret, and a public AMI
# id is not one.
#
# Declared in the root and the resolved id passed into the module, so the module
# takes an ami- id and does not have to know where it came from (rules.md B-6).
# It also keeps the lookup out of a module carrying depends_on, which would defer
# the read to apply (rules.md D-6) - harmless for an AMI id, but there is no
# reason to take it on.
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block          = var.vpc_cidr_block
  vpc_name                = "${var.project_name}-vpc"
  internet_gateway_name   = "${var.project_name}-igw"
  public_subnet_name      = "${var.project_name}-public"
  public_route_table_name = "${var.project_name}-public-rt"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # This module uses nothing from network and does not need a VPC to create a key
  # pair. It waits anyway, because the rule is that a root with a network module
  # has no module starting before that module finishes - an exception here would
  # mean the next reader has to decide per module whether the omission was
  # reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "app_secret" {
  source = "./modules/app_secret"

  name_prefix             = "${var.project_name}-workshop-user-"
  username                = var.workshop_username
  recovery_window_in_days = var.secret_recovery_window_in_days

  # Nothing to do with the VPC either; same reasoning as key_pair (rules.md D-3).
  depends_on = [module.network]
}
module "cognito_user_pool" {
  source = "./modules/cognito_user_pool"

  name        = "${var.project_name}-user-pool"
  client_name = "${var.project_name}-client"

  # A Cognito pool is a regional resource with no network attachment at all, so
  # this edge exists purely to keep the root free of exceptions (rules.md D-3).
  depends_on = [module.network]
}
module "dynamodb_tables" {
  source = "./modules/dynamodb_tables"

  tables      = var.dynamodb_tables
  name_prefix = "${var.project_name}-"

  # As above: DynamoDB tables are not in the VPC. Also the reason this is one
  # module rather than six instantiations of a single-table module - six module
  # blocks would mean six copies of this edge, and the module explains the rest
  # of that decision.
  depends_on = [module.network]
}
module "windows_ec2" {
  source = "./modules/windows_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name              = var.project_name
  instance_type              = var.instance_type
  root_volume_size           = var.root_volume_size
  security_group_name        = "${var.project_name}-sg"
  security_group_description = "Security group for the Windows workshop instance reached over RDP"
  ingress_cidr_blocks        = var.rdp_ingress_cidr_blocks

  aws_region        = data.aws_region.current.region
  workshop_username = var.workshop_username
  git_clone_url     = var.git_clone_url
  git_clone_branch  = var.git_clone_branch

  # Everything the setup script needs at boot, injected as ids and names rather
  # than discovered by the module (rules.md B-6). The module does not know that
  # the secret, the pool and the tables are built in this same root, which is why
  # the ordering below has to be stated rather than inferred.
  secret_id             = module.app_secret.secret_id
  cognito_user_pool_id  = module.cognito_user_pool.user_pool_id
  cognito_user_pool_arn = module.cognito_user_pool.user_pool_arn
  cognito_client_id     = module.cognito_user_pool.client_id
  dynamodb_table_names  = module.dynamodb_tables.table_names

  item_images_service_url = var.item_images_service_url
  kiro_installer_url      = var.kiro_installer_url
  additional_user_data    = var.additional_user_data

  # Value references order this after the resources that produced each value and
  # nothing else, which is not enough for any of the four (rules.md D-2):
  #
  #   - module.app_secret.secret_id is the secret container. The password lives
  #     in a separate aws_secretsmanager_secret_version, and the script's first
  #     real action is Get-SECSecretValue - boot before the version exists and it
  #     raises ResourceNotFoundException inside the try block, so no workshop
  #     account is created and apply still reports success. The conversion needed
  #     a resource-level depends_on naming that version; a module-level
  #     depends_on means "after every resource in the module", so it covers the
  #     version without this root reaching inside.
  #   - module.network.public_subnet_a_id orders this after that one subnet, not
  #     after the route to the internet gateway. The script starts reaching the
  #     PowerShell Gallery within seconds of launch, and losing that race leaves
  #     the whole setup unrun - the same end state as the missing egress rule the
  #     windows_ec2 module describes, except intermittent (rules.md D-3).
  #   - the Cognito and DynamoDB values are only baked into a launcher script, so
  #     they are the two that would survive a race. They are listed for
  #     uniformity and because destroy runs this in reverse: the instance goes
  #     before the tables and the pool it was told to use.
  depends_on = [
    module.network,
    module.key_pair,
    module.app_secret,
    module.cognito_user_pool,
    module.dynamodb_tables,
  ]
}
