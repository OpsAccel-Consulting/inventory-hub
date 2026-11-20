#!/usr/bin/env bash
# Push Terraform outputs into GitHub Actions secrets/variables using the gh CLI.
# Role ARNs are piped straight into `gh secret set`, so the account ID is never
# printed to the terminal (safe to run on a screen recording).
#
#   gh auth login            # once
#   ./scripts/configure-github.sh <org>/<repo>
set -euo pipefail

REPO="${1:?usage: configure-github.sh <org/repo>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform/environments/dev"

tf() { terraform -chdir="$TF_DIR" output -raw "$1"; }

# Read the bucket before touching GitHub so a missing file can't leave a half-configured repo.
BACKEND_LOCAL="${TF_DIR}/backend.local.hcl"
BUCKET=$(sed -nE 's/^bucket *= *"([^"]+)".*/\1/p' "$BACKEND_LOCAL" 2>/dev/null || true)
if [[ -z "$BUCKET" ]]; then
  echo "No bucket in ${BACKEND_LOCAL#"$ROOT"/}. Run scripts/bootstrap-state.sh first." >&2
  exit 1
fi

echo "Configuring ${REPO}..."

tf github_deploy_role_arn    | gh secret set AWS_DEPLOY_ROLE_ARN    --repo "$REPO"
tf github_terraform_role_arn | gh secret set AWS_TERRAFORM_ROLE_ARN --repo "$REPO"

gh variable set AWS_REGION       --repo "$REPO" --body "$(tf region)"
gh variable set EKS_CLUSTER_NAME --repo "$REPO" --body "$(tf cluster_name)"
gh variable set ECR_REPOSITORY   --repo "$REPO" --body "$(tf ecr_repository_name)"

gh variable set TF_STATE_BUCKET  --repo "$REPO" --body "$BUCKET"

# Environments used by the workflows (reviewers are added in the GitHub UI)
gh api --method PUT "repos/${REPO}/environments/dev" > /dev/null
gh api --method PUT "repos/${REPO}/environments/infra-dev" > /dev/null

echo "Done. Add a required reviewer to the 'infra-dev' environment in"
echo "Settings -> Environments to gate terraform apply."
