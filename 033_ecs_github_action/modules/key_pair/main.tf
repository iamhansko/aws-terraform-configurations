resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name by default rather than a fixed one.
#
# The _monolithic template got uniqueness by slicing a segment out of the uuid it generated to stand in for
# AWS::StackId:
#
#   key_name = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# key_name_prefix is the provider's own way of buying the same property - two copies of this project in one
# account do not collide on the key pair name.
resource "aws_key_pair" "key_pair" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates: the private half goes to Parameter Store
# under /ec2/keypair/<key-pair-id>, so it is retrievable without being a Terraform output.
#
# The key is in state either way - tls_private_key puts it there - so this parameter is not what exposes
# it. It is how a person gets at it, and the root exposes the fetch command rather than the key, because
# every output is also written into a README that an unauthenticated code-server serves (rules.md H-2).
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
