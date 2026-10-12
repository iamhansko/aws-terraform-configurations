# The role S3 assumes to replicate objects out of the source bucket.
#
# Two things differ from the _monolithic template, and both are about scope.
#
# The name is fixed, because the destination account's bucket policy derives this role's ARN for its
# aws:PrincipalArn condition and cannot reference it across state files (rules.md I-2).
#
# The policy is split by what each action applies to and scoped to the two buckets, where the original
# granted all eleven actions on "*". That mattered: the role could read any object in the source account and
# write into any bucket it was allowed to reach.
resource "aws_iam_role" "replication" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "replication" {
  name = var.inline_policy_name
  role = aws_iam_role.replication.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket-level reads on the source: which objects exist, and what the replication rules are.
        Sid      = "ReadSourceBucketConfiguration"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetReplicationConfiguration"]
        Resource = var.source_bucket_arn
      },
      {
        # Object-level reads on the source. GetObjectRetention and GetObjectLegalHold are only needed if
        # object lock is in use, and are kept because a bucket can gain lock later and the failure then is a
        # replication that stops with nothing logged here.
        Sid    = "ReadSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold",
        ]
        Resource = "${var.source_bucket_arn}/*"
      },
      {
        # Writes into the destination account's bucket. This is only half of the permission: the destination
        # bucket's own policy has to allow this role as a principal, and it is in another account.
        Sid    = "ReplicateIntoDestination"
        Effect = "Allow"
        Action = concat(
          ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"],
          var.allow_owner_override ? ["s3:ObjectOwnerOverrideToBucketOwner"] : [],
        )
        Resource = "${var.destination_bucket_arn}/*"
      },
    ]
  })
}
