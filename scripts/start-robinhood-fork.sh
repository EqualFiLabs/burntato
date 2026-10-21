#!/usr/bin/env bash
set -euo pipefail

set -a
. /home/hooftly/.openclaw/workspace/.rpc
set +a
: "${ROBINHOOD_MAINNET:?private Robinhood Mainnet RPC required}"
manifest_block=$(jq -er '.forkBlock' deployments/statics-market-robinhood-4663.json)
operator_block=$(jq -er '.finalizedBlock' deployments/statics-operators-robinhood-4663.json)
[[ "$manifest_block" == "$operator_block" ]] || { printf 'Market and Operator fork anchors differ\n' >&2; exit 1; }
[[ -z "${ROBINHOOD_OPERATOR_FORK_BLOCK:-}" || "$ROBINHOOD_OPERATOR_FORK_BLOCK" == "$manifest_block" ]] || { printf 'Fork block must match the committed manifests\n' >&2; exit 1; }
exec python3 scripts/run-private-rpc.py --network mainnet -- anvil \
  --fork-block-number "$manifest_block" --chain-id 4663 \
  --host 127.0.0.1 --port "${PORT:-8545}"
