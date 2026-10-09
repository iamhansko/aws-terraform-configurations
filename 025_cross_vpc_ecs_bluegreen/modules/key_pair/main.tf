resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name rather than a fixed one.
#
# The _monolithic template got uniqueness by generating a uuid to stand in for AWS::StackId,
# assembling a string shaped like a CloudFormation stack ARN out of it, and then slicing one
# segment back out of that string:
#
#   key_name = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# That reads as an artefact of the translation, but the property it bought is real - a key pair
# name is account-wide, so a fixed one collides with a second copy of this project. key_name_prefix
# is the provider's own way of getting it, and dropping the uuid drops the random provider and the
# synthetic stack ARN with it. Nothing else read that local.
resource "aws_key_pair" "key_pair" {
  key_name_prefix = var.key_name_prefix
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# What CloudFormation does for a key pair it generates: the private half is written to Parameter
# Store under /ec2/keypair/<key-pair-id>, retrievable without being an output.
#
# The key is in Terraform state either way - tls_private_key puts it there - so this parameter is
# not what exposes it. It is how a person gets at it, and the root exposes the fetch command rather
# than the key, which is the form this repository prefers for a secret.
#
# Worth knowing what this key is for here. The workbench security group opens the SSH port that
# its userdata moves sshd to, so this is a usable way in; both instance roles also carry the SSM
# agent, so Session Manager works without it. The launch template attaches the same key to every
# ECS container instance, which have no inbound rule at all and are reachable only through SSM.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
