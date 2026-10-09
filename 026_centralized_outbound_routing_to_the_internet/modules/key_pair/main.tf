# CloudFormation's AWS::EC2::KeyPair generates the key material itself and writes the private half to
# SSM Parameter Store at /ec2/keypair/<key-pair-id>. Terraform has no equivalent, so the three
# resources below reproduce it: tls_private_key generates the pair, the public half becomes the key
# pair, and the private half is written to the same parameter path - so the same
# "aws ssm get-parameter --with-decryption" call the _monolithic template implied still works.
#
# Nothing in this project can use the key. The only instance sits in a private subnet in a VPC with
# no internet gateway, and its security group has no inbound rule, so there is no path for an SSH
# connection to arrive on. It is reproduced because the template had it, and because the parameter is
# the kind of thing that outlives a demo: see the note on aws_ssm_parameter below.
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.key_pair.public_key_openssh
}
# A SecureString, as CloudFormation creates it. Two things worth knowing about this resource:
#
# The value is in Terraform state in cleartext regardless of the parameter's type, because Terraform
# generated it. Encrypting it in Parameter Store protects it at rest in AWS and does nothing for the
# state file, so the state file is the thing to treat as the secret.
#
# The parameter name embeds the key pair id, so replacing the key pair replaces this parameter rather
# than updating it - and a stale parameter from a previous apply is not cleaned up by the new one. It
# is removed on destroy because it is a managed resource here, which is more than the CloudFormation
# original managed.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
