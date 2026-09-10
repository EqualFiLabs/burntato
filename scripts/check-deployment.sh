#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_ARTIFACT="artifacts/robinhood-testnet/deployment.json"
readonly ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

artifact=${1:-$DEFAULT_ARTIFACT}
rpc_url=${RPC_URL:-${ROBINHOOD_TESTNET_RPC_URL:-}}
failures=0
call_count=0
receipt_summary=not_checked
export FOUNDRY_DISABLE_NIGHTLY_WARNING=${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}

for command_name in cast jq; do
  command -v "$command_name" >/dev/null || { printf 'FAIL missing_command=%s\n' "$command_name" >&2; exit 1; }
done
[[ -n "$rpc_url" ]] || { printf 'FAIL missing_rpc set RPC_URL or ROBINHOOD_TESTNET_RPC_URL\n' >&2; exit 1; }
[[ -f "$artifact" ]] || { printf 'FAIL missing_artifact=%s\n' "$artifact" >&2; exit 1; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

sanitize() {
  local value=$1
  value=${value//"$rpc_url"/<redacted-rpc>}
  value=${value//$'\n'/ }
  printf '%.240s' "$value"
}

json_value() {
  jq -er --arg field "$1" '.[$field] // empty' "$artifact"
}

same_value() {
  [[ "${1,,}" == "${2,,}" ]]
}

check_call() {
  local name=$1
  local address=$2
  local signature=$3
  local expected=$4
  local actual

  call_count=$((call_count + 1))
  if ! actual=$(cast call "$address" "$signature" --rpc-url "$rpc_url" 2>&1); then
    fail "$name error=$(sanitize "$actual")"
    return
  fi
  actual=${actual%% *}
  if ! same_value "$actual" "$expected"; then
    fail "$name expected=$expected actual=$(sanitize "$actual")"
  fi
}

required_fields=(
  chainId diamond admin guardian treasuryRecipient rewardAllocator hook hookDeployer
  operatorRewardsRouter operatorsNft activationRegistry hookFeeBps operatorRewardShareBps
  poolManager positionManager permit2 diamondCutFacet diamondLoupeFacet governanceFacet
  marketFacet buybackFacet potatoTokenFacet gameFacet recoveryFacet settlementFacet
  claimsFacet treasuryRewardsFacet foundationInit
)
for field in "${required_fields[@]}"; do
  json_value "$field" >/dev/null || fail "artifact_field=$field"
done
((failures == 0)) || exit 1

expected_chain=$(json_value chainId)
actual_chain=$(cast chain-id --rpc-url "$rpc_url" 2>&1) || {
  fail "chain_id error=$(sanitize "$actual_chain")"
  exit 1
}
if [[ "$actual_chain" == "$expected_chain" ]]; then
  :
else
  fail "chain_id expected=$expected_chain actual=$(sanitize "$actual_chain")"
fi

code_fields=(
  diamond diamondCutFacet diamondLoupeFacet governanceFacet marketFacet buybackFacet
  potatoTokenFacet gameFacet recoveryFacet settlementFacet claimsFacet treasuryRewardsFacet
  foundationInit hookDeployer hook operatorRewardsRouter
)
code_count=0
for field in "${code_fields[@]}"; do
  address=$(json_value "$field" 2>/dev/null || true)
  [[ -n "$address" && "${address,,}" != "$ZERO_ADDRESS" ]] || continue
  if code=$(cast code "$address" --rpc-url "$rpc_url" 2>&1); then
    if [[ "$code" != "0x" && "$code" != "0x0" ]]; then
      code_count=$((code_count + 1))
    else
      fail "$field code=empty"
    fi
  else
    fail "$field code_error=$(sanitize "$code")"
  fi
done

diamond=$(json_value diamond)
admin=$(json_value admin)
guardian=$(json_value guardian)
treasury=$(json_value treasuryRecipient)
reward_allocator=$(json_value rewardAllocator)
hook=$(json_value hook)
router=$(json_value operatorRewardsRouter)
operators_nft=$(json_value operatorsNft)
activation_registry=$(json_value activationRegistry)
pool_manager=$(json_value poolManager)
position_manager=$(json_value positionManager)
permit2=$(json_value permit2)

check_call authority "$diamond" 'authority()(address)' "$admin"
check_call guardian "$diamond" 'guardian()(address)' "$guardian"
check_call foundation_configured "$diamond" 'foundationConfigured()(bool)' true
check_call protocol_paused "$diamond" 'paused()(bool)' false
check_call market_ready "$diamond" 'marketReady()(bool)' true
check_call treasury_recipient "$diamond" 'treasuryRecipient()(address)' "$treasury"
check_call reward_allocator "$diamond" 'rewardAllocator()(address)' "$reward_allocator"

check_call hook_owner "$hook" 'owner()(address)' "$admin"
check_call hook_token "$hook" 'token()(address)' "$diamond"
check_call hook_pool_manager "$hook" 'poolManager()(address)' "$pool_manager"
check_call hook_fee_recipient "$hook" 'feeAddress()(address)' "$treasury"
check_call hook_fee_bps "$hook" 'feeBps()(uint16)' "$(json_value hookFeeBps)"
check_call hook_operator_router "$hook" 'operatorRewardsRouter()(address)' "$router"
check_call hook_operator_share "$hook" 'operatorRewardShareBps()(uint16)' "$(json_value operatorRewardShareBps)"

check_call position_manager_pool "$position_manager" 'poolManager()(address)' "$pool_manager"
check_call position_manager_permit2 "$position_manager" 'permit2()(address)' "$permit2"
check_call operators_registry "$operators_nft" 'activationRegistry()(address)' "$activation_registry"
check_call registry_collection "$activation_registry" 'genesisCollection()(address)' "$operators_nft"

if [[ "${router,,}" != "$ZERO_ADDRESS" ]]; then
  check_call router_burntato "$router" 'burntato()(address)' "$diamond"
  check_call router_operators "$router" 'operators()(address)' "$operators_nft"
  check_call router_registry "$router" 'activationRegistry()(address)' "$activation_registry"
fi

if [[ -n "${BROADCAST_FILE:-}" ]]; then
  if [[ ! -f "$BROADCAST_FILE" ]]; then
    fail "missing_broadcast_file=$BROADCAST_FILE"
  else
    receipt_count=$(jq -er '.receipts | length' "$BROADCAST_FILE")
    failed_receipts=$(jq -er '[.receipts[] | select(.status != "0x1")] | length' "$BROADCAST_FILE")
    if [[ "$failed_receipts" == 0 ]]; then
      receipt_summary=$receipt_count
    else
      fail "receipts_failed=$failed_receipts total=$receipt_count"
    fi
  fi
fi

if ((failures == 0)); then
  printf 'PASS deployment_check chain_id=%s deployed_code=%d calls=%d receipts=%s\n' \
    "$actual_chain" "$code_count" "$call_count" "$receipt_summary"
else
  printf 'FAIL deployment_check failures=%d\n' "$failures" >&2
  exit 1
fi
