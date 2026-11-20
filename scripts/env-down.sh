#!/usr/bin/env bash
# Tear the dev environment down completely, in the right order.
#
#   ./scripts/env-down.sh               # or: make env-down
#   ./scripts/env-down.sh --profile my-admin-profile
#
# Steps:
#   1. Check the AWS sign-in and ask you to type the cluster name
#   2. Delete the app namespace - this removes the load balancer, which the
#      AWS Load Balancer Controller created outside Terraform and which would
#      otherwise block deleting the VPC
#   3. Wait until the load balancer is gone
#   4. terraform destroy (planned first; summary shown; you confirm)
#
# The Terraform state bucket is kept (it is needed to rebuild).
# Output that could contain the AWS account ID is masked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform/environments/dev"
NAMESPACE="inventory-hub"
PROFILE="${AWS_PROFILE:-}"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  cat << EOF
Options:
  --profile NAME   AWS profile to use (default: \$AWS_PROFILE)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
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
step "Checking AWS sign-in"
for t in aws terraform kubectl; do
  command -v "$t" > /dev/null || die "$t is not installed"
done
[[ -n "$PROFILE" ]] || die "No AWS profile. Use --profile NAME or export AWS_PROFILE=NAME"
export AWS_PROFILE="$PROFILE"
who=$(aws sts get-caller-identity --query Arn --output text 2>&1) ||
  die "AWS profile '${PROFILE}' is not signed in. Run: aws login --profile ${PROFILE}"
info "AWS identity: $(printf '%s' "$who" | mask)"

CLUSTER=$(tf output -raw cluster_name 2> /dev/null || true)
REGION=$(tf output -raw region 2> /dev/null || true)
[[ -n "$CLUSTER" ]] || die "No cluster in Terraform state - is the environment already down?"

read -r -p "    Destroy EVERYTHING in '${CLUSTER}' (${REGION})? Type the cluster name: " answer
[[ "$answer" == "$CLUSTER" ]] || die "Aborted - nothing was changed."

# ---------- 2-3. Kubernetes first (removes the load balancer) ----------
step "Deleting the app namespace (removes the load balancer)"
if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" > /dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" 2>&1 | mask
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=true --timeout=5m
else
  info "Cluster not found - skipping"
fi

step "Waiting for the load balancer to be deleted"
for _ in $(seq 1 30); do
  remaining=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?starts_with(LoadBalancerName, '${CLUSTER}')].LoadBalancerName" \
    --output text 2> /dev/null || true)
  [[ -z "$remaining" ]] && break
  info "still there: ${remaining}"
  sleep 10
done
[[ -z "${remaining:-}" ]] || die "Load balancer still exists after 5 minutes - wait and re-run"

# ---------- 4. terraform destroy ----------
step "Planning the destroy"
PLAN="${TF_DIR}/env-down.tfplan"
trap 'rm -f "$PLAN"' EXIT
tf plan -destroy -input=false -out="$PLAN" 2>&1 | mask | grep -E '^(Plan:|No changes|Error|│)' || true
[[ -f "$PLAN" ]] || die "terraform plan -destroy failed - run it by hand to see why"
read -r -p "    Destroy these resources? Type 'yes' to continue: " answer
[[ "$answer" == "yes" ]] || die "Aborted - Kubernetes app removed, AWS infrastructure kept."

step "Destroying (about 15-20 minutes)"
tf apply -input=false "$PLAN" 2>&1 | mask

step "Done"
left=$(tf state list 2> /dev/null | wc -l | tr -d ' ')
if [[ "$left" == "0" ]]; then
  info "Everything destroyed. The state bucket is kept for the next env-up."
else
  info "${left} resources still in state - wait a few minutes and run this script again."
fi
