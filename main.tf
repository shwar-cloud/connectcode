provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

module "slcr_s3" {
  source      = "./modules/s3"
  bucket_name = var.bucket_name
  alert_email = var.alert_email
}
