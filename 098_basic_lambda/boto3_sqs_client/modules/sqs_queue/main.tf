# The queue that sits between the function and the worker instance, and the whole point of the project: the
# function URL accepts a burst of HTTP requests, each one becomes a message, and the worker drains them at
# whatever rate it manages.
#
# There is deliberately no aws_sqs_queue_policy here, and that is worth saying because it is the resource
# where CloudFormation conversions go wrong. AWS::SQS::QueuePolicy takes a Queues list, while Terraform's
# aws_sqs_queue_policy.queue_url is a single string, so a converted template often carries
# queue_url = jsonencode([aws_sqs_queue.x.id]) - a JSON array handed to a string attribute. validate and plan
# both pass, and the apply fails with a malformed queue url from the SQS API (rules.md A-3). Nothing needs a
# queue policy here: both principals that touch this queue are IAM roles in the same account, so their own
# identity policies are sufficient.
#
# No dead letter queue either, which is the other thing missing from the original. The worker deletes a
# message only after logging success, so a message whose processing throws becomes visible again after the
# visibility timeout and is retried forever. For a demo that is the intended behaviour - the retry is what
# makes the message count drain to zero - but it is not what a real consumer would want.
resource "aws_sqs_queue" "queue" {
  name                       = var.name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
}
