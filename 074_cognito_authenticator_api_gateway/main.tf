data "aws_region" "current" {}
# Suffix for the hosted domain prefix, which is unique across every AWS account in the region.
resource "random_id" "domain_suffix" {
  byte_length = 4
}
locals {
  workshop_dir = "/home/ec2-user/workshop"
  # Read back out of the module it was passed into, so every step waits on the directory the bootstrap
  # actually writes to (rules.md B-5).
  marker = module.vscode_ec2.marker_file_path
}
module "network" {
  source = "./modules/network"
}
module "key_pair" {
  source = "./modules/key_pair"

  # Uses nothing from network and waits anyway, so the root has no exception to reason about (rules.md D-3).
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
  # The workshop toolchain, as the _monolithic template installed it: Node.js and esbuild for the web app's
  # build, gettext for the envsubst in it, zip for its package, and docker.
  #
  # Not SAM CLI, which the template also installed. Its one use was deploying the web app's SAM template, and
  # that template is Terraform resources now.
  #
  # docker with the group membership and a code-server restart rather than the chmod 666 on
  # /var/run/docker.sock the template used, which handed the root-equivalent socket to every local user
  # (rules.md H-1 describes the same fix).
  additional_user_data = <<-EOT
    dnf install -yq docker nodejs gettext unzip zip
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    npm install -g esbuild
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
module "workshop_files" {
  source = "./modules/workshop_files"

  bucket_prefix = "cognito-authenticator-files-"
  source_dir    = "${path.root}/workshop"

  depends_on = [module.network]
}
# --- The web app --------------------------------------------------------------------------------------------
#
# The workshop's cognito-web SAM template, as Terraform resources: the function, its REST API and its stage.
# Its package is built on the workbench (webapp_build below) and its checksum read back from S3 once
# webapp_package_waiter has seen it there, which is what holds the function until the package exists - the API
# and its URL do not wait.
module "web_app" {
  source = "./modules/cognito_web_app"

  name           = var.webapp_name
  package_sha256 = data.aws_s3_object.webapp_package.checksum_sha256

  depends_on = [module.network]
}
locals {
  # The callback page itself, with the trailing slash: this project's SAM template published exactly this as
  # CognitoWebAppURL (.../Prod/callback/), where 073's published the app's root. The pool matches redirect
  # URIs exactly, so the slash is part of the value.
  callback_url = "${module.web_app.url}/callback/"
}
# --- Cognito and the API ------------------------------------------------------------------------------------
module "user_pool" {
  source = "./modules/cognito_user_pool"

  mfa_configuration              = "OFF"
  callback_urls                  = [local.callback_url]
  domain_prefix                  = "${data.aws_region.current.region}-${random_id.domain_suffix.hex}"
  branding_settings_path         = "${path.root}/modules/cognito_user_pool/branding/settings.json"
  branding_background_image_path = "${path.root}/modules/cognito_user_pool/branding/page_background_light.png"

  depends_on = [module.network]
}
module "petstore_api" {
  source = "./modules/petstore_api"

  user_pool_arn        = module.user_pool.user_pool_arn
  authorization_scopes = module.user_pool.custom_scopes
  # A MOCK integration and no CORS preflight, as the _monolithic template had it. The API is called with curl
  # at this stage of the workshop; a browser page calling it would need cors_allow_origin set.
  backend_url       = null
  cors_allow_origin = null

