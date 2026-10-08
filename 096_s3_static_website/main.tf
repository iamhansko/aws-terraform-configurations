data "aws_region" "current" {}
# The AMI id for the seeder, from the public parameter AWS maintains for the latest Amazon Linux 2023.
#
# insecure_value rather than value: the provider marks value sensitive for every parameter whatever its
# type, and a sensitive value cannot be used as an instance's ami attribute without nonsensitive().
# insecure_value is the provider's own accessor for a parameter that is not a secret, and a public AMI id
# is not one. This is what the _monolithic file did too.
#
# Declared in the root and the resolved id passed into the module, so the module takes an ami- id and does
# not have to know where it came from (rules.md B-6). It also keeps the lookup out of a module carrying
# depends_on, which would defer the read to apply (rules.md D-6).
data "aws_ssm_parameter" "seeder_ami_id" {
  name = var.seeder_ami_ssm_parameter_name
}
# Both Lambda zips are built here rather than inside the lambda_function module, and the reason is
# rules.md D-6 rather than taste.
#
# Every module in this root carries depends_on, because the root has a network module and the rule admits
# no exceptions (rules.md D-3). A module-level depends_on defers every data source declared inside that
# module until apply - so an archive_file in there would leave filename and source_code_hash unknown at
# plan, and a changed index.py would stop showing up as a plan diff. Up here the hash is computed at plan
# time and an edited function is visible before it is applied.
#
# source_dir rather than the _monolithic file's source_file. A single file works until the function gains a
# second one, and then the second one is silently missing from the package and the function fails at import
# with ModuleNotFoundError.
data "archive_file" "backend_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/${var.backend_lambda_source_dir}"
  output_path = "${path.module}/build/backend_lambda.zip"
}
data "archive_file" "terminate_seeder_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/${var.terminate_seeder_lambda_source_dir}"
  output_path = "${path.module}/build/terminate_seeder_lambda.zip"
}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  availability_zone_suffix = var.availability_zone_suffix
  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_route_table_name  = "${var.project_name}-public-rt"
  public_subnet_name       = "${var.project_name}-public"
}
module "website_bucket" {
  source = "./modules/static_website_bucket"

  name_prefix    = "${var.project_name}-"
  index_document = var.website_index_document
  error_document = var.website_error_document
  force_destroy  = var.website_bucket_force_destroy

  # A bucket is a regional service with no network attachment, so this edge buys nothing on its own. It is
  # here because the rule is that a root with a network module has no module starting before that module
  # finishes - an exception would mean the next reader has to decide per module whether the omission was
  # reasoned or forgotten (rules.md D-3). It also fixes the destroy order, which matters here: the bucket
  # goes after the instance that was writing to it.
  depends_on = [module.network]
}
module "backend_lambda" {
  source = "./modules/lambda_function"

  # Derived from the project name, not the _monolithic template's literal "Backend". Lambda function names
  # are unique per account and region, so that literal fails a second apply in one account with
  # ResourceConflictException - and "Backend" in an account's function list says nothing about which stack
  # owns it.
  name               = "${var.project_name}-backend"
  filename           = data.archive_file.backend_lambda.output_path
  source_code_hash   = data.archive_file.backend_lambda.output_base64sha256
  handler            = var.lambda_handler
  runtime            = var.lambda_runtime
  timeout            = var.lambda_timeout
  memory_size        = var.lambda_memory_size
  log_retention_days = var.lambda_log_retention_days

  # The password the function returns. The _monolithic template put it in the function's source as the
  # CloudFormation placeholder ${GamePassword}; the conversion to Terraform dropped the substitution, so
  # the source on disk still carried the placeholder verbatim and the function would have served the
  # literal six characters to the browser. An environment variable is the substitution Terraform can
  # actually perform.
  environment_variables = {
    (var.game_password_environment_variable) = var.game_password
  }

