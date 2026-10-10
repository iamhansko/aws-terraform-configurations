resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name rather than a fixed one. The _monolithic template got uniqueness by slicing a segment out
# of the uuid it generated to stand in for AWS::StackId; key_name_prefix is the provider's own way of getting
# the same property, and using it drops the random provider (see the root providers.tf).
resource "aws_key_pair" "key_pair" {
  key_name_prefix = var.key_name_prefix
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates: the private half is written to Parameter
# Store under /ec2/keypair/<key-pair-id>, so it is retrievable without being a Terraform output.
#
# The key is in state either way - tls_private_key puts it there - so this parameter is not what exposes it.
# It is how a person gets at it, and the root publishes the fetch command rather than the key.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
