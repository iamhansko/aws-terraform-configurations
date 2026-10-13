# Plain outputs rather than the local.outputs map and workbench README that rules.md H-2 describes: this root
# has no vscode_ec2 workbench to write a README onto, so there is nothing for the map to feed.
output "skill_url" {
  value       = local.skill_url
  description = "The skill URL to enter in Kakao's chatbot admin center (skill server URL). The SAM template output only ARNs, so this had to be looked up in the console"
}
output "skill_test_command" {
  value       = "curl -s -X POST '${local.skill_url}' -H 'Content-Type: application/json' -d '{\"userRequest\":{\"utterance\":\"hello\",\"callbackUrl\":\"https://example.com/callback\"}}'"
  description = "Calls the skill the way Kakao does. The answer is the useCallback response; the callback function then runs - and posts to example.com, which discards it. Its log shows the run"
}
output "kakao_chatbot_function" {
  value       = module.chatbot_function.function_arn
  description = "Kakao Chatbot Function ARN, as the SAM template output it"
}
output "kakao_chatbot_function_role" {
  value       = module.chatbot_function.role_arn
  description = "IAM Role for Kakao Chatbot Function, as the SAM template output it"
}
output "callback_function" {
  value       = module.callback_function.function_arn
  description = "Kakao Chatbot Callback Function ARN, as the SAM template output it"
}
output "callback_function_role" {
  value       = module.callback_function.role_arn
  description = "IAM Role for Kakao Chatbot Callback Function, as the SAM template output it"
}
output "chatbot_log_command" {
  value       = module.chatbot_function.log_tail_command
  description = "Follows the skill function's log"
}
output "callback_log_command" {
  value       = module.callback_function.log_tail_command
  description = "Follows the callback function's log, where a failed callback post shows up"
}
output "layer_packages" {
  value       = module.layer.packages
  description = "Every distribution in the callback function's layer, as the builder read it back"
}
output "layer_build_log_command" {
  value       = module.layer.build_log_command
  description = "The layer builder's log, where a failed pip install is recorded in full"
}
