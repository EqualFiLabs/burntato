#!/usr/bin/env bash
set -euo pipefail

certora_bin=${CERTORA_BIN:-certoraRun}
foundry_bin=${FOUNDRY_BIN:-forge}
if [[ "$foundry_bin" == */* ]]; then
  export PATH="$(dirname "$foundry_bin"):$PATH"
elif ! command -v "$foundry_bin" >/dev/null 2>&1; then
  echo "forge is not available; set FOUNDRY_BIN to its absolute path" >&2
  exit 1
fi
suite=${1:-all}

run_suite() {
  "$certora_bin" "formal/certora/conf/$1.conf"
}

case "$suite" in
  math)
    run_suite math
    ;;
  activation)
    run_suite activation
    ;;
  buyback-funding)
    run_suite buyback-funding
    ;;
  all)
    run_suite math
    run_suite activation
    run_suite buyback-funding
    ;;
  *)
    echo "usage: $0 [math|activation|buyback-funding|all]" >&2
    exit 2
    ;;
esac
