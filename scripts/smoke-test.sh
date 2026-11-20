#!/usr/bin/env bash
# Post-deploy smoke test.
#   ./scripts/smoke-test.sh http://<alb-hostname> [expected-version]
set -euo pipefail

BASE_URL="${1:?usage: smoke-test.sh <base-url> [expected-version]}"
EXPECTED_VERSION="${2:-}"
RETRIES="${RETRIES:-30}"

# New ALBs need DNS propagation + healthy targets: retry readiness first.
for i in $(seq 1 "$RETRIES"); do
  if curl -fsS --max-time 5 "${BASE_URL}/readyz" > /dev/null 2>&1; then
    echo "readyz OK (attempt ${i})"
    break
  fi
  if [[ "$i" == "$RETRIES" ]]; then
    echo "Service never became ready at ${BASE_URL}" >&2
    exit 1
  fi
  sleep 10
done

check() {
  local path="$1" expected="$2"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${BASE_URL}${path}")
  if [[ "$code" != "$expected" ]]; then
    echo "FAIL ${path}: expected ${expected}, got ${code}" >&2
    exit 1
  fi
  echo "PASS ${path} -> ${code}"
}

check /healthz 200
check / 200
check /products 200
check /api/v1/products 200
check /api/v1/summary 200
check /api/v1/products/999999 404

if [[ -n "$EXPECTED_VERSION" ]]; then
  # The new version can take a few seconds to be served by every target.
  for i in $(seq 1 12); do
    live=$(curl -fsS --max-time 5 "${BASE_URL}/version" | sed -E 's/.*"version": *"([^"]+)".*/\1/')
    if [[ "$live" == "$EXPECTED_VERSION" ]]; then
      echo "PASS /version -> ${live}"
      exit 0
    fi
    sleep 5
  done
  echo "FAIL /version: expected ${EXPECTED_VERSION}, got ${live:-none}" >&2
  exit 1
fi
