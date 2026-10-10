resource "aws_iam_role" "code_deploy_iam_role" {
  # A generated name, where the _monolithic template used "CodeDeployRole-${local.stack_suffix}".
  name_prefix = var.role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codedeploy.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# The _monolithic template hand-wrote this policy, and the action list it wrote is almost exactly AWS's
# own AWSCodeDeployRoleForECS. That matters for how much of it to touch: the list is what CodeDeploy
# actually calls during an ECS blue/green deployment, and guessing it short produces a deployment that
# stops partway with traffic already shifted - which is the worst state this project can be left in. So
# the actions stay, and only the three things that can be narrowed without guessing are narrowed
# (rules.md A-5).
resource "aws_iam_role_policy" "code_deploy_iam_role" {
  count = var.create_deploy_policy ? 1 : 0

  name = "code-deploy"
  role = aws_iam_role.code_deploy_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageTaskSetsAndTrafficRouting"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:CreateTaskSet",
          "ecs:UpdateServicePrimaryTaskSet",
          "ecs:DeleteTaskSet",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyRule",
          "cloudwatch:DescribeAlarms",
        ]
        # Left on *, and that is a decision rather than the template's default carried forward. Two of
        # these have no stable resource to name: UpdateServicePrimaryTaskSet and DeleteTaskSet act on a
        # task set whose ARN contains an id CodeDeploy generates, so scoping them means a wildcard
        # inside the ARN and no real narrowing. ModifyListener and ModifyRule are the pair that moves
        # production traffic, and they are the reason this role should not be reused for anything else.
        Resource = "*"
      },
      {
        Sid    = "ReadTheDeploymentRevision"
        Effect = "Allow"
        # Narrowed from the template's *. CodeDeploy reads the appspec out of the pipeline's artifact
        # store, which is one bucket, and GetObjectVersion is needed as well as GetObject because
        # CodePipeline hands the revision over by version.
        Action = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = [
          "${var.artifact_bucket_arn}/*",
        ]
      },
      {
        Sid    = "PassTaskExecutionRole"
        Effect = "Allow"
        # Narrowed from the template's *, which with the PassedToService condition still allowed any
        # role in the account to be handed to ECS. CodeDeploy passes one role: the execution role the
        # task definition it is deploying names.
        Action   = ["iam:PassRole"]
        Resource = [var.task_execution_role_arn]
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
}
# Two actions from the template's list are gone, and both because nothing in this project uses them.
#
# lambda:InvokeFunction authorizes the lifecycle hooks an appspec can declare - BeforeAllowTraffic and
# the rest. The appspec this project's build writes has no Hooks section at all, so on * this was a
# grant to invoke any function in the account from a role whose trust policy is a public AWS service.
# Adding a Hooks section means adding the action back, scoped to the functions named in it.
#
# sns:Publish authorizes the deployment group's trigger configuration. There is no trigger
# configuration here and no topic for one to point at.
resource "aws_codedeploy_app" "code_deploy_application" {
  name             = var.application_name
  compute_platform = "ECS"
}
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name               = aws_codedeploy_app.code_deploy_application.name
  deployment_group_name  = var.deployment_group_name
  service_role_arn       = aws_iam_role.code_deploy_iam_role.arn
  deployment_config_name = var.deployment_config_name
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
  ecs_service {
    cluster_name = var.cluster_name
    service_name = var.service_name
  }
  load_balancer_info {
    target_group_pair_info {
      # The production listener. This is the single piece of configuration that makes the listener's
      # default rule a field with two owners - CodeDeploy rewrites it to shift traffic, which is why
      # the load balancer module ignores changes to it (rules.md E-8).
      #
      # Note what is not here: a test_traffic_route. And note that naming the listener is enough to
      # bring its rules in: CodeDeploy also rewrites any rule on this listener that forwards to the live
      # target group, so the User-Agent rule the load balancer module reproduces moves with every
      # deployment and has to be ignored the same way the default action is. If Terraform puts it back
      # on the old target group, the next deployment stops before creating a task set with "Primary
      # taskset target group must be behind listener <rule ARN>".
      prod_traffic_route {
        listener_arns = var.listener_arns
      }
      # Both target groups by name, not ARN, which is what CodeDeploy takes here. Order is not
      # significant - CodeDeploy works out which one the service currently uses and registers the
      # replacement task set into the other.
      target_group {
        name = var.blue_target_group_name
      }
      target_group {
        name = var.green_target_group_name
      }
    }
  }
  blue_green_deployment_config {
    deployment_ready_option {
      # CONTINUE_DEPLOYMENT, as the _monolithic template had it: traffic shifts as soon as the
      # replacement task set is healthy, with no approval step. STOP_DEPLOYMENT would park the
      # deployment waiting for someone, which is the production setting and the wrong one for a demo
      # that then has nothing to show.
      action_on_timeout = var.deployment_ready_action_on_timeout
    }
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      # Zero, as the template had it. This is the window in which a rollback is instant because the
      # original task set is still running - at zero there is no such window, and a rollback has to
      # start new tasks. It also means a listener rule left on the previous target group points at a
      # target group with no task set behind it, which CodeDeploy refuses at the next deployment.
      termination_wait_time_in_minutes = var.termination_wait_time_in_minutes
    }
  }
  auto_rollback_configuration {
    enabled = true
    # The template's three events, reproduced. DEPLOYMENT_STOP_ON_ALARM is in the list and cannot
    # actually fire: it rolls back when an alarm in the deployment group's alarm_configuration goes
    # into ALARM, and there is no alarm_configuration here. It is harmless and kept, because removing
    # it would change what the original declared - but a reader should not take it as evidence that
    # this deployment is watching anything.
    events = var.auto_rollback_events
  }

  # The role must carry its policy before CodeDeploy will validate it. service_role_arn orders this
  # after the role but not after the policy on it, and CodeDeploy checks the role at
  # CreateDeploymentGroup - so a race here fails the apply rather than the first deployment
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy.code_deploy_iam_role]
}
