data "aws_region" "current" {}

module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair doesn't reference any network output, so without this the
  # network module's own resources (NAT gateways, routes, etc.) would have
  # no ordering relationship with it at all (rules.md #27).
  depends_on = [module.network]
}

module "bastion_ec2" {
  source = "./modules/bastion_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.public_subnet_a_id
  key_name      = module.key_pair.key_name
  instance_type = var.bastion_instance_type

  depends_on = [module.network]
}

module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  vpc_id     = module.network.vpc_id
  subnet_ids = [module.network.public_subnet_a_id, module.network.public_subnet_b_id]

  depends_on = [module.network]
}

module "app_asg" {
  source = "./modules/app_asg"

  vpc_id                          = module.network.vpc_id
  subnet_ids                      = [module.network.private_subnet_a_id, module.network.private_subnet_b_id]
  key_name                        = module.key_pair.key_name
  instance_type                   = var.app_instance_type
  bastion_security_group_id       = module.bastion_ec2.security_group_id
  load_balancer_security_group_id = module.application_load_balancer.security_group_id
  target_group_arns               = [module.application_load_balancer.target_group_arn]
  min_size                        = var.app_min_size
  max_size                        = var.app_max_size
  prefix                          = var.prefix

  depends_on = [module.network, module.bastion_ec2, module.application_load_balancer]
}
