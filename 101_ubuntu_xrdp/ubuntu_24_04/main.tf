data "aws_region" "current" {}
# The AMI id, from the public parameter Canonical maintains per release.
#
# insecure_value rather than value: the provider marks value sensitive for every
# parameter regardless of its type, and a sensitive value cannot be used for an
# instance's ami attribute without wrapping it in nonsensitive(). insecure_value
# is the provider's own accessor for a parameter that is not a secret, and a
# public AMI id is not one.
#
# This data source is declared in the root and the id passed into the module, so
# that the module takes an ami- id and does not have to know where it came from
# (rules.md B-6). It also keeps the lookup out of a module that carries
# depends_on, which would defer the read to apply (rules.md D-6) - not a problem
# for an AMI id, but there is no reason to take it on.
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

  # This module uses nothing from network, and it does not need to wait for a
  # VPC to create a key pair. It waits anyway, because the rule is that a root
  # with a network module has no module starting before that module finishes -
  # an exception here would mean the next reader has to decide per module
  # whether the omission was reasoned or forgotten (rules.md D-3).
  depends_on = [module.network]
}
module "ubuntu_ec2" {
  source = "./modules/ubuntu_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name              = var.project_name
  instance_type              = var.instance_type
  password                   = var.password
  ingress_cidr_blocks        = var.rdp_ingress_cidr_blocks
  security_group_name        = "${var.project_name}-sg"
  security_group_description = "Security group for the Ubuntu desktop instance reached over RDP"
  root_volume_size           = var.root_volume_size

  # vpc_id and subnet_id order this after the VPC and that one subnet, and
  # nothing else in the network module. The route to the internet gateway is one
  # of the resources that ordering misses, and cloud-init starts apt within
  # seconds of the launch - so losing that race leaves the desktop and xrdp
  # uninstalled, which is the same end state as the missing egress rule the
  # ubuntu_ec2 module describes, except intermittent (rules.md D-3).
  depends_on = [module.network, module.key_pair]
}
