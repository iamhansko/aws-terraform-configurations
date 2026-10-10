resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# key_name_prefix instead of the _monolithic template's slice of its AWS::StackId stand-in:
#
#   key_name = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# The provider-generated suffix buys the same uniqueness without a random_uuid.
resource "aws_key_pair" "key_pair" {
  key_name_prefix = var.key_name_prefix
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# What CloudFormation does with a key pair it generates: the private half goes to Parameter Store under
# /ec2/keypair/<key-pair-id>. The root exposes the fetch command, never the key, because every output is also
# written into a README that an unauthenticated code-server serves (rules.md H-2).
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