  depends_on = [module.network]
}
# --- The web app's build ------------------------------------------------------------------------------------
#
# What sam build did, on the workbench because it is npm install: put the workshop tree there, write ws-env.sh,
# and run cognito-web/deploy.sh, which builds the package and uploads it to the web app's package bucket. At
# this stage of the workshop web-ui-js/cognito-sdk.js is still empty - writing it is the exercise - so
# deploy.sh has no front end to bundle yet, and the web app serves its pages and the callback page only.
#
# The _monolithic template wrote ws-env.sh in a second stage, after the pool existed. The pool exists before
# the build now, so both are one step. From Terraform's values rather than by exporting them and dumping env,
# so the file is the same each run. WS_MOCK_API_ID is new - web-ui-js/cognito-env-tmpl.js names it and the
# original never set it.
resource "aws_ssm_association" "webapp_build" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.webapp_name}-build"
  wait_for_success_timeout_seconds = var.webapp_build_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Re-runs when any staged file or any of the IDs changes, and then overwrites the workbench's copy of the
    # files it syncs - including edits made there during the workshop.
    commands = <<-EOT
      # workshop files ${module.workshop_files.content_hash}
      set -euo pipefail
      until [ -f ${local.marker}/userdata ]; do sleep 10; done
      aws s3 sync ${module.workshop_files.s3_uri} ${local.workshop_dir} --region ${data.aws_region.current.region} --only-show-errors
      cat > ${local.workshop_dir}/ws-env.sh << 'WSENV'
      export WS_CALLBACK_URL="${local.callback_url}"
      export WS_USER_POOL_ID="${module.user_pool.user_pool_id}"
      export WS_COGNITO_DOMAIN="${module.user_pool.domain}"
      export WS_USER_POOL_CLIENT_ID="${module.user_pool.client_id}"
      export WS_USER_POOL_ARN="${module.user_pool.user_pool_arn}"
      export WS_REGION="${data.aws_region.current.region}"
      export WS_MOCK_API_ID="${module.petstore_api.rest_api_id}"
      export WS_WEBAPP_URL="${module.web_app.url}"
      export WS_WEBAPP_FUNCTION_NAME="${module.web_app.function_name}"
      export WS_WEBAPP_PACKAGE_BUCKET="${module.web_app.package_bucket}"
      export WS_WEBAPP_PACKAGE_KEY="${module.web_app.package_key}"
      WSENV
      # S3 keeps no file modes.
      chmod +x ${local.workshop_dir}/ws-env.sh ${local.workshop_dir}/cognito-web/deploy.sh
      chown -R ec2-user:ec2-user ${local.workshop_dir}
      su - ec2-user -c "bash ${local.workshop_dir}/cognito-web/deploy.sh"
      touch ${local.marker}/webapp_built
      EOT
  }
  depends_on = [module.vscode_ec2, module.workshop_files]
}
# Holds the apply until the build's package is in S3.
#
# The read below used to wait on webapp_build through depends_on, trusting wait_for_success_timeout_seconds to
# hold the association's create until the build had finished. It did not, and the first apply failed with
# "couldn't find resource" on the package. From CloudTrail and the association's history, 2026-10-10 (KST):
#
#   04:13:46  RunInstances               the workbench launches
#   04:13:58  CreateAssociation          webapp_build; the provider starts polling DescribeAssociation
#   04:14:00  RegisterManagedInstance    the workbench's SSM agent registers - 2 seconds after the association
#   04:14:05  last DescribeAssociation   Overview Success, and the waiter returns
#   04:14:05  CreateAssociation          vscode_readme, and the package read: couldn't find resource
#   04:14:06  SendCommand                the build is sent to the workbench (command b171ef69-...)
#   04:17:15  put-object web-app.zip     3m10s after the read
#
# An association whose target has not registered with Systems Manager reports Success at once, and every first
# apply is in that state, because this association is created as soon as the instance is. That is the provider
# issue rules.md D-5 warns about; 073_cognito_identity_pool failed the same way on the same build.
#
# So the wait is a function that asks S3 for the object until it is there, and stops early only when the
# association's current run has failed - never on its Success. It reaches network through depends_on, which is
# what D-3 asks for; the association and the bucket arrive through the values below.
module "webapp_package_waiter" {
  source = "./modules/s3_object_waiter"

  function_name   = "${var.webapp_name}-PackageWaiter"
  bucket_name     = module.web_app.package_bucket
  bucket_arn      = module.web_app.package_bucket_arn
  object_key      = module.web_app.package_key
  association_id  = aws_ssm_association.webapp_build.association_id
  association_arn = aws_ssm_association.webapp_build.arn
  # The same number as the association's own wait, so "how long the build may take" stays one value, capped
  # at the 900 seconds a Lambda function can run. The cap is applied here rather than by lowering the variable:
  # the association's wait_for_success_timeout_seconds reads it too, and the provider sends any change to that
  # as an UpdateAssociation, which re-runs the whole build on the workbench.
  timeout_seconds = min(var.webapp_build_timeout_seconds, 900)