  # Public, unauthenticated, and deliberately so: the page is served from an S3 website hostname with no
  # credentials to sign a request with, and the value it fetches is a game password that the hint files in
  # the same bucket already give away. Everything about that is the _monolithic template's design. It is
  # not a shape to copy into anything that is not meant to be world-readable.
  create_function_url             = true
  function_url_authorization_type = var.backend_function_url_authorization_type
  function_url_invoke_mode        = var.backend_function_url_invoke_mode
  function_url_allow_origins      = var.backend_function_url_allow_origins

  # Nothing to do with the VPC - a Lambda function outside one is a regional service. Same reasoning as the
  # bucket above (rules.md D-3).
  depends_on = [module.network]
}
module "site_seeder_ec2" {
  source = "./modules/site_seeder_ec2"

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id
  ami_id    = data.aws_ssm_parameter.seeder_ami_id.insecure_value

  instance_name                = "${var.project_name}-seeder"
  instance_type                = var.seeder_instance_type
  associate_public_ip_address  = var.seeder_associate_public_ip_address
  security_group_name          = "${var.project_name}-seeder-sg"
  ingress_cidr_blocks          = var.seeder_ingress_cidr_blocks
  iam_policy_arns              = var.seeder_iam_policy_arns
  instance_profile_name_prefix = "${var.project_name}-seeder-"

  # Both the name and the ARN. The name is what the script PUTs into; the ARN is what the instance role's
  # s3:PutObject statement is scoped to. Passing both rather than assembling the ARN from the name, because
  # an assembled ARN that is wrong produces AccessDenied on every upload and reads exactly like a missing
  # policy (rules.md B-6).
  bucket_name = module.website_bucket.bucket_name
  bucket_arn  = module.website_bucket.bucket_arn

  # The endpoint the page fetches the password from, written into an object in the bucket. It does not
  # exist until Lambda has created the function URL, which is what orders this module after that one.
  backend_function_url = module.backend_lambda.function_url
  backend_config_key   = var.backend_config_object_key

  game_source_url      = var.game_source_url
  content_types        = var.seeder_content_types
  default_content_type = var.seeder_default_content_type
  text_objects         = var.game_hint_text_objects
  image_objects        = var.game_hint_image_objects

  python_package      = var.seeder_python_package
  python_requirements = var.seeder_python_requirements
  dnf_packages        = var.seeder_dnf_packages
  dnf_groups          = var.seeder_dnf_groups

  # Value references order this after the resources that produced each value and nothing else, which is
  # not enough for either of the two it takes values from (rules.md D-2):
  #
  #   - module.website_bucket.bucket_name is the bucket resource. The public access block and the bucket
  #     policy are separate resources, and the policy is what makes the uploaded objects readable. A seed
  #     that wins that race uploads successfully and the site still 403s until the policy lands - which
  #     resolves on its own, but looks like a broken upload while it does not.
  #   - module.network.public_subnet_a_id orders this after that one subnet, not after the route to the
  #     internet gateway or its attachment. The script starts fetching from github.com within a couple of
  #     minutes of launch, and losing that race leaves the download failing with a DNS or routing error
  #     and the bucket empty - with apply already reported as successful (rules.md D-3).
  #
  # Destroy runs this in reverse, which is the other half: the instance goes before the bucket it was
  # writing to and before the function whose URL it embedded.
  depends_on = [module.network, module.website_bucket, module.backend_lambda]
}
# The second function from the _monolithic template, which was a CloudFormation custom resource whose only
# job was to terminate the seeder once it had finished uploading.
#
# It is reproduced as a plain function that anyone can invoke, not as a custom resource. See
# aws_lambda_invocation below for why its automatic invocation is off by default, and
# lambda_src/custom_resource_lambda_function/index.py for what the original source could and could not do.
module "terminate_seeder_lambda" {
  source = "./modules/lambda_function"

