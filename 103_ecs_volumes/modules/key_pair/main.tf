resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name by default rather than a fixed one.
#
# The _monolithic template got uniqueness by slicing a segment out of the uuid it generated to stand in
# for AWS::StackId:
#
#   key_name = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# That reads as an accident of the CloudFormation translation, but the property it bought is real: two
# copies of this project in one account do not collide. key_name_prefix is the provider's own way of
# getting it, and dropping the uuid drops the random provider with it.
resource "aws_key_pair" "key_pair" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates: the private key is written to Parameter
# Store under /ec2/keypair/<key-pair-id>, so it is retrievable without being an output.
#
# The key is in Terraform state either way - tls_private_key puts it there - so this parameter is not
# what exposes it. It is how a person gets at it, and the root exposes the fetch command rather than the
# key itself.
#
# Worth knowing what this key is and is not for in this project. Neither security group opens 22, so
# nothing is reachable over SSH as built; both instance roles carry AdministratorAccess and both AMIs
# ship the SSM agent, so Session Manager is the way onto a box. This key pair exists because the
# _monolithic template attached one to both the builder instance and the container instance launch
# template, and because it is the fallback when the agent itself is what is broken.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
