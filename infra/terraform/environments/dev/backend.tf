# Partial backend configuration - values come from backend.hcl (local) or
# -backend-config flags (GitHub Actions):
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