  name               = "${var.project_name}-terminate-seeder"
  filename           = data.archive_file.terminate_seeder_lambda.output_path
  source_code_hash   = data.archive_file.terminate_seeder_lambda.output_base64sha256
  handler            = var.lambda_handler
  runtime            = var.lambda_runtime
  timeout            = var.lambda_timeout
  memory_size        = var.lambda_memory_size
  log_retention_days = var.lambda_log_retention_days

  # The _monolithic template gave this role an inline policy of ec2:* on "*", on top of
  # AWSLambdaBasicExecutionRole. The function makes exactly one call, TerminateInstances, against exactly
  # one instance. Narrowing it is a change to what the original did, which rules.md A-5 permits for an
  # automated role provided it is written down - and the direction is the one that rule insists on.
  #
  # Scoped in the root rather than inside the module because the instance ARN belongs to a different
  # module, and joining two modules' outputs is the root's job (rules.md C-1). It also means the policy
  # cannot name an instance this project did not create.
  additional_policy_statements = [{
    Effect   = "Allow"
    Action   = ["ec2:TerminateInstances"]
    Resource = [module.site_seeder_ec2.instance_arn]
  }]

  # No function URL: nothing outside the account should be able to terminate an instance.
  create_function_url = false

  # After the instance, both because the policy above names it and because destroy then removes this
  # function before the instance it is allowed to terminate (rules.md D-2). Reachable from network through
  # module.site_seeder_ec2, which is what rules.md D-3 asks for - the edge composes, so repeating
  # module.network here would add nothing to the graph.
  depends_on = [module.site_seeder_ec2]
}
# Terminating the seeder during apply, which is what the _monolithic template's custom resource did. Off by
# default, and that default is the one deliberate behavioural change in this project.
#
# Two separate problems, and only the first is fixable:
#
#   1. The converted invocation could not have worked at all. aws_lambda_invocation does a synchronous
#      invoke and reads the return value; a CloudFormation custom resource handler reads
#      event['RequestType'] and POSTs its result to event['ResponseURL']. The original handler imported
#      cfnresponse - a module AWS injects only into functions whose code was inlined as ZipFile, not into
#      a zip built by archive_file - and terminated the instance id that an Fn::Sub had substituted into
#      its source, a substitution the conversion dropped. With input = jsonencode({}) it would also have
#      had no ResponseURL to post to. Four independent reasons, any one of them fatal. The repaired
#      handler takes instance_ids from the payload and returns a value, which fixes all four.
#
#   2. Terminating a managed aws_instance makes this root churn forever. The provider treats a terminated
#      instance as gone, so the next refresh drops it from state and the next plan proposes to create it
#      again; that changes the instance id, which changes this resource's input, which re-invokes and
#      terminates the new one. Every plan is dirty and every apply rebuilds and re-seeds. CloudFormation
#      did not have this problem because its custom resource ran once at stack create and the stack never
#      reconciled the instance again.
#
# So the capability is kept and the automatic call is not. Turn this on to watch the original behaviour,
# including the churn; leave it off and use the root's terminate_seeder_command when the seed is done,
# which does the same thing without Terraform expecting the instance to still be there.
resource "aws_lambda_invocation" "terminate_seeder" {
  count = var.terminate_seeder_after_seeding ? 1 : 0

  function_name = module.terminate_seeder_lambda.name
  # The instance id as a payload value, where the original had it substituted into the function's source.
  # The handler reads this key; an empty object - which is what the conversion passed - makes it raise
  # rather than terminate something unexpected.
  input = jsonencode({
    instance_ids = [module.site_seeder_ec2.instance_id]
  })

  # The invoke has to happen after the instance has finished seeding, which Terraform cannot observe - it
  # only knows the instance exists. This edge is the same one the conversion had, and it is as close as
  # this gets: the seed takes several minutes after the instance is running, so switching this on will
  # usually terminate the instance partway through the upload and leave a half-filled bucket. That is the
  # other half of why it is off (rules.md D-2).
  depends_on = [module.site_seeder_ec2, module.terminate_seeder_lambda]
}
