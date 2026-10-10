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
  # The group whose members may call the PetStore API. The pre token generation trigger copies a user's groups
  # into the access token's scopes, and the API's method accepts this one, so membership is the switch. Named
  # once because three things have to agree on it: the group that exists, the scope the method checks, and
  # the README command that adds a user to it (rules.md B-5).
  api_group = "Engineering"
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
  # build, gettext for the envsubst in it, and zip for its package, which SAM used to make.
  #
  # SAM CLI no longer deploys anything this root creates. It stays for the workshop's own exercises - the
  # cognito-lambdas template and the empty ApiGWAuthZ one are the participants' to fill in and deploy.
  #
  # docker with the group membership and a code-server restart rather than the chmod 666 on
  # /var/run/docker.sock the template used, which handed the root-equivalent socket to every local user
  # (rules.md H-1 describes the same fix).
  additional_user_data = <<-EOT
    dnf install -yq docker nodejs gettext unzip zip
    systemctl enable --now docker
    usermod -aG docker ec2-user
    systemctl restart code-server
    cd /tmp
    wget -q https://github.com/aws/aws-sam-cli/releases/download/v${var.sam_cli_version}/aws-sam-cli-linux-x86_64.zip
    unzip -q aws-sam-cli-linux-x86_64.zip -d sam-installation
    ./sam-installation/install
    rm -rf sam-installation aws-sam-cli-linux-x86_64.zip
    npm install -g esbuild
    runuser -u ec2-user -- env HOME=/home/ec2-user aws configure set default.region ${data.aws_region.current.region}
  EOT

  depends_on = [module.network, module.key_pair]
}
module "workshop_files" {
  source = "./modules/workshop_files"

  source_dir = "${path.root}/workshop"

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
  webapp_url   = module.web_app.url
  callback_url = "${local.webapp_url}/callback"
}
# --- Cognito ------------------------------------------------------------------------------------------------
#
# The workshop's other SAM template, cognito-lambdas, is the pre token generation function here: one function
# and the permission for the pool to invoke it, which the user pool module holds.
module "pre_token_generation" {
  source = "./modules/cognito_trigger_lambda"

  # Not cognito-lambdas-PreToken, the name the workshop's own SAM template gives it - deploying that template
  # from the workbench later would collide with a fixed name taken here.
  function_name = "${var.project_name}-PreToken"
  # The same file the workbench gets, so the deployed trigger and the workshop's copy cannot differ.
  source_file = "${path.root}/workshop/cognito-lambdas/PreToken/app.mjs"

  depends_on = [module.network]
}
module "user_pool" {
  source = "./modules/cognito_user_pool"

  callback_urls = [local.callback_url]
  domain_prefix = "${data.aws_region.current.region}-${random_id.domain_suffix.hex}"
  groups        = [local.api_group, "Customer"]
  pre_token_generation_lambda = {
    arn           = module.pre_token_generation.function_arn
    function_name = module.pre_token_generation.function_name
  }
  branding_settings_path         = "${path.root}/modules/cognito_user_pool/branding/settings.json"
  branding_background_image_path = "${path.root}/modules/cognito_user_pool/branding/page_background_light.png"

  depends_on = [module.network]
}
module "listable_bucket" {
  source = "./modules/listable_bucket"

  depends_on = [module.network]
}
module "identity_pool" {
  source = "./modules/cognito_identity_pool"

  user_pool_client_id  = module.user_pool.client_id
  user_pool_endpoint   = module.user_pool.user_pool_endpoint
  listable_bucket_arns = [module.listable_bucket.bucket_arn]

  depends_on = [module.network]
}
module "petstore_api" {
  source = "./modules/petstore_api"

  user_pool_arn = module.user_pool.user_pool_arn
  # The resource server's scope, or the Engineering group - which reaches the token as a scope through the
  # pre token generation trigger. Either is enough, and a token with neither is a 401 by design: a user signed
  # in through the web app's SDK form carries only aws.cognito.signin.user.admin until they join the group
  # (custom scopes come only from the OAuth flows). That is the workshop's lesson, so the scopes stay as they
  # are; what the module adds is CORS on the 401 itself, so the page can say so instead of "Network Error".
  authorization_scopes      = concat(module.user_pool.custom_scopes, [local.api_group])
  optional_query_parameters = ["page", "type"]
  backend_url               = "http://petstore.execute-api.us-east-1.amazonaws.com/petstore/pets"
  # The workshop page calls GET /pets from the web app's origin with an Authorization header, which makes the
  # browser send a preflight first.
  cors_allow_origin = "*"

