# Three identical IAM roles whose policy documents are written three different ways.
#
# That is the project, and it needs restating because the translation moved it. The _monolithic template's
# three roles differed in how CloudFormation was given the document - a YAML mapping, a JSON mapping, and a
# JSON string - which is a distinction that does not survive into Terraform: HCL has no YAML form. What does
# survive is the underlying question, "what are the ways of producing a policy document, and do they agree",
# and Terraform has three answers of its own. They are below, in the same order.
#
# All three are handed to the same module, which cannot tell them apart. Comparing the three
# read_policies_command outputs is how the answer becomes visible (rules.md B-6).
locals {
  # Style 1: an HCL object through jsonencode. The ordinary choice, and the one every other project in this
  # repository uses - the document is data, so the type checker and the editor can see into it.
  hcl_object_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = var.trusted_service }
      Action    = "sts:AssumeRole"
    }]
  })
  hcl_object_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = var.policy_actions
      Resource = var.policy_resources
    }]
  })
  # Style 3: a heredoc JSON literal with interpolation. The form that looks most like the original template's
  # third role, and the one with the sharpest edge: the document is a string, so nothing checks it until IAM
  # does. A trailing comma here is an apply-time error, which is why the module validates with jsondecode
  # (rules.md B-1).
  #
  # jsonencode is used for the interpolated lists rather than joining them by hand, because a list written
  # into JSON by hand is how a single-element list becomes a bare string.
  heredoc_assume_role_policy = <<-JSON
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": ${jsonencode(var.trusted_service)} },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  JSON
  heredoc_policy             = <<-JSON
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": ${jsonencode(var.policy_actions)},
          "Resource": ${jsonencode(var.policy_resources)}
        }
      ]
    }
  JSON
}
# Style 2: the provider's own document builder. Between the other two - the structure is checked by the
# provider's schema rather than by jsonencode accepting any object, so a misspelled argument name is a plan
# error instead of a document IAM ignores. The cost is that it is two more resources in the graph and the
# document is only readable after a plan.
data "aws_iam_policy_document" "data_source_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [var.trusted_service]
    }
  }
}
data "aws_iam_policy_document" "data_source_policy" {
  statement {
    effect    = "Allow"
    actions   = var.policy_actions
    resources = var.policy_resources
  }
}
module "hcl_object_role" {
  source = "./modules/iam_role"

  name_prefix             = "${var.project_name}-hcl-object-"
  description             = "Trust and permissions policies written as HCL objects and serialised with jsonencode"
  assume_role_policy_json = local.hcl_object_assume_role_policy
  inline_policy_name      = var.policy_name
  inline_policy_json      = local.hcl_object_policy
}
module "data_source_role" {
  source = "./modules/iam_role"

  name_prefix             = "${var.project_name}-data-source-"
  description             = "Trust and permissions policies built with the aws_iam_policy_document data source"
  assume_role_policy_json = data.aws_iam_policy_document.data_source_assume_role_policy.json
  inline_policy_name      = var.policy_name
  inline_policy_json      = data.aws_iam_policy_document.data_source_policy.json
}
module "heredoc_role" {
  source = "./modules/iam_role"

  name_prefix             = "${var.project_name}-heredoc-"
  description             = "Trust and permissions policies written as JSON string literals"
  assume_role_policy_json = local.heredoc_assume_role_policy
  inline_policy_name      = var.policy_name
  inline_policy_json      = local.heredoc_policy
}
