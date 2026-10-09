# A generated EC2 key pair, mirroring what CloudFormation does for AWS::EC2::KeyPair without a
# PublicKeyMaterial: create the pair and put the private half in SSM at /ec2/keypair/<key-pair-id>.
#
# The private key lands in Terraform state in cleartext, which is unavoidable with the tls provider -
# state is the only place the generated key exists before it is written anywhere. The SSM copy is a
# SecureString, so the readable copy is the state file rather than the parameter.
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.key_pair.public_key_openssh
}
# The parameter name depends on the key pair's id, which is why this reads as though it were the other
# way round: the pair has to exist before its private half can be filed under its id. That reference
# is the only thing ordering these two.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