  depends_on = [module.network]
}
# --- The web app's build ------------------------------------------------------------------------------------
#
# What sam build did, on the workbench because it is npm install and an esbuild bundle: put the workshop tree
# there, write ws-env.sh, and run cognito-web/deploy.sh, which builds the package and uploads it to the web
# app's package bucket. The _monolithic template did this twice, across its two stacks - deployed the web app
# unconfigured to get an address, then rebuilt it once the pool existed. The address comes from the API now, so
# the pool exists first and one build is enough.
#
# ws-env.sh is written from Terraform's values rather than by exporting them and dumping env, so the file is
# the same each run. deploy.sh reads it, and so do the workshop's later steps.
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
      export WS_IDENTITY_POOL_ID="${module.identity_pool.identity_pool_id}"
      export WS_WEBAPP_URL="${local.webapp_url}"
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
# "couldn't find resource" on the package. From CloudTrail and the association's history, 2026-10-09 (KST):
#
#   23:54:22  RunInstances               the workbench launches
#   23:54:34  CreateAssociation          webapp_build; the provider starts polling DescribeAssociation
#   23:54:37  RegisterManagedInstance    the workbench's SSM agent registers - 3 seconds after the association
#   23:54:38  last DescribeAssociation   Overview Success with no targets counted, and the waiter returns
#   23:54:41  CreateAssociation          vscode_readme, and the package read: NoSuchKey
#   23:54:48  SendCommand                the build is sent to the workbench (command 987f104e-...)
#   23:57:54  put-object web-app.zip     3m20s after the read
#
# An association whose target has not registered with Systems Manager reports Success at once - reproduced
# against an instance ID that does not exist, which stays Success with an empty AssociationStatusAggregatedCount
# for as long as it is watched. That is the provider issue rules.md D-5 warns about, and every first apply is
# in it, because this association is created as soon as the instance is.
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
      description = "The workbench. The workshop tree is in ~/workshop, and ~/workshop/ws-env.sh holds every ID below"
      value       = module.vscode_ec2.vscode_url
    }
    web_app_url = {
      order       = 2
      title       = "Workshop web app"
      description = "The _monolithic template's 03oooUi output: sign up, sign in, enrol TOTP, call the API and list the bucket, all from the browser"
      value       = "${local.webapp_url}/cognito-sdk.html"
    }
    cognito_login_url = {
      order       = 3
      title       = "Managed login"
      description = "Cognito's own sign-in page, styled by the branding in this root, using the implicit flow - the tokens come back in the callback URL"
      value       = "${module.user_pool.hosted_domain_url}/login?client_id=${module.user_pool.client_id}&response_type=token&scope=${join("+", module.user_pool.oauth_scopes)}&redirect_uri=${local.callback_url}"
    }
    openid_configuration_url = {
      order       = 4
      title       = "OpenID configuration"
      description = "The pool's discovery document: issuer, endpoints and signing keys"
      value       = module.user_pool.openid_configuration_url
    }
    unauthorized_command = {
      order       = 5
      title       = "1. Call the API without a token"
      description = "401 - the Cognito authorizer rejects it before the backend is reached"
      value       = module.petstore_api.unauthorized_command
    }
    api_group_command = {
      order       = 6
      title       = "2. Let a user call the API"
      description = "The API accepts an access token that carries the Engineering group as a scope, and a user who has just signed up is in no group - so the web app's Call APIs tab answers 401 for them. Replace USERNAME and run this, then sign out and in again: the group reaches the token's scopes only when a token is issued"
      value       = "aws cognito-idp admin-add-user-to-group --user-pool-id ${module.user_pool.user_pool_id} --group-name ${local.api_group} --username USERNAME"
    }
    authorized_command = {
      order       = 7
      title       = "3. Call the API with an access token"
      description = "Put an access token in ACCESS_TOKEN first. It needs petstore/read, or the Engineering group, which the pre token generation trigger adds to the token as a scope"
      value       = module.petstore_api.authorized_command
    }
    bucket = {
      order       = 8
      title       = "4. The bucket for the Access S3 tab"
      description = "The _monolithic template's 06oooS3BucketName output, and exactly what the Access S3 tab's Bucket field takes. The listing runs on identity pool credentials, so sign in first. Anything around the name - this value used to carry the prefixes after it - makes S3 answer 400 InvalidBucketName without CORS headers, which the page shows as Failed to fetch"
      value       = module.listable_bucket.bucket_name
    }
    bucket_prefixes = {
      order       = 9
      title       = "5. The prefixes for the Access S3 tab"
      description = "What the Prefix field takes, one at a time. Case matters: a prefix that matches nothing lists nothing, which the page reports as There was a problem"
      value       = join(", ", module.listable_bucket.prefixes)
    }
    guest_credentials_command = {
      order       = 10
      title       = "6. Guest credentials, with no sign-in"
      description = "The identity pool's unauthenticated flow. The guest role has no permissions, so these credentials can do nothing"
      value       = module.identity_pool.guest_credentials_command
    }
    user_pool_configuration_command = {
      order       = 11
      title       = "7. The pool's MFA, auto-verification and trigger"
      description = "All three as Cognito holds them. The _monolithic template set the trigger with update-user-pool, which reset the other two - its 00oooAllowEmailAutoVerification output was the console link for switching email verification back on by hand"
      value       = module.user_pool.configuration_check_command
    }
    pre_token_log_command = {
      order       = 12
      title       = "8. The pre token generation trigger's log"
      description = "It runs on every sign-in and token refresh and copies the user's groups into the access token's scopes"
      value       = module.pre_token_generation.log_tail_command
    }
    web_app_deploy_command = {
      order       = 13
      title       = "Redeploy the web app"
      description = "After editing anything under ~/workshop/cognito-web. It rebuilds the front-end bundle and the package and points the function at it - what sam build and sam deploy did when the web app was a SAM stack. Its template is Terraform's now, so the directory has none"
      value       = "bash ${local.workshop_dir}/cognito-web/deploy.sh"
    }
    web_app_log_command = {
      order       = 14
      title       = "The web app's log"
      description = "The Lambda Web Adapter's lines, then the Express app's"
      value       = module.web_app.log_tail_command
    }
    user_status_command = {
      order       = 15
      title       = "Who has signed up, and who is still unconfirmed"
      description = "UNCONFIRMED with email_verified false means a code was sent and never entered. The web app's Resend Code sends a new one. Cognito's default email leaves no record of delivery, so the masked address the code prompt shows is the only trace of where it went - check spam for no-reply@verificationemail.com"
      value       = module.user_pool.user_status_command
    }
    private_key_command = {
      order       = 16
      title       = "Workbench SSH key"
      description = "Retrieves the generated private key from Parameter Store. No security group opens port 22; this is for the case where the SSM agent is what is broken"
      value       = module.key_pair.private_key_command
    }
  }
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# Cognito Identity Pool", ""],
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
