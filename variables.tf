variable "bucket_name" {
  type        = string
  description = "Main S3 bucket name"
}

variable "aws_access_key" {
  type        = string
  description = "AWS access key"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "AWS secret key"
  sensitive   = true
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "ap-south-1"
}

variable "alert_email" {
type        = string
description = "Email for S3 replication alerts"
}