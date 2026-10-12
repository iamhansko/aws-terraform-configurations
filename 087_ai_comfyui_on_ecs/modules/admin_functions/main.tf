# The blueprint's AdminConstruct: seven functions from its admin_lambda directory, the load balancer routes
# that put five of them behind the Cognito login, and the two events that drive the other two.
#
# Together they are how the GPU instance is turned on and off without the console. /admin shows the state
# and offers Scale Up, Restart Docker or Shutdown; while ComfyUI is down, the scale-in listener widens the
# /admin rule to answer / as well, so a user who opens the application lands on that page rather than on the
# 503 an empty target group returns, and the scale-up listener narrows it again once the task is running.
#
# One module, rather than functions here and rules in the root, because the routes and the functions name
# each other: the rule needs the admin function's target group, and three functions need the rule's ARN.
locals {
  # The blueprint's functions, keyed by the module their handler is in. All seven are one code package, as
  # the blueprint shipped the whole directory to each.
  functions = {
    admin            = "admin.handler"
    restart_docker   = "restart_docker.handler"
    shutdown         = "shutdown.handler"
    scaleup_trigger  = "scaleup_trigger.handler"
    scalein_listener = "scalein_listener.handler"
    scaleup_listener = "scaleup_listener.handler"
    signout          = "signout.handler"
  }
  function_names = { for key in keys(local.functions) : key => "${var.name}-${replace(key, "_", "-")}" }

  service_environment = {
    ASG_NAME         = var.auto_scaling_group_name
    ECS_CLUSTER_NAME = var.cluster_name
    ECS_SERVICE_NAME = var.service_name
  }
  # Each function's environment as the blueprint gave it, split by whether it reads the admin rule's ARN.
  # They are two resources because of that split: one for_each resource is one node in the graph, and the
  # rule cannot both wait for the admin function and be waited for by the restart function in the same node.
  static_environment = {
    admin           = local.service_environment
    shutdown        = { ASG_NAME = var.auto_scaling_group_name }
    scaleup_trigger = local.service_environment
    signout         = { REDIRECT_URL = var.logout_redirect_url }
  }
  rule_aware_environment = {
    restart_docker   = merge(local.service_environment, { LISTENER_RULE_ARN = aws_lb_listener_rule.admin.arn })
    scalein_listener = { ASG_NAME = var.auto_scaling_group_name, LISTENER_RULE_ARN = aws_lb_listener_rule.admin.arn }
    scaleup_listener = merge(local.service_environment, { LISTENER_RULE_ARN = aws_lb_listener_rule.admin.arn })
  }
  function_arns = merge(
    { for key, function in aws_lambda_function.static : key => function.arn },
    { for key, function in aws_lambda_function.rule_aware : key => function.arn },
  )

  # The blueprint's listener rules, by priority. The keys are short because they name target groups, which
  # ELB limits to 32 characters.
  routes = {
    admin    = { function = "admin", path = "/admin", priority = 5 }
    restart  = { function = "restart_docker", path = "/admin/restart", priority = 10 }
    shutdown = { function = "shutdown", path = "/admin/shutdown", priority = 15 }
    scaleup  = { function = "scaleup_trigger", path = "/admin/scaleup", priority = 20 }
    signout  = { function = "signout", path = "/signout", priority = 25 }
  }
}

# --- Role -----------------------------------------------------------------------------------------------

resource "aws_iam_role" "functions" {
  name_prefix = "${substr(var.name, 0, 26)}-admin-fn-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The blueprint's managed policies (rules.md B-7/B-8). See function_policy_arns for why AutoScalingFullAccess
# is kept.
resource "aws_iam_role_policy_attachment" "functions" {
  for_each   = toset(var.function_policy_arns)
  role       = aws_iam_role.functions.name
  policy_arn = each.value
}
# The blueprint's inline statement, as it wrote it: reading and updating the service, rewriting the admin rule,
# and sending the Docker restart through SSM Run Command.
resource "aws_iam_role_policy" "functions" {
  name = "admin"
  role = aws_iam_role.functions.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:UpdateService",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyRule",
        "ssm:SendCommand",
      ]
      Resource = "*"
    }]
  })
}

# --- Functions ------------------------------------------------------------------------------------------

# Declared before the functions so they write to a group with a retention. The blueprint declared none, so
# Lambda created seven that never expired and outlived the stack.
resource "aws_cloudwatch_log_group" "function" {
  for_each = local.function_names

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days
}
resource "aws_lambda_function" "static" {
  for_each = local.static_environment

  function_name    = local.function_names[each.key]
  role             = aws_iam_role.functions.arn
  runtime          = var.runtime
  handler          = local.functions[each.key]
  timeout          = var.timeout
  filename         = var.source_zip_path
  source_code_hash = var.source_code_hash

  environment {
    variables = each.value
  }

  # The role's policies and the log group have to exist before the first invocation, and the role ARN implies
  # neither (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.functions, aws_iam_role_policy.functions, aws_cloudwatch_log_group.function]
}
resource "aws_lambda_function" "rule_aware" {
  for_each = local.rule_aware_environment

  function_name    = local.function_names[each.key]
  role             = aws_iam_role.functions.arn
  runtime          = var.runtime
  handler          = local.functions[each.key]
  timeout          = var.timeout
  filename         = var.source_zip_path
  source_code_hash = var.source_code_hash

  environment {
    variables = each.value
  }

  depends_on = [aws_iam_role_policy_attachment.functions, aws_iam_role_policy.functions, aws_cloudwatch_log_group.function]
}

