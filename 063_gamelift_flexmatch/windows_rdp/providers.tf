terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    awscc  = { source = "hashicorp/awscc", version = "~> 1.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    # Back for a different function than the one it packaged in _monolithic - see below.
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}
provider "aws" {
  region = var.aws_region
}
# The only root in this repository with a second AWS provider, and the reason is
# the subject of the project.
#
# FlexMatch is two resources: a matchmaking rule set and a matchmaking
# configuration. hashicorp/aws has neither - the conversion in _monolithic left
# both as NOT CONVERTED comments, and with them gone the game-match-request
# function calls StartMatchmaking against a configuration that does not exist,
# so every match request returns MatchError and nothing else in the project has
# anything to do. hashicorp/awscc is generated from the CloudFormation resource
# schemas, which is where those two types live, so it carries them as
# awscc_gamelift_matchmaking_rule_set and
# awscc_gamelift_matchmaking_configuration. Only modules/gamelift_matchmaking
# uses it.
#
# Same region as the aws provider, explicitly: the configuration names a game
# session queue and an SNS topic that the aws provider creates, and the
# matchmaker has to live beside them. Both providers fall back to the same
# chain when aws_region is null, so this states what would happen anyway rather
# than leaving the two to agree by accident.
provider "awscc" {
  region = var.aws_region
}
# What else differs from the _monolithic template's provider set.
#
# archive now zips modules/s3_object_waiter's handler - the function that holds
# the six game functions and the GameLift build until the instance's uploads are
# in S3 (main.tf has why the association cannot). What it packaged in
# _monolithic is still gone: secret_plaintext_lambda, a CloudFormation custom
# resource whose only job was reading the generated password back into an
# output. It could not have worked here: index.py imports cfnresponse, which
# Lambda injects only into functions whose code was inlined as ZipFile, and it
# speaks the custom resource protocol - event['RequestType'], ResourceProperties,
# a POST to ResponseURL - while aws_lambda_invocation does a plain synchronous
# invoke and reads a return value the handler never produces. The function, its
# role, the archive and the invocation are all dropped; the password is exposed
# as a retrieval command instead (modules/app_secret). lambda_src/ stays on disk
# unreferenced, because the _monolithic copy still names it.
#
# random is still here, for the workshop password - and no longer for a uuid.
# The template generated random_uuid to stand in for AWS::StackId and sliced a
# segment out of it to name the key pair; key_name_prefix does that directly.
#
# tls generates the key pair. On Windows its private half is how the built-in
# Administrator password is decrypted, so modules/key_pair writes it to
# Parameter Store the way CloudFormation would have.
