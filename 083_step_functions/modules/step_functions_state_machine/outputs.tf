output "arn" {
  value       = aws_sfn_state_machine.state_machine.arn
  description = "ARN of the state machine, which the starter function is given and which its IAM policy is scoped to (rules.md B-5)"
}
output "name" {
  value       = aws_sfn_state_machine.state_machine.name
  description = "Name of the state machine"
}
output "role_arn" {
  value       = aws_iam_role.state_machine.arn
  description = "ARN of the role the state machine runs as. Scoped to the two functions and the one topic its definition names, where the _monolithic template granted lambda:InvokeFunction, sns:Publish and logs:* on every resource in the account"
}
output "log_group_name" {
  value       = var.log_level == "OFF" ? null : aws_cloudwatch_log_group.state_machine[0].name
  description = "The execution log group, or null with logging off. The _monolithic template configured no logging while granting logs:* - so the permission existed and nothing wrote anything"
}
output "definition" {
  value       = aws_sfn_state_machine.state_machine.definition
  description = "The definition as Step Functions stored it. Built from a typed HCL object rather than a heredoc string, so this is the check that the object serialised to what was intended"
}
output "state_names" {
  value       = sort(keys(local.definition.States))
  description = "The states in the machine, for comparing against an execution history that stopped early"
}
output "console_url" {
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/states/home?region=${data.aws_region.current.region}#/statemachines/view/${aws_sfn_state_machine.state_machine.arn}"
  description = "The state machine in the console, which draws the graph and colours the path each execution took. For this project that visual is most of the value"
}
output "list_executions_command" {
  value       = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.state_machine.arn} --query 'executions[].[startDate,status,name]' --output table"
  description = "Every execution and how it ended. Both demo executions should read SUCCEEDED - the failing one fails its validation, not its execution, so it takes the NotifyFailed branch and finishes normally"
}
output "start_execution_command" {
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.state_machine.arn} --input '{\"data\":{\"name\":\"Someone\",\"age\":30}}'"
  description = "Starts a run by hand, for trying inputs the two demo executions do not cover"
}
