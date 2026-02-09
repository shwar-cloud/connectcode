# KMS Key for Encryption
resource "aws_kms_key" "kms_bucketkey" {
  description             = "S3 bucket KMS key"
  deletion_window_in_days = 10

  tags = {
    Environment = "Production"
    Project     = "SLCR"
  }
}

# Main S3 Bucket
resource "aws_s3_bucket" "slcr_bucket" {
  bucket              = var.bucket_name
  object_lock_enabled = true

  tags = {
    Environment = "Production"
    Project     = "SLCR"
  }
}

# Object Lock Configuration

resource "aws_s3_bucket_object_lock_configuration" "object_lock" {
  bucket = aws_s3_bucket.slcr_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}

# Replica S3 Bucket
resource "aws_s3_bucket" "slcr_bucket_replica" {
  bucket = "${var.bucket_name}-replica"

  tags = {
    Environment = "Production"
    Project     = "SLCR"
  }
}

# Versioning for Buckets
resource "aws_s3_bucket_versioning" "slcr_bucket_versioning" {
  bucket = aws_s3_bucket.slcr_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "slcr_bucket_replica_versioning" {
  bucket = aws_s3_bucket.slcr_bucket_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "slcr_bucket_encryption" {
  bucket = aws_s3_bucket.slcr_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kms_bucketkey.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Lifecycle Rule

resource "aws_s3_bucket_lifecycle_configuration" "slcr_bucket_lifecycle" {
  bucket = aws_s3_bucket.slcr_bucket.id

  rule {
    id     = "tiering-rule"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Bucket Policy – Enforce KMS Encryption

resource "aws_s3_bucket_policy" "slcr_bucket_encryption_policy" {
  bucket = aws_s3_bucket.slcr_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceKMS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.slcr_bucket.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

# IAM Role for Replication

resource "aws_iam_role" "slcr_bucket_replication_role" {
  name = "${var.bucket_name}-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "Production"
    Project     = "SLCR"
  }
}

# IAM Role Policy for Replication
resource "aws_iam_role_policy" "slcr_bucket_replication_policy" {
  role = aws_iam_role.slcr_bucket_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.slcr_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.slcr_bucket_replica.arn}/*"
      }
    ]
  })
}

# Replication Configuration
resource "aws_s3_bucket_replication_configuration" "slcr_bucket_replication_config" {
  bucket = aws_s3_bucket.slcr_bucket.id
  role   = aws_iam_role.slcr_bucket_replication_role.arn

  rule {
    id     = "replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.slcr_bucket_replica.arn
      storage_class = "STANDARD"
    }

    delete_marker_replication {
      status = "Disabled"
    }

    filter {}
  }
}

# SNS Topic for Replication Failures
resource "aws_sns_topic" "replication_failures" {
  name = "${var.bucket_name}-replication-failures"

  tags = {
    Environment = "Production"
    Project     = "SLCR"
  }
}

# SNS Topic Policy (REQUIRED)
resource "aws_sns_topic_policy" "replication_failures_policy" {
  arn = aws_sns_topic.replication_failures.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action   = "sns:Publish"
        Resource = aws_sns_topic.replication_failures.arn

        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.slcr_bucket.arn
          }
        }
      }
    ]
  })
}

# S3 Event Notifications
resource "aws_s3_bucket_notification" "replication_events" {
  bucket = aws_s3_bucket.slcr_bucket.id

  topic {
    topic_arn = aws_sns_topic.replication_failures.arn
    events    = ["s3:Replication:OperationFailedReplication"]
  }

  depends_on = [
    aws_sns_topic_policy.replication_failures_policy
  ]
}

# CloudWatch Alarm for Replication Lag
resource "aws_cloudwatch_metric_alarm" "replication_lag_alarm" {
  alarm_name          = "${var.bucket_name}-replication-lag"
  alarm_description   = "Alarm if replication lag exceeds 1 hour"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 3600
  statistic           = "Maximum"
  threshold           = 3600

  dimensions = {
    BucketName  = aws_s3_bucket.slcr_bucket.bucket
    StorageType = "AllStorageTypes"
  }

  alarm_actions = [aws_sns_topic.replication_failures.arn]
}

# SNS Email Subscription
resource "aws_sns_topic_subscription" "replication_email_alert" {
   topic_arn = aws_sns_topic.replication_failures.arn
   protocol  = "email"
   endpoint  = var.alert_email
} 