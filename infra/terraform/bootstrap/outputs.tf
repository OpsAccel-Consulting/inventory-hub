output "state_bucket" {
  description = "Put this in environments/<env>/backend.hcl (bucket = ...)."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  value = var.region
}
