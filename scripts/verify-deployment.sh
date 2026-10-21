#!/usr/bin/env bash
set -euo pipefail
artifact=${1:?deployment artifact required}
chain_id=${2:?chain ID required}
: "${BLOCKSCOUT_API_URL:?Blockscout API URL required}"
: "${ETH_RPC_URL:?RPC must be selected by the deployment wrapper}"
# Source publication only: never resume or broadcast a deployment here.
while read -r field contract; do
  address=$(jq -er --arg field "$field" '.[$field]' "$artifact")
  [[ "$address" != 0x0000000000000000000000000000000000000000 ]] || continue
  arguments=()
  if [[ "$field" == diamond ]]; then
    arguments=(--constructor-args "$(cast abi-encode 'constructor(address,address)' "$(jq -er .deployer "$artifact")" "$(jq -er .diamondCutFacet "$artifact")")")
  elif [[ "$field" == operatorRewardsRouter ]]; then
    arguments=(--constructor-args "$(cast abi-encode 'constructor(address,address,address)' "$(jq -er .diamond "$artifact")" "$(jq -er .operatorsNft "$artifact")" "$(jq -er .activationRegistry "$artifact")")")
  fi
  forge verify-contract "$address" "$contract" --chain "$chain_id" --rpc-url "$ETH_RPC_URL" \
    --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL" --watch "${arguments[@]}"
done <<'CONTRACTS'
diamond src/BurntatoDiamond.sol:BurntatoDiamond
diamondCutFacet src/facets/DiamondCutFacet.sol:DiamondCutFacet
diamondLoupeFacet src/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet
governanceFacet src/facets/GovernanceFacet.sol:GovernanceFacet
potatoTokenFacet src/facets/PotatoTokenFacet.sol:PotatoTokenFacet
buybackFacet src/facets/BuybackFacet.sol:BuybackFacet
gameFacet src/facets/GameFacet.sol:GameFacet
recoveryFacet src/facets/RecoveryFacet.sol:RecoveryFacet
settlementFacet src/facets/SettlementFacet.sol:SettlementFacet
claimsFacet src/facets/ClaimsFacet.sol:ClaimsFacet
treasuryRewardsFacet src/facets/TreasuryRewardsFacet.sol:TreasuryRewardsFacet
foundationInit src/initializers/FoundationInit.sol:FoundationInit
operatorRewardsRouter src/rewards/BurntatoOperatorRewardsRouter.sol:BurntatoOperatorRewardsRouter
CONTRACTS
