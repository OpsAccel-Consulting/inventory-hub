#!/usr/bin/env bash
# Bring the dev environment up from nothing to a running, seeded app.
#
#   ./scripts/env-up.sh                 # or: make env-up
#   ./scripts/env-up.sh --profile my-admin-profile --no-seed --no-ip-restrict
#
# Steps:
#   1. Check tools and the AWS sign-in
#   2. terraform plan (saved), show the summary, ask, then apply that exact plan
#   3. Run the Deploy workflow on main and wait for it
#   4. Point kubectl at the cluster and wait for the pods
#   5. Load the demo data (flask seed)
#   6. Restrict the load balancer to your current public IP
#   7. Print the app URL
#
# All output that could contain the AWS account ID is masked, so the run is
# safe to record.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform/environments/dev"
NAMESPACE="inventory-hub"
PROFILE="${AWS_PROFILE:-}"
SEED=true
IP_RESTRICT=true
ASSUME_YES=false

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  cat << EOF
Options:
  --profile NAME     AWS profile to use (default: \$AWS_PROFILE)
  --no-seed          Don't load the demo data
  --no-ip-restrict   Leave the load balancer open to the internet
  --yes              Don't ask before applying the Terraform plan
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --no-seed)
      SEED=false
      shift
      ;;
    --no-ip-restrict)
      IP_RESTRICT=false
      shift
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() {
  printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}
mask() { sed -E 's/[0-9]{12}/<redacted>/g'; }
tf() { terraform -chdir="$TF_DIR" "$@"; }

# ---------- 1. preflight ----------
step "Checking tools and AWS sign-in"
for t in aws terraform kubectl gh curl; do
  command -v "$t" > /dev/null || die "$t is not installed"
done
[[ -n "$PROFILE" ]] || die "No AWS profile. Use --profile NAME or export AWS_PROFILE=NAME"
export AWS_PROFILE="$PROFILE"
who=$(aws sts get-caller-identity --query Arn --output text 2>&1) ||
  die "AWS profile '${PROFILE}' is not signed in. Run: aws login --profile ${PROFILE}"
info "AWS identity: $(printf '%s' "$who" | mask)"
gh auth status > /dev/null 2>&1 || die "GitHub CLI not signed in. Run: gh auth login"
REPO=$(cd "$ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner)
info "GitHub repo:  ${REPO}"

# ---------- 2. infrastructure ----------
step "Planning infrastructure"
if [[ ! -d "${TF_DIR}/.terraform" ]]; then
  info "First run in this clone - initialising Terraform"
  (cd "$ROOT" && make tf-init) 2>&1 | mask
fi
PLAN="${TF_DIR}/env-up.tfplan"
trap 'rm -f "$PLAN"' EXIT
tf plan -input=false -out="$PLAN" 2>&1 | mask | grep -E '^(Plan:|No changes|Error|│)' || true
[[ -f "$PLAN" ]] || die "terraform plan failed - run 'make tf-plan' to see the full output"
if ! $ASSUME_YES; then
  read -r -p "    Apply this plan? Type 'yes' to continue: " answer
  [[ "$answer" == "yes" ]] || die "Aborted - nothing was changed."
fi

step "Applying (EKS and RDS take 15-25 minutes; RDS is usually last)"
tf apply -input=false "$PLAN" 2>&1 | mask
CLUSTER=$(tf output -raw cluster_name)
REGION=$(tf output -raw region)

# ---------- 3. deploy ----------
step "Deploying the app (GitHub Actions)"
before=$(gh run list --repo "$REPO" --workflow deploy.yml --limit 1 --json databaseId -q '.[0].databaseId' 2> /dev/null || true)
gh workflow run deploy.yml --repo "$REPO" --ref main
run_id=""
for _ in $(seq 1 30); do
  sleep 4
  run_id=$(gh run list --repo "$REPO" --workflow deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')
  [[ -n "$run_id" && "$run_id" != "$before" ]] && break
done
[[ -n "$run_id" && "$run_id" != "$before" ]] || die "Could not find the new Deploy run - check the Actions tab"
info "Run: https://github.com/${REPO}/actions/runs/${run_id}"
gh run watch "$run_id" --repo "$REPO" --exit-status > /dev/null ||
  die "Deploy failed - open the run above for details"
info "Deploy succeeded"

# ---------- 4. kubectl ----------
step "Connecting kubectl"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" 2>&1 | mask
kubectl -n "$NAMESPACE" rollout status deploy/inventory-hub --timeout=10m

# ---------- 5. demo data ----------
if $SEED; then
  step "Loading demo data"
  kubectl -n "$NAMESPACE" exec deploy/inventory-hub -c web -- flask seed
fi

# ---------- 6. restrict access ----------
if $IP_RESTRICT; then
  step "Restricting the load balancer to your IP"
  MYIP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
  [[ "$MYIP" =~ ^[0-9.]+$ ]] || die "Could not determine your public IP"
  kubectl -n "$NAMESPACE" annotate ingress inventory-hub \
    "alb.ingress.kubernetes.io/inbound-cidrs=${MYIP}/32" --overwrite > /dev/null
  info "Only ${MYIP} can reach the app (re-run this script's step or the annotate command if your IP changes)"
fi

# ---------- 7. URL ----------
step "Done"
HOST=$(kubectl -n "$NAMESPACE" get ingress inventory-hub -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
info "App:     http://${HOST}"
info "Health:  http://${HOST}/readyz"
info "Tear down when finished: ./scripts/env-down.sh  (or make env-down)"
