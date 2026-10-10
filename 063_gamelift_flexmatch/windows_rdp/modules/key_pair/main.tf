resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}
# A generated name by default rather than a fixed one.
#
# The _monolithic template got uniqueness by slicing a segment out of the uuid it
# generated to stand in for AWS::StackId:
#
#   key_name = "key-${element(split("-", element(split("/", local.stack_id), 2)), 3)}"
#
# That reads as an accident of the CloudFormation translation, but the property it
# bought is real: two copies of this project in one account do not collide.
# key_name_prefix is the provider's own way of getting it, and it lets the uuid -
# and the random provider call that produced it - go away entirely.
resource "aws_key_pair" "key_pair" {
  key_name        = var.key_name
  key_name_prefix = var.key_name == null ? var.key_name_prefix : null
  public_key      = tls_private_key.key_pair.public_key_openssh
}
# Mirrors what CloudFormation does for a key pair it generates: the private key
# goes into Parameter Store under /ec2/keypair/<key-pair-id>, so it is
# retrievable without being a Terraform output.
#
# On Windows this parameter is not a convenience, it is the only way to read the
# Administrator password. EC2 encrypts that password with the key pair's public
# half at launch, and ec2 get-password-data needs the private half to decrypt it -
# so losing this parameter means losing Administrator on the instance. The root
# builds that command out of this path and the instance id.
#
# The key is in Terraform state either way, because tls_private_key puts it
# there; this parameter is not what exposes it.
resource "aws_ssm_parameter" "key_pair_private_key" {
  name  = "${var.parameter_name_prefix}${aws_key_pair.key_pair.key_pair_id}"
  type  = "SecureString"
  value = tls_private_key.key_pair.private_key_pem
}
