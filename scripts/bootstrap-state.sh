#!/usr/bin/env bash
# One-time: create the Terraform state bucket and point the local dev backend at it.
# The bucket goes to the git-ignored backend.local.hcl; backend.hcl keeps its placeholder.
#   ./scripts/bootstrap-state.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP="${ROOT}/infra/terraform/bootstrap"
BACKEND_LOCAL="${ROOT}/infra/terraform/environments/dev/backend.local.hcl"

terraform -chdir="$BOOTSTRAP" init -input=false
terraform -chdir="$BOOTSTRAP" apply -input=false -auto-approve

BUCKET=$(terraform -chdir="$BOOTSTRAP" output -raw state_bucket)
cat > "$BACKEND_LOCAL" <<EOF
# Local only (git-ignored). Written by scripts/bootstrap-state.sh.
# Layered on top of backend.hcl by \`make tf-init\`.
bucket = "${BUCKET}"
EOF

echo
echo "State bucket: ${BUCKET}"
echo "Wrote ${BACKEND_LOCAL#"$ROOT"/} (git-ignored)"
echo "Also set the GitHub repository variable TF_STATE_BUCKET=${BUCKET}"
echo
echo "NOTE: bootstrap state is local (infra/terraform/bootstrap/terraform.tfstate)."
echo "      It is git-ignored - keep a copy somewhere safe."
