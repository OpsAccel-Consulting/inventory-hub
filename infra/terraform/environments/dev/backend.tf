# Partial backend configuration - values come from backend.hcl plus the bucket from
# backend.local.hcl (local, via `make tf-init`) or a -backend-config flag (GitHub Actions):
#   terraform init -backend-config=backend.hcl -backend-config=backend.local.hcl
terraform {
  backend "s3" {}
}
