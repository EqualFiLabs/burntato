#!/usr/bin/env bash
set -euo pipefail

halmos_bin=${HALMOS_BIN:-halmos}
foundry_bin=${FOUNDRY_BIN:-forge}
if [[ "$foundry_bin" == */* ]]; then
  export PATH="$(dirname "$foundry_bin"):$PATH"
elif ! command -v "$foundry_bin" >/dev/null 2>&1; then
  echo "forge is not available; set FOUNDRY_BIN to its absolute path" >&2
  exit 1
fi
export FOUNDRY_PROFILE=formal

"$halmos_bin" \
  --forge-build-out out-formal \
  --match-contract '^Burntato(Math|Activation|BuybackFunding|Pause)Properties$' \
  --solver-timeout-branching 5s \
  --solver-timeout-assertion 120s \
  --statistics
