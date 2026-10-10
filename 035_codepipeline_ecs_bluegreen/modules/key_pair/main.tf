# The SSH key pair, generated here rather than supplied.
#
# CloudFormation's AWS::EC2::KeyPair generates the material itself and files the private half in
# Parameter Store under /ec2/keypair/<key-pair-id>. Terraform has no equivalent, so the three steps
# are written out: generate, register the public half, store the private half.
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
resource "aws_key_pair" "key_pair" {
  # A generated name rather than the _monolithic template's "key-${local.stack_suffix}", which needed a
  # random_uuid sliced out of a synthetic CloudFormation stack ARN to be unique. Key pair names are
  # account-wide, so uniqueness is a real requirement and key_name_prefix is the provider's own way of
  # meeting it - see the root providers.tf for what else that uuid was holding up.
  key_name_prefix = var.key_name_prefix
  public_key      = tls_private_key.key_pair.public_key_openssh
}
resource "aws_ssm_parameter" "key_pair_private_key" {
  name = "/ec2/keypair/${aws_key_pair.key_pair.key_pair_id}"
  # SecureString, as CloudFormation writes it. Nothing reads this parameter during apply; it exists so
  # the generated key can be retrieved later, which is why only the retrieval command is exposed as an
  # output and never the key itself (rules.md H-2).
  type        = "SecureString"
  value       = tls_private_key.key_pair.private_key_pem
  description = var.parameter_description
}