# --- Load balancer routes -------------------------------------------------------------------------------

# Lambda targets have no port and no VPC. No health_check block, as the blueprint set none: ELB then leaves
# health checks off for a Lambda target group - on, it would invoke the admin function every half minute and
# have it describe the Auto Scaling group each time. Declaring the block, even with enabled = false, fills in
# the provider's defaults, and a 30-second interval with the 30-second timeout it picks for Lambda is rejected
# with "Health check interval must be greater than the timeout".
resource "aws_lb_target_group" "route" {
  for_each = local.routes

  name        = "${var.name}-${each.key}"
  target_type = "lambda"
}
# Who may invoke each function: the load balancer, through that function's target group only. The blueprint's
# permissions named no source, which let any target group in any account register the function.
resource "aws_lambda_permission" "route" {
  for_each = local.routes

  statement_id  = "AllowLoadBalancer"
  action        = "lambda:InvokeFunction"
  function_name = local.function_names[each.value.function]
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.route[each.key].arn

  # function_name is a string built here, not a reference, so nothing else orders this after the function.
  depends_on = [aws_lambda_function.static, aws_lambda_function.rule_aware]
}
resource "aws_lb_target_group_attachment" "route" {
  for_each = local.routes

  target_group_arn = aws_lb_target_group.route[each.key].arn
  target_id        = local.function_arns[each.value.function]

  # ELB invokes the function to check it may when it is registered, and rejects the registration without the
  # permission (rules.md D-1).
  depends_on = [aws_lambda_permission.route]
}
# /admin, on its own because the functions rewrite its condition at runtime: the scale-in listener and the
# restart function widen it to "/" and "/admin" while ComfyUI is down, the scale-up listener narrows it back.
# Ignoring the condition is what keeps every plan from reverting that while the instance is off - and from
# sending the user to a 502 instead of the page that can turn it back on. Only that field (rules.md E-8).
resource "aws_lb_listener_rule" "admin" {
  listener_arn = var.listener_arn
  priority     = local.routes.admin.priority

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = var.cognito_user_pool_arn
      user_pool_client_id = var.cognito_user_pool_client_id
      user_pool_domain    = var.cognito_user_pool_domain
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.route["admin"].arn
  }

  condition {
    path_pattern {
      values = [local.routes.admin.path]
    }
  }

  lifecycle {
    ignore_changes = [condition]
  }
}
resource "aws_lb_listener_rule" "route" {
  for_each = { for key, route in local.routes : key => route if key != "admin" }

  listener_arn = var.listener_arn
  priority     = each.value.priority

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = var.cognito_user_pool_arn
      user_pool_client_id = var.cognito_user_pool_client_id
      user_pool_domain    = var.cognito_user_pool_domain
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.route[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

# --- Events ---------------------------------------------------------------------------------------------

# An instance about to terminate - the idle scale-in, Shutdown, a spot interruption. ECS managed draining's
# lifecycle hook is what makes Auto Scaling emit this event (modules/ecs_gpu_capacity).
resource "aws_cloudwatch_event_rule" "scale_in" {
  name        = "${var.name}-scale-in"
  description = "Points / at the admin page when the ComfyUI GPU instance is terminating"
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [var.auto_scaling_group_name]
    }
  })
}
resource "aws_cloudwatch_event_target" "scale_in" {
  rule = aws_cloudwatch_event_rule.scale_in.name
  arn  = aws_lambda_function.rule_aware["scalein_listener"].arn
}
resource "aws_lambda_permission" "scale_in" {
  statement_id  = "AllowScaleInEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rule_aware["scalein_listener"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_in.arn
}
# A task reaching RUNNING anywhere in the cluster.
resource "aws_cloudwatch_event_rule" "task_running" {
  name        = "${var.name}-task-running"
  description = "Gives / back to ComfyUI once its ECS task is running"
  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      clusterArn = [var.cluster_arn]
      lastStatus = ["RUNNING"]
    }
  })
}
resource "aws_cloudwatch_event_target" "task_running" {
  rule = aws_cloudwatch_event_rule.task_running.name
  arn  = aws_lambda_function.rule_aware["scaleup_listener"].arn
}
resource "aws_lambda_permission" "task_running" {
  statement_id  = "AllowTaskRunningEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rule_aware["scaleup_listener"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.task_running.arn
}
