# Shared backend settings. Keep the bucket as a placeholder: the public repo must not
# name the state bucket. The real bucket comes from:
#   - local:  backend.local.hcl (git-ignored, written by scripts/bootstrap-state.sh)
#   - CI:     -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}"
bucket       = "REPLACE_WITH_STATE_BUCKET"
key          = "inventory-hub/dev/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
