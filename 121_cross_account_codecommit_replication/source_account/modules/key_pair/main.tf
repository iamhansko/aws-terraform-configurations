resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}

resource "aws_key_pair" "this" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.this.public_key_openssh
}

# The private material is already in Terraform state because TLS generated it. Parameter Store provides a
# retrievable recovery path without exposing the key as a normal output.
resource "aws_ssm_parameter" "private_key" {
  name  = "/ec2/keypair/${aws_key_pair.this.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.this.private_key_pem
}
