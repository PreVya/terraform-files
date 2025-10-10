output "ip"{
    value = aws_instance.flask_express.public_ip
}

output "s3_bucket_name" {
  description = "S3 bucket for .env files"
  value       = aws_s3_bucket.env_bucket.bucket
}