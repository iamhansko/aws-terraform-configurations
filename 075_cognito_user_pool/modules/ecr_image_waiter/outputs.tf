# repository_names and image_tags come back out of the invocation's result rather than straight from the inputs.
# That is what makes a lookup named through them wait for the invocation: while it is being created or replaced
# the result is unknown, so the lookup is deferred to apply and runs after it; once it is in state the result is
# known and the lookup happens at plan, which is how a tag pushed over by hand is seen (rules.md B-5).
#
# Keyed by the caller's labels, which are configuration literals, so a for_each over the caller's own map stays
# known at plan while these values are not (rules.md B-8).
output "repository_names" {
  value       = { for label, image in jsondecode(aws_lambda_invocation.wait.result).images : label => image.repository_name }
  description = "Repository of each image, per label, known only once the function has seen every tag there"
}
output "image_tags" {
  value       = { for label, image in jsondecode(aws_lambda_invocation.wait.result).images : label => image.image_tag }
  description = "Tag of each image, per label, known only once the function has seen every tag there"
}
