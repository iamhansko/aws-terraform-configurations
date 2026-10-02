output "role_arn" {
  value       = aws_iam_role.fis_iam_role.arn
  description = "ARN of the role FIS assumes to act on the targets. Carries only the EC2 access policy - the _monolithic template also gave it fis:* on *, which an experiment role has no use for: it acts on the target service, not on FIS"
}
output "role_name" {
  value       = aws_iam_role.fis_iam_role.name
  description = "Name of that role, generated unless role_name was set so two deployments in one account do not collide"
}
output "template_ids" {
  value = merge(
    var.stop_instance_experiment == null ? {} : { stop_instance = aws_fis_experiment_template.stop_instance[0].id },
    var.spot_interruption_experiment == null ? {} : { spot_interruption = aws_fis_experiment_template.spot_interruption[0].id },
  )
  description = "Experiment template ID per enabled experiment, keyed by kind. A template is not a running experiment - starting one is a separate API call, which is deliberately left to the operator (see start_commands)"
}
output "target_name_tags" {
  value = merge(
    var.stop_instance_experiment == null ? {} : { stop_instance = var.stop_instance_experiment.name_tag },
    var.spot_interruption_experiment == null ? {} : { spot_interruption = var.spot_interruption_experiment.name_tag },
  )
  description = "The Name tag each experiment searches for, re-exposed so a mismatch with what the node pools actually tag is visible in terraform output rather than only as a failed experiment (rules.md B-5)"
}
output "start_commands" {
  value = merge(
    var.stop_instance_experiment == null ? {} : {
      stop_instance = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.stop_instance[0].id} --query 'experiment.{Id:id,State:state.status}' --output table"
    },
    var.spot_interruption_experiment == null ? {} : {
      spot_interruption = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.spot_interruption[0].id} --query 'experiment.{Id:id,State:state.status}' --output table"
    },
  )
  description = "How to run each experiment. A command rather than something the apply does: starting one takes a node away and costs money, and an experiment started during an apply would have finished before anyone could watch it"
}
output "experiment_list_command" {
  value       = "aws fis list-experiments --query 'experiments[].{Id:id,Template:experimentTemplateId,State:state.status,Started:creationTime}' --output table"
  description = "Every experiment run in this account, with its final state. failed here with a template whose targets look right is usually empty target resolution - the tag matched nothing, which is what empty_target_resolution_mode = fail makes visible"
}
output "experiment_detail_command" {
  value       = "aws fis get-experiment --id <experiment-id> --query '{State:state,Targets:targets,Actions:actions}'"
  description = "What one experiment actually resolved to and did. The Targets section lists the instances it selected, which is the only record of whether the Name tag matched what was intended"
}
