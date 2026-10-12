output "function_names" {
  value       = local.function_names
  description = "The seven functions, keyed by the blueprint module their handler is in"
}
output "admin_rule_arn" {
  value       = aws_lb_listener_rule.admin.arn
  description = "ARN of the /admin listener rule whose condition the functions rewrite while ComfyUI is down"
}
output "admin_rule_paths_command" {
  value       = "aws elbv2 describe-rules --rule-arns ${aws_lb_listener_rule.admin.arn} --query 'Rules[0].Conditions[0].PathPatternConfig.Values' --output text"
  description = "Which paths the admin page currently answers: /admin alone while ComfyUI is up, / and /admin while it is down or scaling"
}
output "status_command" {
  # Through a file in the working directory rather than /dev/stdout, which the AWS CLI cannot open on Windows.
  value       = "aws lambda invoke --function-name ${local.function_names.admin} --payload '{}' --cli-binary-format raw-in-base64-out comfyui-admin.json > /dev/null && grep -oE \"id='status-message'>[^<]*|href='/admin/[a-z]+'|Error occurred[^<]*\" comfyui-admin.json | sort -u; rm -f comfyui-admin.json"
  description = "What the /admin page would show, read by invoking its function directly: the links it offers (/admin/scaleup when the instance is off, /admin/restart and /admin/shutdown while ComfyUI runs) and its status line"
}
