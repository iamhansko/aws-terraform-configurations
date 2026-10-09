resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name by default rather than a fixed one.
#
# The _monolithic template got uniqueness by slicing a segment out of a uuid it generated to stand in for
# AWS::StackId:
#
#   key_name = "key-$${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# That reads as an accident of the CloudFormation translation, but the property it bought is real: two
# copies of this project in one account do not collide. key_name_prefix is the provider's own way of
# getting it, so the uuid, the local that assembled a fake stack ARN around it, the random provider and the
# stack_name variable are all gone from this project - see the root's providers.tf.
resource "aws_key_pair" "key_pair" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates: the private key is written to Parameter
# Store under /ec2/keypair/<key-pair-id>, so it is retrievable without being a Terraform output.
#
# The key is in Terraform state either way - tls_private_key puts it there - so this parameter is not what
# exposes it. It is how the person using the project gets at it, and the root publishes the fetch command
# rather than the key.
#
# In this project the key is close to decoration, and that is worth saying so nobody goes looking for a way
# to use it. The instance sits in a VPC with no internet gateway, so there is no address to open an SSH
# connection to from outside; the way in is Session Manager, which needs no key. The key pair is kept
# because the _monolithic template created one and because an instance launched without key_name cannot
# have one added later without being replaced.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
