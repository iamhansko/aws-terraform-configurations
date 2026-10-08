data "aws_region" "current" {}
# insecure_value rather than value: the provider marks value sensitive for every
# parameter regardless of type, and a sensitive value cannot be used as an
# instance's ami without nonsensitive(). A public AMI id is not a secret.
data "aws_ssm_parameter" "ami_id" {
  name = var.ami_ssm_parameter_name
}
locals {
  # Everything this variant does beyond ubuntu_24_04, injected into the userdata
  # rather than forked into a second copy of the module (rules.md B-4).
  #
  # Position matters more than content here. The module places this after xrdp is
  # installed and before ubuntu-desktop, because installing the desktop hands the
  # primary interface from systemd-networkd to NetworkManager and the link and
  # DNS stay down until the instance reboots. A git clone, a pipe from
  # raw.githubusercontent.com and whatever init.sh downloads all need the network,
  # so none of it can run after the desktop.
  application_setup = <<-EOT
    %{if var.kiro_install_script_url != null~}
    # Third-party installer piped into root's shell, as the template had it. See
    # the kiro_install_script_url variable for what is being trusted.
    curl -fsSL ${var.kiro_install_script_url} | bash
    %{endif~}

    su - ubuntu <<'SPIRITOFKIRO'
    set -x
    cd /home/ubuntu/Desktop
    git clone ${var.application_repository_url} spirit-of-kiro
    cd spirit-of-kiro
    git checkout ${var.application_repository_ref}

    # The credential helper is written once by the module, at
    # ~/Desktop/scripts/env.sh, and copied in here rather than written a second
    # time. The template inlined the same script again at this point, which left
    # two copies of it to keep in step (rules.md B-5 makes the same argument for
    # values crossing a module boundary).
    #
    # init.sh needs the credentials exported into its own environment, which is
    # why this is sourced rather than just run - the template did the same.
    cp /home/ubuntu/Desktop/scripts/env.sh ./scripts/env.sh
    chmod +x ./scripts/env.sh ./scripts/init.sh
    source ./scripts/env.sh
    ./scripts/init.sh
    SPIRITOFKIRO
  EOT
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

  # Nothing here comes from network and a key pair does not need a VPC. It waits
  # anyway, so that no module in this root starts before network finishes and a
  # reader does not have to judge each omission (rules.md D-3).
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
  additional_user_data       = local.application_setup

  # vpc_id and subnet_id order this after the VPC and that one subnet only. The
  # route to the internet gateway is not among them, and cloud-init starts
  # cloning and apt-installing within seconds of the launch, so losing that race
  # leaves the desktop, xrdp and the application all uninstalled (rules.md D-3).
  depends_on = [module.network, module.key_pair]
}
