data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
# Both instances come from one module rather than a module each: they differ only
# in which subnet they sit in, who may reach them, and whether they run the app.
# That difference is the whole point of the project, and expressing it as
# arguments is what makes it readable side by side.
module "public_ec2" {
  source = "./modules/ec2_instance"

  name                        = "${var.prefix}-public-ec2"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.instance_type
  associate_public_ip_address = true
  security_group_name         = "${var.prefix}-public-ec2-sg"
  security_group_description  = "Security group for the public EC2 instance running the demo app"
  # One entry per rule, each behind its own switch, so turning SSH on cannot
  # also widen the app rule. Keys are literals, which is what for_each needs
  # (rules.md B-8).
  ingress_cidr_rules = merge(
    var.allow_app_from_anywhere ? { app_from_anywhere = { port = var.app_port, cidr_block = "0.0.0.0/0" } } : {},
    var.allow_ssh_from_anywhere ? { ssh_from_anywhere = { port = 22, cidr_block = "0.0.0.0/0" } } : {},
  )
  # The _monolithic template ran "npm run start" in the foreground of the user
  # data script, after cfn-signal. That never returns, so cloud-init never
  # finished and the app died with the first reboot. A systemd unit starts it
  # instead: user data completes, and the app comes back on its own.
  user_data = <<-EOT
    #!/bin/bash
    set -x
    dnf update -yq
    dnf install -yq git
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${var.nvm_version}/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    nvm install ${var.app_node_major_version}
    git clone ${var.app_repository_url} $HOME/app
    cd $HOME/app
    npm install
    # Resolve the interpreter now, while nvm is loaded, so the unit below does
    # not have to source nvm from a non-login shell.
    echo "NODE_BIN=$(dirname $(nvm which ${var.app_node_major_version}))" > $HOME/app/.node-path
    EOF
    . /home/ec2-user/app/.node-path
    cat <<EOF > /etc/systemd/system/demo-app.service
    [Unit]
    Description=Demo app
    After=network-online.target
    Wants=network-online.target
    [Service]
    Type=simple
    User=ec2-user
    WorkingDirectory=/home/ec2-user/app
    Environment=PATH=$NODE_BIN:/usr/local/bin:/usr/bin:/bin
    Environment=PORT=${var.app_port}
    ExecStart=$NODE_BIN/npm run start
    Restart=always
    [Install]
    WantedBy=multi-user.target
    EOF
    systemctl daemon-reload
    systemctl enable --now demo-app
    EOT

  depends_on = [module.network]
}
module "private_ec2" {
  source = "./modules/ec2_instance"

  name                        = "${var.prefix}-private-ec2"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.private_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.instance_type
  associate_public_ip_address = false
  security_group_name         = "${var.prefix}-private-ec2-sg"
  security_group_description  = "Security group for the private EC2 instance, reachable only from the public instance"
  # No CIDR rules at all: the only way in is from the public instance's security
  # group. Keyed by label because that ID is another module's output and unknown
  # at plan time, so keying by the value itself would make for_each keys that
  # cannot be resolved (rules.md B-8). The module is handed an ID and never
  # learns whose it is (rules.md B-6).
  ingress_source_group_rules = {
    ssh_from_public_ec2 = { port = 22, security_group_id = module.public_ec2.security_group_id }
    app_from_public_ec2 = { port = var.app_port, security_group_id = module.public_ec2.security_group_id }
  }

  depends_on = [module.network]
}
