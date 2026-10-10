data "aws_region" "current" {}
# CloudFront's origin-facing addresses, so the instance can admit the distribution without being open to the
# world. In the root, where nothing defers it to apply (rules.md D-6).
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_origin_facing_prefix_list_name
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
  # rather than the chmod 666 on /var/run/docker.sock it used (rules.md H-1 describes the same fix).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
module "lambda_edge_functions" {
  source = "./modules/lambda_edge_functions"
  # us-east-1, where Lambda@Edge has to live, while everything else stays in aws_region (rules.md I-3).
  providers = {
    aws = aws.us_east_1
  }

  name_prefix    = var.project_name
  runtime        = var.lambda_runtime
  delete_timeout = var.lambda_delete_timeout
  functions = {
    s3-origin-lambda-function = {
      source_file = "${path.root}/lambda_src/s3_origin/index.js"
      description = "Viewer request on the S3 origin"
    }
    ec2-origin-lambda-function = {
      source_file = "${path.root}/lambda_src/ec2_origin/index.js"
      description = "Viewer request on the EC2 origin"
    }
  }

  depends_on = [module.network]
}
module "distribution" {
  source = "./modules/edge_distribution"

  comment = "Lambda@Edge on an S3 origin and an EC2 origin"
  # Both from the instance module, so the origin's port and path are the ones nginx actually serves
  # (rules.md B-5).
  ec2_origin_domain_name = module.vscode_ec2.public_dns
  ec2_origin_http_port   = module.vscode_ec2.http_port
  ec2_path_prefix        = module.vscode_ec2.path_prefix
  s3_origin_lambda_arn   = module.lambda_edge_functions.qualified_arns["s3-origin-lambda-function"]
  ec2_origin_lambda_arn  = module.lambda_edge_functions.qualified_arns["ec2-origin-lambda-function"]

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
      description = "The _monolithic template's DistributionDomainName output. The viewer-request function logs the request and passes it on, so this reaches code-server through CloudFront"
      value       = module.distribution.ec2_url
    }
    distribution_root_url = {
      order       = 2
      title       = "CloudFront distribution - S3 origin"
      description = "The default behaviour: the Hello World page in the bucket, after the S3 origin function has logged the request"
      value       = module.distribution.url
    }
    request_command = {
      order       = 4
      title       = "1. Send a request through the S3 origin function"
      description = "The function runs before the cache and the origin on every viewer request"
      value       = "curl -s ${module.distribution.url}"
    }
    function_logs_command = {
      order       = 5
      title       = "2. Find the function's log"
      description = "A Lambda@Edge replica logs to /aws/lambda/us-east-1.<function> in the region of the edge location that served the request - not in us-east-1, and not necessarily in this region. This lists the regions that have one"
      value       = "for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do aws logs describe-log-groups --region $r --log-group-name-prefix ${module.lambda_edge_functions.log_group_names["s3-origin-lambda-function"]} --query 'logGroups[].logGroupName' --output text | sed \"s|^|$r |\"; done | grep -v ' $'"
    }
    function_versions = {
      order       = 6
      title       = "Associated function versions"
      description = "The distribution runs these exact versions. A code change publishes a new version and the distribution is updated to it, which redeploys every edge location"
      value       = jsonencode(module.lambda_edge_functions.qualified_arns)
    }
    distribution_status_command = {
      order       = 7
      title       = "Distribution status"
      description = "InProgress for several minutes after every change; the edge serves the previous version until it is Deployed"
      value       = module.distribution.status_command
    }
    teardown_note = {
      order       = 8
      title       = "Before terraform destroy"
      description = "The functions cannot be deleted until CloudFront has removed their edge replicas, which happens some time after the distribution is gone. Destroy waits up to lambda_delete_timeout for that; if it still fails with replicated function, run terraform destroy again later"
      value       = "terraform destroy"
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
    ["# CloudFront Lambda@Edge", ""],
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
