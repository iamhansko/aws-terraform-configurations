# Every value here is a projection of local.outputs in main.tf. Nothing in this file builds a value
# of its own: the same map is rendered into /home/ec2-user/README.md by the association at the bottom
# of main.tf, and an output written directly here would be missing from that README with nothing to
# say so - apply would succeed either way (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform does not allow an expression
# in an output's description ("Variables not allowed - Variables may not be used here"), so the
# wording is a literal in both places. The values are not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. It runs with authentication disabled on an instance whose role carries AdministratorAccess, so the URL is the credential"
}
output "instance_id" {
  value       = local.outputs.instance_id.value
  description = "ID of the code-server instance. Also the one EC2 instance in this project that the Config rule deliberately ignores"
}
output "session_manager_command" {
  value       = local.outputs.session_manager_command.value
  description = "Starts a shell through SSM, which works even with vscode_ingress_cidr_blocks narrowed to nothing. Requires the SSM agent to have registered, which it can only do with outbound access - if this hangs, read bootstrap_log_command"
}
output "port_forward_command" {
  value       = local.outputs.port_forward_command.value
  description = "Forwards the IDE port to localhost through SSM. The safe way to use this instance with the ingress list narrowed"
}
output "private_key_parameter" {
  value       = local.outputs.private_key_parameter.value
  description = "SSM parameter holding the generated private key. Read it with: aws ssm get-parameter --with-decryption --name <this> --query Parameter.Value --output text"
}
output "config_recorder_status_command" {
  value       = local.outputs.config_recorder_status_command.value
  description = "Start here, because everything downstream is silent when this is wrong. recording: false means the recorder exists but was never started, and a change-triggered rule with no configuration items evaluates nothing, forever, with no error"
}
output "config_rule_name" {
  value       = local.outputs.config_rule_name.value
  description = "Name of the rule. It requires an instance's profile to hold exactly one role whose attached managed policies are exactly AmazonS3ReadOnlyAccess, and exempts this project's own workbench by Name tag"
}
output "governed_instance_profiles" {
  value       = local.outputs.governed_instance_profiles.value
  description = "The instance profiles created for this demo, with what each one is supposed to show. They are attached to nothing: an instance has to carry one before there is anything to evaluate"
}
output "launch_test_instance_commands" {
  value       = local.outputs.launch_test_instance_commands.value
  description = "Launches one instance per fixture into this project's public subnet, each carrying one of the governed instance profiles. These are not Terraform resources, so terraform destroy does not remove them"
}
output "force_evaluation_command" {
  value       = local.outputs.force_evaluation_command.value
  description = "Replays the rule against what has already been recorded, instead of waiting for the next change. Returns immediately and evaluates asynchronously"
}
output "compliance_details_command" {
  value       = local.outputs.compliance_details_command.value
  description = "One row per evaluated instance. An empty table right after apply is the expected state rather than a failure - the rule has had nothing to judge yet. Once the test instances are evaluated both read COMPLIANT, because the handler rewrote their roles before it finished reporting"
}
output "fixture_policy_check_command" {
  value       = local.outputs.fixture_policy_check_command.value
  description = "What is attached to each fixture role now. The handler remediates what it judges, so after one evaluation this shows AmazonS3ReadOnlyAccess where the fixture started with AdministratorAccess - and terraform plan will then want to reattach it. The NON_COMPLIANT verdict itself is overwritten by the COMPLIANT one the same invocation sends afterwards, so the log rather than the compliance API is where it can be seen"
}
output "lambda_log_command" {
  value       = local.outputs.lambda_log_command.value
  description = "The handler's log, and the only place a rule that never evaluates leaves evidence. From the Config side a missing handler, an AccessDenied and a timeout are indistinguishable"
}
output "terminate_test_instances_command" {
  value       = local.outputs.terminate_test_instances_command.value
  description = "Terminates the test instances and waits until they are gone. Run it before terraform destroy: an instance still holding a governed instance profile blocks deleting that profile, and one still in this project's subnet stops the destroy at the subnet and the internet gateway with DependencyViolation"
}
output "config_bucket_name" {
  value       = local.outputs.config_bucket_name.value
  description = "Where configuration history and snapshots are written. Holds objects Terraform never created, which is why config_bucket_force_destroy defaults to true"
}
output "config_snapshot_list_command" {
  value       = local.outputs.config_snapshot_list_command.value
  description = "What has been delivered. Empty for the first hour is normal; empty together with a FAILURE in the recorder status is a permissions problem"
}
output "bootstrap_log_command" {
  value       = local.outputs.bootstrap_log_command.value
  description = "The workbench user data log. The script runs with set -x, so this is the first place to look when code-server does not answer"
}
