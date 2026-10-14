output "kiro_login_data" {
  value = {
    start_url           = local.identity_store_id == null ? null : "https://${local.identity_store_id}.awsapps.com/start"
    user_name            = module.kiro_user.user_name
    user_one_time_password   = nonsensitive(data.aws_ssm_parameter.kiro_password.value)
    user_email               = module.kiro_user.email
    login_region = module.kiro_bootstrap.aws_region
  }
  description = "Kiro Login"
}
