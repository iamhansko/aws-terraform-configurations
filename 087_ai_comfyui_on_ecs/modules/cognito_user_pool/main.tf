# The blueprint's AuthConstruct: the user pool the load balancer authenticates against, its hosted-UI domain,
# the app client the load balancer uses, and the optional pre sign-up check that limits who can register.
locals {
  restrict_sign_up_domains = length(var.allowed_sign_up_email_domains) > 0
  # Lowercase, because that is what the load balancer sends as redirect_uri - a browser lowercases the host it
  # requests - and Cognito compares callback URLs exactly. The blueprint registered the ALB's DNS name as
  # CloudFormation returned it, mixed case, and needed a second custom resource and Lambda
  # (UpdateCognitoCallbackUrl) to rewrite the URLs in lowercase after the stack had created them.
  application_url = "https://${lower(var.application_dns_name)}"
  # Threat protection is a Plus-plan feature: a pool created with it on and no plan named is put on Plus,
  # which is what happened to the blueprint's pool. Derived rather than a second variable, so the two cannot
  # disagree (rules.md B-1).
  user_pool_tier     = var.advanced_security_mode == "OFF" ? "ESSENTIALS" : "PLUS"
  hosted_ui_base_url = "https://${aws_cognito_user_pool_domain.domain.domain}.auth.${var.region}.amazoncognito.com"
}

# --- SMS ------------------------------------------------------------------------------------------------

# What CDK created for the pool because the blueprint enabled SMS as an MFA factor and auto-verifies phone
# numbers: a role Cognito assumes to publish SMS through SNS, guarded by an external ID.
resource "aws_iam_role" "sms" {
  name_prefix = "${substr(var.name, 0, 30)}-sms-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cognito-idp.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.sms_external_id }
      }
    }]
  })
}
# sns:Publish on *, as CDK granted it. SMS publishing has no topic to scope to - the target is a phone number.
resource "aws_iam_role_policy" "sms" {
  name = "sns-publish"
  role = aws_iam_role.sms.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = "*"
    }]
  })
}

# --- Pre sign-up check ----------------------------------------------------------------------------------

# The blueprint's checkEmailDomainFunction, created only when there are domains to check against - the
# blueprint's allowed_sign_up_email_domains=None. Cognito also runs it for users created by an administrator,
# so with domains set an address outside them cannot be added from the console either.
resource "aws_cloudwatch_log_group" "pre_sign_up" {
  count = local.restrict_sign_up_domains ? 1 : 0

  name              = "/aws/lambda/${var.name}-check-email-domain"
  retention_in_days = var.log_retention_days
}
resource "aws_iam_role" "pre_sign_up" {
  count = local.restrict_sign_up_domains ? 1 : 0

  name_prefix = "${substr(var.name, 0, 24)}-signup-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "pre_sign_up" {
  count = local.restrict_sign_up_domains ? 1 : 0

  role       = aws_iam_role.pre_sign_up[0].name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_lambda_function" "pre_sign_up" {
  count = local.restrict_sign_up_domains ? 1 : 0

  function_name    = "${var.name}-check-email-domain"
  role             = aws_iam_role.pre_sign_up[0].arn
  runtime          = var.lambda_runtime
  handler          = "check_email_domain.handler"
  timeout          = 60
  filename         = var.pre_sign_up_source_zip_path
  source_code_hash = var.pre_sign_up_source_code_hash

  environment {
    variables = {
      # A JSON array, as the blueprint passed json.dumps(allowed_sign_up_email_domains) to the function.
      ALLOWED_SIGN_UP_EMAIL_DOMAINS_STR = jsonencode(var.allowed_sign_up_email_domains)
    }
  }

  # The role's managed policy and the function's log group have to exist before the first invocation, and the
  # role ARN implies neither (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.pre_sign_up, aws_cloudwatch_log_group.pre_sign_up]
}

# --- User pool ------------------------------------------------------------------------------------------

resource "aws_cognito_user_pool" "pool" {
  name           = var.name
  user_pool_tier = local.user_pool_tier
  # Destroyed with the configuration. The blueprint's pool carried CDK's default RETAIN policy and outlived its
  # stack along with every user in it.
  deletion_protection = "INACTIVE"

  # Optional MFA with both factors, as the blueprint had it, or required with mfa_required.
  mfa_configuration = var.mfa_required ? "ON" : "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }
  # No sns_region, as the blueprint set none: Cognito picks the SNS region for the pool's region itself, and for
  # some regions that is a different one - a pool in Seoul sends its SMS through SNS in Tokyo.
  sms_configuration {
    external_id    = var.sms_external_id
    sns_caller_arn = aws_iam_role.sms.arn
  }

  auto_verified_attributes = ["email", "phone_number"]
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }
  admin_create_user_config {
    allow_admin_create_user_only = !var.self_sign_up_enabled
  }

  # The blueprint's policy. require_lowercase is false because the blueprint did not set it: CDK documents a
  # default of true, but CDK 2.150 leaves the property out of the template, and Cognito's own default is false.
  #
  # The root's set_user_password_command output states these rules in its description, which cannot be an
  # expression - so a change here is a change there too.
  password_policy {
    minimum_length                   = 12
    require_lowercase                = false
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # The three required attributes. Standard attributes, so the constraints are the ones Cognito reports for them
  # anyway; stated so the plan does not show them as a change (schema changes replace the pool).
  dynamic "schema" {
    for_each = toset(["email", "given_name", "family_name"])
    content {
      name                     = schema.value
      attribute_data_type      = "String"
      required                 = true
      mutable                  = true
      developer_only_attribute = false
      string_attribute_constraints {
        min_length = "0"
        max_length = "2048"
      }
    }
  }

  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

  # CDK's default verification message, which it writes into every user pool it creates.
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Verify your new account"
    email_message        = "The verification code to your new account is {####}"
    sms_message          = "The verification code to your new account is {####}"
  }

  dynamic "lambda_config" {
    for_each = aws_lambda_function.pre_sign_up
    content {
      pre_sign_up = lambda_config.value.arn
    }
  }

  # Cognito checks it can assume the SMS role when the pool is created, and sns_caller_arn does not order this
  # after the role's policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.sms]
}
resource "aws_lambda_permission" "pre_sign_up" {
  count = local.restrict_sign_up_domains ? 1 : 0

  statement_id  = "AllowCognitoPreSignUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_sign_up[0].function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.pool.arn
}
# The hosted UI the load balancer redirects to. A Cognito prefix domain is unique per region across all
# accounts, which is why the prefix carries a hash of the account, the region and the project name.
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.pool.id
}
# The client the load balancer's authenticate-cognito action uses. It needs a secret - the load balancer
# fetches it from Cognito itself - and the authorization code grant.
resource "aws_cognito_user_pool_client" "load_balancer" {
  name                                 = var.client_name
  user_pool_id                         = aws_cognito_user_pool.pool.id
  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]
  supported_identity_providers         = ["COGNITO"]
  # Where the load balancer receives the authorization code, and the application itself so the sign-out flow
  # can return to the login page.
  callback_urls = ["${local.application_url}/oauth2/idpresponse", local.application_url]
  logout_urls   = [local.application_url]
}
