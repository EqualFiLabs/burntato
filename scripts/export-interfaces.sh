#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/interfaces
for interface in IPotatoToken IBuyback IGame IRecovery ISettlement IClaims ITreasuryRewards IGovernance IDiamondCut IDiamondLoupe IOperatorRewards; do
  forge inspect "src/interfaces/${interface}.sol:${interface}" abi --json > "artifacts/interfaces/${interface}.json"
done
