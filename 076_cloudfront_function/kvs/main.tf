data "aws_region" "current" {}
# CloudFront's origin-facing addresses, so the instance can admit the distribution without being open to the
# world. In the root, where nothing defers it to apply (rules.md D-6).
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_origin_facing_prefix_list_name
}
# Suffix for the names CloudFront makes unique per account rather than per region.
resource "random_id" "suffix" {
  byte_length = 4
}
locals {
  function_names = {
    s3  = "S3OriginFunction-${random_id.suffix.hex}"
    ec2 = "Ec2OriginFunction-${random_id.suffix.hex}"
  }
}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
# The workbench is also the distribution's EC2 origin: nginx on 80 proxies the code path to code-server. The
# _monolithic template's InboundFromAnywhere parameter, True by default, also opened 80 to 0.0.0.0/0; it is not
# carried over. code-server runs without authentication, so the port admits CloudFront's origin-facing
# addresses only and the distribution is the way in.
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                    = "vscode"
  vpc_id                  = module.network.vpc_id
  subnet_id               = module.network.public_subnet_a_id
  key_name                = module.key_pair.key_name
  instance_type           = var.vscode_instance_type
  code_server_version     = var.code_server_version
  security_group_name     = "vscode-sg"
  path_prefix             = var.code_path_prefix
  ingress_prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  marker_file_path        = var.marker_file_path
  # docker, as the _monolithic template installed it - with the group membership and a code-server restart
  # rather than the chmod 666 on /var/run/docker.sock it used, which handed the root-equivalent socket to
  # every local user (rules.md H-1 describes the same fix).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
module "s3_origin_function" {
  source = "./modules/cloudfront_function"

  name                 = local.function_names.s3
  comment              = "S3 Origin"
  code                 = file("${path.root}/functions/s3_origin.js")
  key_value_store_name = var.create_key_value_stores ? "S3OriginKeyValueStore-${random_id.suffix.hex}" : null

  depends_on = [module.network]
}
module "ec2_origin_function" {
  source = "./modules/cloudfront_function"

  name                 = local.function_names.ec2
  comment              = "EC2 Origin"
  code                 = file("${path.root}/functions/ec2_origin.js")
  key_value_store_name = var.create_key_value_stores ? "Ec2OriginKeyValueStore-${random_id.suffix.hex}" : null

  depends_on = [module.network]
}
module "distribution" {
  source = "./modules/edge_distribution"

  comment = "CloudFront Functions on an S3 origin and an EC2 origin"
  # Both from the instance module, so the origin's port and path are the ones nginx actually serves
  # (rules.md B-5).
  ec2_origin_domain_name  = module.vscode_ec2.public_dns
  ec2_origin_http_port    = module.vscode_ec2.http_port
  ec2_path_prefix         = module.vscode_ec2.path_prefix
  s3_origin_function_arn  = module.s3_origin_function.arn
  ec2_origin_function_arn = module.ec2_origin_function.arn

  depends_on = [module.network]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    distribution_domain_name = {
      order       = 1
      title       = "CloudFront distribution - EC2 origin path"
      description = "The _monolithic template's DistributionDomainName output. The viewer-request function on this path answers every request itself with a 302 to aws.amazon.com/cloudfront, so code-server is never reached through it until the function is changed"
      value       = module.distribution.ec2_url
    }
    distribution_root_url = {
      order       = 2
      title       = "CloudFront distribution - S3 origin"
      description = "The default behaviour. Its function also answers with the 302, so the Hello World page in the bucket is never served until that function is changed"
      value       = module.distribution.url
    }
    function_redirect_command = {
      order       = 4
      title       = "1. Watch the function answer"
      description = "The response comes from the edge, not from either origin: a 302 carrying the cloudfront-functions header the function sets"
      value       = "curl -sI ${module.distribution.ec2_url} | grep -iE '^(HTTP|location|cloudfront-functions|x-cache)'"
    }
    s3_function_test_command = {
      order       = 5
      title       = "2. Run the S3 origin function without the distribution"
      description = "test-function evaluates the LIVE code against a sample event and reports its compute utilization"
      value       = module.s3_origin_function.test_command
    }
    ec2_function_describe_command = {
      order       = 6
      title       = "3. The EC2 origin function's LIVE stage"
      description = "Edit functions/ec2_origin.js to return event.request instead of the 302, apply, and the code path reaches code-server through CloudFront"
      value       = module.ec2_origin_function.describe_command
    }
    key_value_stores = {
      order       = 7
      title       = "Key value stores"
      description = "The stores associated with each function, or none in the default variant. The functions here do not read them yet - a function reads its store through import cf from 'cloudfront' and cf.kvs()"
      value       = var.create_key_value_stores ? "S3 origin: ${module.s3_origin_function.key_value_store_arn}\nEC2 origin: ${module.ec2_origin_function.key_value_store_arn}" : "(none in this variant)"
    }
    distribution_status_command = {
      order       = 8
      title       = "Distribution status"
      description = "InProgress for several minutes after every change; the edge serves the previous configuration until it is Deployed"
      value       = module.distribution.status_command
    }
    private_key_command = {
      order       = 9
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# CloudFront Function with Key Value Store", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into (rules.md B-5).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
  depends_on = [module.vscode_ec2]
}
