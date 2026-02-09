output "slcr_bucket_arn" {
  value = aws_s3_bucket.slcr_bucket.arn
}

output "slcr_bucket_replica_arn" {
  value = aws_s3_bucket.slcr_bucket_replica.arn
}

output "kms_key_arn" {
  value = aws_kms_key.kms_bucketkey.arn
} 