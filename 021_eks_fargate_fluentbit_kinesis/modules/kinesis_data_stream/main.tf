# The sink Fargate's Fluent Bit writes pod logs into. Its own module rather than
# part of the logging module: the stream is a plain AWS resource that anything
# could consume, while the logging module's job is to point Fluent Bit at a sink
# it is handed by name (rules.md B-6). The root joins the two.
resource "aws_kinesis_stream" "kinesis_data_stream" {
  # CloudFormation left this name to be generated. Terraform requires one, so the
  # _monolithic conversion derived it from the stack name and this keeps that
  # shape - with the name now a variable rather than a stack-name interpolation
  # (rules.md B-3).
  name = var.name

  stream_mode_details {
    # On-demand rather than provisioned: the demo's log volume is a handful of
    # records per second, and provisioned mode would need a shard count chosen up
    # front and billed whether or not anything is logging.
    stream_mode = var.stream_mode
  }

  # Only meaningful in PROVISIONED mode. Left null in ON_DEMAND, where the API
  # rejects a shard count outright.
  shard_count = var.stream_mode == "PROVISIONED" ? var.shard_count : null

  retention_period = var.retention_period_hours
  encryption_type  = var.encryption_type
  kms_key_id       = var.encryption_type == "KMS" ? var.kms_key_id : null

  tags = {
    Name = var.name
  }
}
