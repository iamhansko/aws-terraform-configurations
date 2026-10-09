resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name by default rather than a fixed one.
#
# The _monolithic template got uniqueness by generating a uuid to stand in for AWS::StackId and then slicing
# a segment out of it:
#
#   key_name = "key-$${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# That is an artefact of the CloudFormation translation, but the property it bought is real - two copies of
# this project in one account do not fail with InvalidKeyPair.Duplicate. key_name_prefix is the provider's
# own way of getting it, so the uuid, the random provider it needed and the stack_name variable that fed the
# ARN it was spliced into are all gone from this variant. See providers.tf in the root.
resource "aws_key_pair" "key_pair" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates, which is what the _monolithic template was
# imitating: the private half is written to Parameter Store under /ec2/keypair/<key-pair-id>, so it is
# retrievable without being a Terraform output.
#
# The key is in Terraform state either way, because tls_private_key puts it there - this parameter is not
# what exposes it. It is how the person running the project gets at it, and the root publishes the fetch
# command rather than the key.
#
# This project needs it less than most. Both instances are reachable another way - code-server in a browser
# for the workbench, SSM Session Manager for the app server - and the app server's security group opens no
# SSH port at all. It stays because the _monolithic template created it and because an instance whose
# userdata failed early is sometimes only reachable over SSH.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
