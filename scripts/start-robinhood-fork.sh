#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_MAINNET:?ROBINHOOD_MAINNET is required}"

manifest_block="$(jq -er '.forkBlock' deployments/robinhood-chain-4663.json)"
if [[ "$manifest_block" != "45234855" ]]; then
  printf 'Committed manifest fork block is not 45234855\n' >&2
  exit 1
fi
if [[ -n "${ROBINHOOD_FORK_BLOCK:-}" && "$ROBINHOOD_FORK_BLOCK" != "$manifest_block" ]]; then
  printf 'ROBINHOOD_FORK_BLOCK must equal %s\n' "$manifest_block" >&2
  exit 1
fi

exec anvil \
  --fork-url "$ROBINHOOD_MAINNET" \
  --fork-block-number "$manifest_block" \
  --chain-id 4663 \
  --port "${PORT:-8545}"
