resource "aws_iam_role" "code_deploy_iam_role" {
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
# AWSCodeDeployRoleForECS, as the _monolithic template attached it, and unlike the CodeBuild role in this
# project that is the right answer rather than an inherited one: it is AWS's service role policy for
# exactly this job - CreateTaskSet, ModifyListener, the target group calls, and iam:PassRole conditioned on
# ecs-tasks.amazonaws.com. There is nothing in it this deployment group does not use (rules.md A-5).
resource "aws_iam_role_policy_attachment" "code_deploy_iam_role" {
  for_each   = toset(var.service_role_policy_arns)
  role       = aws_iam_role.code_deploy_iam_role.name
  policy_arn = each.value
}
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
      prod_traffic_route {
        listener_arns = [var.production_listener_arn]
      }
      # Both groups by name, not ARN, which is what CodeDeploy takes here. Order is not significant -
      # CodeDeploy reads the listener to find out which one is live and treats the other as the
      # replacement. That is also why nothing in this module has to be told which is which: the only
      # agreement that matters is that these two names are the two groups behind that listener.
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
      # CONTINUE_DEPLOYMENT as the _monolithic template had it: traffic shifts as soon as the replacement
      # task set is healthy, with no approval step. STOP_DEPLOYMENT parks the deployment waiting for
      # someone, which is the production setting and the wrong one for a demo that then shows nothing.
      action_on_timeout = var.deployment_ready_action_on_timeout
      # Only meaningful when action_on_timeout is STOP_DEPLOYMENT, and rejected otherwise.
      wait_time_in_minutes = var.deployment_ready_action_on_timeout == "STOP_DEPLOYMENT" ? var.deployment_ready_wait_time_in_minutes : null
    }
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
      # Zero, as the template had it. This is the window in which a rollback is instant because the
      # original task set is still running; at zero there is no such window and a rollback has to start
      # new tasks. It is also what keeps the container instances from needing to hold two task sets for
      # any longer than the cutover itself.
      termination_wait_time_in_minutes = var.termination_wait_time_in_minutes
    }
  }
  auto_rollback_configuration {
    enabled = var.auto_rollback_enabled
    events  = var.auto_rollback_events
  }
  # CodeDeploy validates the service role at CreateDeploymentGroup. service_role_arn orders this after the
  # role but not after the attachment, so without this the race fails the apply rather than the first
  # deployment (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.code_deploy_iam_role]
}
