# Replace the bucket with the `state_bucket` output of infra/terraform/bootstrap
# (scripts/bootstrap-state.sh does this for you).
bucket       = "REPLACE_WITH_STATE_BUCKET"
key          = "inventory-hub/dev/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
