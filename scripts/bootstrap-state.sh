#!/usr/bin/env bash
# One-time: create the Terraform state bucket and point the dev backend at it.
#   ./scripts/bootstrap-state.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${ROOT}/infra/terraform/bootstrap"
BACKEND="${ROOT}/infra/terraform/environments/dev/backend.hcl"

terraform -chdir="$BOOTSTRAP" init -input=false
terraform -chdir="$BOOTSTRAP" apply -input=false -auto-approve

BUCKET=$(terraform -chdir="$BOOTSTRAP" output -raw state_bucket)
sed -i.bak -E "s|^bucket *=.*|bucket       = \"${BUCKET}\"|" "$BACKEND" && rm -f "${BACKEND}.bak"

echo
echo "State bucket: ${BUCKET}"
echo "Updated ${BACKEND#"$ROOT"/}"
echo "Also set the GitHub repository variable TF_STATE_BUCKET=${BUCKET}"
echo
echo "NOTE: bootstrap state is local (infra/terraform/bootstrap/terraform.tfstate)."
echo "      It is git-ignored - keep a copy somewhere safe."
