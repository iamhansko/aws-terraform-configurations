locals {
  # The bucket name, composed once. The _monolithic template wrote this expression twice - once as the
  # bucket's name and once inside the literal ARN it handed to the lambda permission - because referencing
  # the bucket from the permission would have closed a cycle. Here it exists once and the permission takes a
  # real ARN reference instead, which is only possible because the notification sits in this root rather than
  # inside either module (rules.md B-3/B-5, and modules/event_source_bucket/main.tf for the cycle).
  bucket_name = "${var.bucket_name_prefix}${var.random_string}"
}
module "event_source_bucket" {
  source = "./modules/event_source_bucket"

  bucket_name       = local.bucket_name
  versioning_status = var.bucket_versioning_status
  force_destroy     = var.bucket_force_destroy

  # Only so the module can build an upload command that lands on a key the notification actually reacts to.
  # The notification itself is configured below.
  notification_filter_prefix = var.notification_filter_prefix
  masked_object_prefix       = var.masked_object_prefix
}
module "lambda_function" {
  source = "./modules/lambda_function"

  function_name    = var.lambda_function_name
  source_directory = "${path.root}/${var.lambda_source_directory}"
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  log_tail_minutes = var.log_tail_minutes

  iam_policy_arns              = var.lambda_iam_policy_arns
  additional_policy_statements = var.lambda_additional_policy_statements

  # A reference to the bucket, not a reassembled arn:aws:s3:::<name> string. This is the one direction the
  # dependency may run in: the function may know which bucket invokes it, the bucket may not know which
  # function it invokes, and the notification below closes the loop from outside both of them.
  source_bucket_arn = module.event_source_bucket.bucket_arn
}
# The wiring between the two modules, and the only resource in this root.
#
# It lives here rather than in the bucket module for the reasons set out in that module's main.tf: putting it
# there would make the two modules reference each other and Terraform would reject the configuration with a
# cycle. Joining two modules that know nothing about each other is the root's job in any case (rules.md C-1).
#
# Note that this resource is authoritative over the bucket's whole notification configuration, so it is the
# complete statement of what this bucket notifies - not an addition to whatever else might be configured.
resource "aws_s3_bucket_notification" "event_source_bucket" {
  bucket = module.event_source_bucket.bucket_name

  lambda_function {
    lambda_function_arn = module.lambda_function.function_arn
    events              = var.notification_events
    # Restores the Filter the conversion dropped as a TODO comment. Null omits the attribute entirely, which
    # reproduces the converted behaviour of invoking on every key in the bucket - including the masked copies
    # the function itself writes (see the variable's description for why that does not become a loop).
    filter_prefix = var.notification_filter_prefix
  }

  # Referencing module.lambda_function.function_arn orders this after the function resource and after nothing
  # else in that module - in particular not after the aws_lambda_permission that allows S3 to invoke it
  # (rules.md D-1/D-2). That ordering is not optional here. S3 validates the destination while
  # PutBucketNotificationConfiguration is being applied, by checking it is allowed to invoke the target, so
  # without the permission in place first the apply fails outright with:
  #
  #   Error: putting S3 Bucket Notification Configuration: InvalidArgument: Unable to validate the following
  #   destination configurations
  #
  # which names neither the permission nor the function. depends_on on the module block covers every resource
  # in it, so the permission is included whatever else that module grows.
  depends_on = [module.lambda_function]
}
