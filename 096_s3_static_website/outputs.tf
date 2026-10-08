# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from drifting
# apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2). There is an EC2
# instance in this root, but it is not that: it runs no code-server, serves no IDE, has no inbound rule and
# no key pair, and a Lambda function exists to terminate it as soon as it has finished uploading. Writing a
# README onto a host nobody can open and which is about to be destroyed would be writing it to nowhere.
#
# rules.md H-1 does not apply either, for a second reason on top of that one: it covers a root that
# declares both an EKS cluster and a vscode_ec2, and there is no cluster here. Neither kubectl, eksctl,
# helm nor docker is installed on the seeder, and none should be.
#
# Several of the values this project would most like to report cannot be known at apply time - whether the
# site answers, whether the backend answers, whether the upload ran at all - because they depend on a boot
# script that starts after apply returns. Those are commands rather than omissions.
output "website_url" {
  value       = module.website_bucket.website_url
  description = "The site. Expect a 404 for the first few minutes after apply: the objects are uploaded by the seeder instance once it has booted, installed Python and downloaded the game zip, which is minutes of work that apply does not wait for. A 404 that never clears is seeder_console_output_command"
}
output "bucket_name" {
  value       = module.website_bucket.bucket_name
  description = "Generated name of the bucket holding the site"
}
output "website_endpoint" {
  value       = module.website_bucket.website_endpoint
  description = "The website endpoint's hostname on its own, without the scheme. http only - an S3 website endpoint serves nothing else, which is what 097_cloudfront_s3_static_website puts a distribution in front of to fix"
}
output "backend_function_url" {
  value       = module.backend_lambda.function_url
  description = "The backend endpoint the page fetches the password from. Public and unauthenticated by design - see backend_function_url_is_public"
}
output "backend_function_url_is_public" {
  value       = module.backend_lambda.function_url_is_public
  description = "Whether the backend accepts unauthenticated requests. True, as the _monolithic template had it, and necessary: the caller is a browser with nothing to sign a request with. It means anyone who finds the URL gets the game password, which is also true of the hint files in the public bucket. Reported because it is the one thing about this project that is invisible from the outside until somebody else finds it"
}
output "backend_config_object_url" {
  value       = "${module.website_bucket.website_url}/${var.backend_config_object_key}"
  description = "The object the page reads to find the backend. Fetching this is the quickest way to tell a broken backend from a broken seed: if it 404s the seeder never got this far, and if it holds a different URL than backend_function_url above then the bucket was seeded against an older function"
}
output "website_check_command" {
  # %%{ rather than %{ because %{ opens a template directive in HCL and curl's format string uses the same
  # two characters. Written plainly it fails the plan with "http_code is not a valid template control
  # keyword".
  value       = "echo -n 'site:    '; curl -s -o /dev/null -w '%%{http_code}\\n' ${module.website_bucket.website_url}/; echo -n 'backend: '; curl -s -o /dev/null -w '%%{http_code}\\n' ${module.backend_lambda.function_url}"
  description = "Both halves of the demo in one command. 200 then 200 is a working site. 404 then 200 means the backend is up and the seed has not finished or has failed - go to seeder_console_output_command. 200 then 403 means the function URL has no public invoke permission, which should not be possible from this configuration"
}
output "backend_response_command" {
  value       = "curl -s ${module.backend_lambda.function_url}"
  description = "What the backend actually returns. Should be a JSON object with one password key. A body containing a literal dollar-brace GamePassword would mean the function is running the unrepaired CloudFormation source, which is the defect described in lambda_src/lambda_function/index.py"
}
output "bucket_contents_command" {
  value       = module.website_bucket.list_objects_command
  description = "What is in the bucket. Terraform uploads none of it, so an empty listing is the single most useful diagnostic here - it separates a seed that has not run from a site whose index document is named something else"
}
output "seeder_instance_id" {
  value       = module.site_seeder_ec2.instance_id
  description = "ID of the instance that fills the bucket. Named a seeder rather than a bastion, which is what the _monolithic template called it: nothing connects to it or through it"
}
output "seeder_console_output_command" {
  value       = module.site_seeder_ec2.console_output_command
  description = "Whether the upload ran, and whether it finished. The one diagnostic worth reaching for first: everything the instance does happens after apply has returned, so this log is the only record. The completion marker means success, the failure marker plus a traceback means the script ran and broke, and neither marker means it never started - look at the dnf and pip lines in that case"
}
output "seeder_session_command" {
  value       = module.site_seeder_ec2.session_command
  description = "A shell on the seeder while it is still alive. Session Manager rather than SSH, because there is no key pair and no inbound rule - which is also why AmazonSSMManagedInstanceCore is on the instance role"
}
output "seeder_logs_note" {
  value       = "seeded objects are not in Terraform state; terraform destroy relies on website_bucket_force_destroy = ${var.website_bucket_force_destroy} to empty the bucket"
  description = "The consequence of having an instance rather than Terraform write the content. With force_destroy false a destroy stops at BucketNotEmpty partway through and leaves the root half torn down, and nothing in a plan warns about it"
}
output "terminate_seeder_command" {
  value       = "aws lambda invoke --function-name ${module.terminate_seeder_lambda.name} --cli-binary-format raw-in-base64-out --payload '{\"instance_ids\":[\"${module.site_seeder_ec2.instance_id}\"]}' /dev/stdout"
  description = "Shuts the seeder down once the bucket looks right. This is the replacement for the _monolithic template's custom resource, which terminated the instance during stack creation - doing that from Terraform instead makes every later plan want to rebuild the instance it just destroyed, which is why terminate_seeder_after_seeding defaults to false. Running it by hand leaves state describing an instance that no longer exists, so run terraform destroy rather than another apply afterwards"
}
output "terminate_seeder_lambda_name" {
  value       = module.terminate_seeder_lambda.name
  description = "Name of the terminator function, for a payload different from the one above"
}
output "terminate_seeder_was_invoked" {
  value       = var.terminate_seeder_after_seeding
  description = "Whether apply invoked the terminator itself. False by default - see the variable, and the long note above aws_lambda_invocation in main.tf, for the two independent reasons"
}
output "terminate_seeder_result" {
  value       = length(aws_lambda_invocation.terminate_seeder) == 0 ? null : jsondecode(aws_lambda_invocation.terminate_seeder[0].result)
  description = "What the terminator returned, or null when it was not invoked. Decoded rather than raw, so a reader sees the instance state rather than a JSON string. jsondecode is guarded by the length check because the resource has count 0 by default and decoding null is an error rather than null"
}
output "lambda_logs_commands" {
  value = {
    backend          = module.backend_lambda.logs_command
    terminate_seeder = module.terminate_seeder_lambda.logs_command
  }
  description = "Recent output of each function. The backend's log is the only place an invocation is visible at all - the browser only reports whether its fetch succeeded, not why it failed"
}
output "seeder_user_data" {
  value       = module.site_seeder_ec2.user_data
  description = "The seeder's rendered boot script, including the Python it writes out. Worth being able to read without launching anything: the generated script is nested inside a shell heredoc, so a single CR in these .tf files turns the terminator into SEEDSCRIPT-carriage-return, the heredoc swallows the rest of the file and not one line of the script runs (rules.md A-4)"
}
