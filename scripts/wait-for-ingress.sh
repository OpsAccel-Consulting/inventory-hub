#!/usr/bin/env bash
# Wait until the AWS Load Balancer Controller has provisioned the ALB for an
# Ingress, then print its hostname. First creation takes ~2-4 minutes.
#
#   HOST=$(./scripts/wait-for-ingress.sh inventory-hub inventory-hub)
set -euo pipefail

NAMESPACE="${1:?usage: wait-for-ingress.sh <namespace> <ingress>}"
INGRESS="${2:?usage: wait-for-ingress.sh <namespace> <ingress>}"
TIMEOUT="${TIMEOUT:-600}"

deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  host=$(kubectl -n "$NAMESPACE" get ingress "$INGRESS" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then
    echo "$host"
    exit 0
  fi
  echo "Waiting for ALB on ingress/${INGRESS}..." >&2
  sleep 10
done

echo "Timed out waiting for ingress/${INGRESS}" >&2
kubectl -n "$NAMESPACE" describe ingress "$INGRESS" >&2 || true
exit 1
