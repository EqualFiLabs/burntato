#!/usr/bin/env bash
set -euo pipefail

readonly CHAIN_ID=46630
readonly ARTIFACT=artifacts/robinhood-testnet/deployment.json
readonly DEFAULT_VERIFIER_URL=https://explorer.testnet.chain.robinhood.com/api/

usage() {
  echo "usage: ROBINHOOD_TESTNET_RPC_URL=... $0 --deploy|--verify|--inspect|--launch|--initialize|--enable|--check" >&2
  echo "deploy and state-changing modes require PRIVATE_KEY" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }
mode=$1
case "$mode" in
  --deploy|--verify|--inspect|--launch|--initialize|--enable|--check) ;;
  *) usage; exit 2 ;;
esac

for command_name in cast forge jq; do
  command -v "$command_name" >/dev/null || { echo "missing required command: $command_name" >&2; exit 1; }
done

rpc_url=${ROBINHOOD_TESTNET_RPC_URL:?ROBINHOOD_TESTNET_RPC_URL is required}
[[ $(cast chain-id --rpc-url "$rpc_url") == "$CHAIN_ID" ]] || {
  echo "Robinhood testnet chain $CHAIN_ID is required" >&2
  exit 1
}

if [[ "$mode" == "--deploy" ]]; then
  : "${PRIVATE_KEY:?PRIVATE_KEY is required}"
  forge script script/DeployBurntatoRobinhoodTestnet.s.sol:DeployBurntatoRobinhoodTestnet \
    --rpc-url "$rpc_url" --chain-id "$CHAIN_ID" --broadcast --slow \
    --gas-estimate-multiplier 200 -vv
  exit 0
fi

[[ -f "$ARTIFACT" ]] || { echo "missing deployment artifact: $ARTIFACT" >&2; exit 1; }
jq -e --argjson chainId "$CHAIN_ID" '.chainId == $chainId and .diamond != null and .hook != null' "$ARTIFACT" \
  >/dev/null

if [[ "$mode" == "--verify" ]]; then
  forge script script/DeployBurntatoRobinhoodTestnet.s.sol:DeployBurntatoRobinhoodTestnet \
    --rpc-url "$rpc_url" --chain-id "$CHAIN_ID" --resume --verify --verify-external \
    --verifier blockscout --verifier-url "${BLOCKSCOUT_API_URL:-$DEFAULT_VERIFIER_URL}" -vv
  exit 0
fi

if [[ "$mode" == "--inspect" ]]; then
  RPC_URL="$rpc_url" scripts/check-deployment.sh "$ARTIFACT"
  exit 0
fi

if [[ "$mode" == "--check" ]]; then
  forge script script/FinalizeBurntatoRobinhoodTestnet.s.sol:FinalizeBurntatoRobinhoodTestnet \
    --sig 'checkFinalized()' --rpc-url "$rpc_url" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
method=${mode#--}
case "$method" in
  launch) signature='launchMarket()' ;;
  initialize) signature='initializePurchases()' ;;
  enable) signature='enableExternalBuys()' ;;
esac
forge script script/FinalizeBurntatoRobinhoodTestnet.s.sol:FinalizeBurntatoRobinhoodTestnet \
  --sig "$signature" --rpc-url "$rpc_url" --chain-id "$CHAIN_ID" --broadcast --slow \
  --gas-estimate-multiplier 200 -vv
