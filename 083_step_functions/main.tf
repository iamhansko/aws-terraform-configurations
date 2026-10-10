# The two functions the state machine invokes. One module used twice, because the only thing that differs is
# the source directory - the role, the log group, the packaging and the permissions are identical.
module "validate_data_function" {
  source = "./modules/python_lambda_function"

  name               = "${var.project_name}-validate-data"
  source_dir         = "${path.root}/lambda_src/validate_data_function"
  runtime            = var.lambda_runtime
  log_retention_days = var.log_retention_days
  # Nothing beyond its own logs: it transforms the object it is given and returns.
}
module "process_data_function" {
  source = "./modules/python_lambda_function"

  name               = "${var.project_name}-process-data"
  source_dir         = "${path.root}/lambda_src/process_data_function"
  runtime            = var.lambda_runtime
  log_retention_days = var.log_retention_days
}
module "notification_topic" {
  source = "./modules/sns_notification_topic"

  name                = "${var.project_name}-notifications"
  display_name        = "Step Functions demo"
  email_subscriptions = var.notification_email_addresses
}
module "state_machine" {
  source = "./modules/step_functions_state_machine"

  name = var.project_name
  # The ARNs rather than the names, so the definition and the role's policy read the same values and the
  # policy can be scoped to exactly these two functions (rules.md B-5).
  validate_function_arn  = module.validate_data_function.arn
  process_function_arn   = module.process_data_function.arn
  notification_topic_arn = module.notification_topic.arn
  log_level              = var.state_machine_log_level
  log_retention_days     = var.log_retention_days
}
# The function that starts an execution.
#
# It exists because Terraform has no resource for running a state machine once: the machine is
# infrastructure, an execution is not. The _monolithic template used the same shim as a CloudFormation custom
# resource, and it could not have worked - the code imported cfnresponse, a module CloudFormation injects only
# into inline Lambda code, so a zipped function fails on the import; and it read its arguments from
# event["ResourceProperties"], which is not the shape anything here sends. The rewritten source in
# lambda_src/execution_starter_function has the details.
module "execution_starter_function" {
  source = "./modules/python_lambda_function"

  name               = "${var.project_name}-execution-starter"
  source_dir         = "${path.root}/lambda_src/execution_starter_function"
  runtime            = var.lambda_runtime
  timeout            = var.starter_function_timeout
  log_retention_days = var.log_retention_days
  # Scoped to the one state machine, where the _monolithic template granted states:StartExecution on "*"
  # (rules.md A-5). Supplied by the root because the module does not know what the function calls
  # (rules.md B-6).
  additional_policy_statements = [{
    actions   = ["states:StartExecution"]
    resources = [module.state_machine.arn]
  }]
}
# The demo executions, started at apply time.
#
# aws_lambda_invocation rather than a null_resource with a local-exec: the call is made by the AWS provider
# with the same credentials as everything else, its result is recorded in state, and a failure fails the
# apply. The result carries the execution ARN, which the outputs below read.
#
# It re-invokes whenever its input changes, so editing demo_executions starts fresh runs - and so does a
# replaced state machine, because its ARN is part of the input. It does not re-invoke on an unchanged apply,
# which is why the executions are not duplicated every time. lifecycle_scope stays at its default
# CREATE_ONLY: terraform destroy calls nothing, it only drops the recorded result.
resource "aws_lambda_invocation" "demo_execution" {
  for_each = var.demo_executions

  function_name = module.execution_starter_function.name
  input = jsonencode({
    stateMachineArn = module.state_machine.arn
    input = {
      data = {
        name = each.value.name
        age  = each.value.age
      }
    }
  })

  # The state machine's role has to be able to invoke the two functions before an execution starts, and the
  # starter's own policy has to exist before it is invoked. Neither is implied by the ARN references above
  # (rules.md D-1/D-2).
  depends_on = [module.state_machine, module.execution_starter_function]
}
