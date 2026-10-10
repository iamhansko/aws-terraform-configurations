# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
output "state_machine_arn" {
  value       = module.state_machine.arn
  description = "ARN of the state machine"
}
output "state_machine_console_url" {
  value       = module.state_machine.console_url
  description = "The state machine in the console, which draws the graph and colours the path each execution took. For this project that picture is most of the point"
}
output "demo_execution_arns" {
  value       = { for label, invocation in aws_lambda_invocation.demo_execution : label => jsondecode(invocation.result).executionArn }
  description = "The executions this apply started, by label. Read from the starter function's return value, which is why it returns the ARN at all - the _monolithic template's version returned nothing and reported through cfnresponse, so there was no way to find the execution it had started"
}
output "demo_execution_inputs" {
  value       = { for label, execution in var.demo_executions : label => execution }
  description = "What each execution was given. The invalid one has age 0, which fails the validate function's check - and the execution still finishes as SUCCEEDED, because a failed validation is not a failed execution. That distinction is what the demo is for"
}
output "list_executions_command" {
  value       = module.state_machine.list_executions_command
  description = "1. Every execution and how it ended. Both should read SUCCEEDED; the branch they took is what differs"
}
output "describe_execution_commands" {
  value       = { for label, invocation in aws_lambda_invocation.demo_execution : label => "aws stepfunctions describe-execution --execution-arn ${jsondecode(invocation.result).executionArn} --query '[status,input,output]' --output json" }
  description = "2. Each execution's input and output. The output is the SNS publish result, so comparing the two shows which notification state ran - the valid input reaches NotifySucceeded, the invalid one NotifyFailed"
}
output "execution_history_commands" {
  value       = { for label, invocation in aws_lambda_invocation.demo_execution : label => "aws stepfunctions get-execution-history --execution-arn ${jsondecode(invocation.result).executionArn} --query 'events[].[id,type,stateEnteredEventDetails.name,stateExitedEventDetails.name]' --output table" }
  description = "3. Every state each execution entered and left, in order. This is where the Choice state's decision is visible"
}
output "state_machine_log_group" {
  value       = module.state_machine.log_group_name
  description = "The execution log group. Declared here where the _monolithic template configured no logging at all while granting its role logs:* on every resource in the account"
}
output "function_log_commands" {
  value = {
    validate_data     = module.validate_data_function.logs_command
    process_data      = module.process_data_function.logs_command
    execution_starter = module.execution_starter_function.logs_command
  }
  description = "4. Each function's recent output. The validate function's log shows the object it was given, which is the quickest way to see why the Choice state went the way it did"
}
output "notification_subscription_count" {
  value       = module.notification_topic.subscription_count
  description = "How many addresses are subscribed. Zero - the default, and the _monolithic template's - means both notification states publish successfully and the message goes nowhere. The execution history records the publish as successful either way, so this is the only place that shows it"
}
output "pending_subscriptions_command" {
  value       = module.notification_topic.pending_subscriptions_command
  description = "5. Subscriptions and their state. A SubscriptionArn reading PendingConfirmation is an email nobody has clicked, and it delivers nothing until they do"
}
output "start_execution_command" {
  value       = module.state_machine.start_execution_command
  description = "6. Starts a run by hand, for inputs the two demo executions do not cover"
}
output "lambda_runtimes" {
  value = {
    validate_data     = module.validate_data_function.runtime
    process_data      = module.process_data_function.runtime
    execution_starter = module.execution_starter_function.runtime
  }
  description = "The runtime all three functions are on. The _monolithic template had two of them on python3.9, which has reached end of support"
}
