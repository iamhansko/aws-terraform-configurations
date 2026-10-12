data "aws_region" "current" {}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
  depends_on = [module.network]
}
module "template_bucket" {
  source = "./modules/template_bucket"

  template_body = file("${path.root}/${var.template_path}")

  depends_on = [module.network]
}
module "presigned_url" {
  source = "./modules/presigned_url_function"

  # CloudFormation generated this name; Terraform requires one, so it comes from the project name as the
  # _monolithic template derived it from the stack name.
  function_name      = "${var.project_name}-lambda-function"
  bucket_name        = module.template_bucket.bucket_name
  object_key         = module.template_bucket.template_key
  object_arn         = module.template_bucket.template_object_arn
  expires_in_seconds = var.presigned_url_expires_in

  # The _monolithic template ordered the presign after the instance (depends_on = [aws_instance.vs_code_ec2]),
  # because the instance's userdata was what uploaded the object - and that ordering waited for the instance
  # to be running, not for the upload. object_key now comes out of the upload itself, so the URL is signed
  # after the object exists. module.network is for the uniform reason (rules.md D-3).
  depends_on = [module.network]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # The region only. The _monolithic template's userdata also wrote template.yaml with echo and uploaded it
  # with aws s3 cp; Terraform uploads it now, and the README's steps show how to do the same by hand.
  additional_user_data = <<-EOT
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  template_s3_uri = "s3://${module.template_bucket.bucket_name}/${module.template_bucket.template_key}"
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it (rules.md H-2). The _monolithic template's README was a heredoc of shell commands in
  # userdata; the same walkthrough is here, as entries, with the bucket name and the lifetime filled in.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. The commands below run from its terminal, with its instance role"
      value       = module.vscode_ec2.vscode_url
    }
    presigned_url = {
      order       = 2
      title       = "S3 object presigned URL"
      description = "A GET for the template, signed by the Lambda function's role. It works from anywhere without credentials, for at most presigned_url_expires_in seconds - and less if the role session that signed it expires first, which is when S3 answers Request has expired"
      value       = module.presigned_url.url
    }
    fetch_presigned_url_command = {
      order       = 3
      title       = "1. Fetch the template through the URL"
      description = "No credentials involved. 200 while the URL is valid, 403 with Request has expired once it is not"
      value       = "curl -s -o /dev/null -w '%%{http_code}\\n' '${module.presigned_url.url}'"
    }
    create_stack_command = {
      order       = 4
      title       = "2. Create a stack from the URL"
      description = "CloudFormation fetches the template through the URL, so this works from any account. Run it after the URL has expired to see the error in the screenshots"
      value       = "aws cloudformation create-stack --stack-name ${var.stack_name} --template-url '${module.presigned_url.url}'"
    }
    workbench_presign_command = {
      order       = 5
      title       = "3. Presign it again, with the workbench's own credentials"
      description = "The same operation as the Lambda function, signed with this instance's role session instead. Those credentials rotate every few hours, so the same rule applies: the URL lasts as long as the shorter of --expires-in and the session"
      value       = "TEMPLATE_URL=$(aws s3 presign ${local.template_s3_uri} --expires-in ${var.presigned_url_expires_in}) && echo $TEMPLATE_URL"
    }
    workbench_update_stack_command = {
      order       = 6
      title       = "4. Update the stack from that URL"
      description = "The _monolithic README's last step. update-stack reports No updates are to be performed when the template is unchanged, which still proves CloudFormation could read it"
      value       = "aws cloudformation update-stack --stack-name ${var.stack_name} --template-url \"$TEMPLATE_URL\""
    }
    regenerate_command = {
      order       = 7
      title       = "5. A fresh Lambda-signed URL"
      description = "Run from where terraform runs, not from the workbench. The invocation runs once at create and its result is kept in state, so an expired URL stays expired until it is replaced"
      value       = "terraform apply -replace='module.presigned_url.${module.presigned_url.invocation_address}'"
    }
    template_s3_uri = {
      order       = 8
      title       = "Template object"
      description = "Where the template is stored. The bucket is private; the URL is the only way in from outside the account"
      value       = local.template_s3_uri
    }
    signer_role_arn = {
      order       = 9
      title       = "Role that signed the URL"
      description = "S3 checks this role's permissions when the URL is used. It may read this one object and nothing else, so a URL it signs can do nothing else either"
      value       = module.presigned_url.role_arn
    }
    delete_stack_command = {
      order       = 10
      title       = "Before terraform destroy"
      description = "The stack is created by hand, so terraform destroy does not know about it. Delete it here or it outlives the project - the VPC it made stays behind"
      value       = "aws cloudformation delete-stack --stack-name ${var.stack_name}"
    }
    private_key_command = {
      order       = 11
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# Presigned S3 objects", ""],
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