  depends_on = [module.network]
}
# The package the build uploaded, read for its SHA-256 - the function's code_sha256.
#
# Named through the waiter's result rather than module.web_app's outputs, and that is the whole ordering: while
# the waiter is being invoked its result is unknown, so this read is deferred to apply and runs after the wait;
# once the waiter is in state the read happens at plan, so a later deploy.sh upload is what the next plan
# compares against instead of something it reverts. No depends_on, which would defer the read on every change
# to the waiter's module (rules.md D-6).
data "aws_s3_object" "webapp_package" {
  bucket        = module.webapp_package_waiter.bucket
  key           = module.webapp_package_waiter.key
  checksum_mode = "ENABLED"
}
# --- README on the workbench ------------------------------------------------------------------------------
locals {
  # Every output this root exposes, defined once. outputs.tf projects this map and the README on the
  # workbench renders it, so an output cannot exist without also appearing in that README (rules.md H-2).
  outputs = {
    vscode_url = {
      order       = 1
      title       = "VS Code URL"
      description = "The workbench. The workshop tree is in ~/workshop, and ~/workshop/ws-env.sh holds the IDs below"
      value       = module.vscode_ec2.vscode_url
    }
    cognito_login_url = {
      order       = 2
      title       = "Managed login"
      description = "The _monolithic template's CognitoLoginUrl output: Cognito's own sign-in page, styled by the branding in this root, using the implicit flow. After sign-in the browser lands on the web app's callback page with the tokens in the URL"
      value       = "${module.user_pool.hosted_domain_url}/login?client_id=${module.user_pool.client_id}&response_type=token&scope=${join("+", module.user_pool.oauth_scopes)}&redirect_uri=${local.callback_url}"
    }
    openid_configuration_url = {
      order       = 3
      title       = "OpenID configuration"
      description = "The _monolithic template's CognitoOpenIdConfiguration output: the pool's issuer, endpoints and signing keys"
      value       = module.user_pool.openid_configuration_url
    }
    unauthorized_command = {
      order       = 4
      title       = "1. Call the API without a token"
      description = "The _monolithic template's TestUrl output. 401 - the Cognito authorizer rejects it before the MOCK integration is reached"
      value       = module.petstore_api.unauthorized_command
    }
    authorized_command = {
      order       = 5
      title       = "2. Call the API with the access token from the callback page"
      description = "Put the access_token the callback page shows into ACCESS_TOKEN. It carries petstore/read, the scope the method requires; the id_token does not, and is a 401"
      value       = module.petstore_api.authorized_command
    }
    user_pool_configuration_command = {
      order       = 6
      title       = "The pool's configuration"
      description = "MFA, auto-verification and the feature plan as Cognito holds them"
      value       = module.user_pool.configuration_check_command
    }
    web_app_deploy_command = {
      order       = 7
      title       = "Redeploy the web app"
      description = "After editing anything under ~/workshop/cognito-web - writing web-ui-js/cognito-sdk.js, for one. It bundles the front end once that file has content, rebuilds the package and points the function at it: what sam build and sam deploy did when the web app was a SAM stack. Its template is Terraform's now, so the directory has none"
      value       = "bash ${local.workshop_dir}/cognito-web/deploy.sh"
    }
    web_app_log_command = {
      order       = 8
      title       = "The web app's log"
      description = "The Lambda Web Adapter's lines, then the Express app's. Every request to the callback page passes through it"
      value       = module.web_app.log_tail_command
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
    ["# Cognito Authenticator with API Gateway", ""],
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
    # Waits for the web app's build, the last step on the workbench (rules.md D-5).
    commands = <<-EOT
      until [ -f ${local.marker}/webapp_built ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${local.marker}/vscode_readme
      EOT
  }
  depends_on = [aws_ssm_association.webapp_build]
}
