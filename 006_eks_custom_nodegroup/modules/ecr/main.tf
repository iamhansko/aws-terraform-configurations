resource "aws_ecr_repository" "ecr" {
  name                 = var.name
  force_delete         = var.force_delete
  image_tag_mutability = var.image_tag_mutability
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }
  tags = {
    Name = var.name
  }
}
