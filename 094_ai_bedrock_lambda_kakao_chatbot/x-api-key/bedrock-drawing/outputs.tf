# Plain outputs rather than the local.outputs map and workbench README that rules.md H-2 describes: this root
# has no vscode_ec2 workbench to write a README onto, so there is nothing for the map to feed.
output "skill_url" {
  value       = local.skill_url
  description = "The skill URL to enter in Kakao's chatbot admin center (skill server URL). The SAM template output only ARNs, so this had to be looked up in the console"
}
output "api_key_value_command" {
  value       = module.skill_api.api_key_value_command
  description = "Prints the API key to enter as the x-api-key header value in Kakao's chatbot admin center. A command rather than the key, so terraform output does not print it"
}
output "skill_test_command" {
  value       = "curl -s -X POST '${local.skill_url}' -H 'Content-Type: application/json' -H \"x-api-key: $(${module.skill_api.api_key_value_command})\" -d '{\"userRequest\":{\"utterance\":\"hello\",\"callbackUrl\":\"https://example.com/callback\"}}'"
  description = "Calls the skill the way Kakao does. The answer is the useCallback response; the callback function then runs - and calls Bedrock - and posts to example.com, which discards it. Its log shows the run"
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
  description = "Follows the callback function's log, where a failed Bedrock call or callback post shows up"
}
output "layer_packages" {
  value       = module.layer.packages
  description = "Every distribution in the callback function's layer, as the builder read it back"
}
output "layer_build_log_command" {
  value       = module.layer.build_log_command
  description = "The layer builder's log, where a failed pip install is recorded in full"
}
output "text_to_image_s3_bucket" {
  value       = module.image_bucket.bucket_arn
  description = "Text to Image S3 Bucket ARN, as the SAM template output it. Public for reads of single objects"
}
output "images_list_command" {
  value       = module.image_bucket.list_command
  description = "Lists the generated images"
}
