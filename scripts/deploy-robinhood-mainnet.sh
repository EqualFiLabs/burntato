#!/usr/bin/env bash
set -euo pipefail

readonly CHAIN_ID=4663
readonly RPC_ALIAS=robinhood_mainnet
readonly BOOTSTRAP_BUYBACK_WEI=5025000000000000000
readonly ARTIFACT=artifacts/robinhood-mainnet/deployment.json
readonly INITIALIZE_CALL=artifacts/robinhood-mainnet/initialize-call.json
readonly ENABLE_CALL=artifacts/robinhood-mainnet/enable-call.json
readonly OPERATION_LEDGER=artifacts/robinhood-mainnet/operations.json
readonly RELEASE_RECORD=deployments/robinhood-mainnet-4663-launch.json
readonly DEPLOY_SCRIPT=script/DeployBurntatoRobinhoodMainnet.s.sol:DeployBurntatoRobinhoodMainnet
readonly OPERATE_SCRIPT=script/OperateBurntatoRobinhoodMainnet.s.sol:OperateBurntatoRobinhoodMainnet
readonly BROADCAST_FILE=broadcast/DeployBurntatoRobinhoodMainnet.s.sol/4663/run-latest.json
readonly LAUNCH_BROADCAST_FILE=broadcast/OperateBurntatoRobinhoodMainnet.s.sol/4663/launchMarket-latest.json
readonly INITIALIZE_BROADCAST_FILE=broadcast/OperateBurntatoRobinhoodMainnet.s.sol/4663/initializePurchases-latest.json
readonly ENABLE_BROADCAST_FILE=broadcast/OperateBurntatoRobinhoodMainnet.s.sol/4663/enableExternalBuys-latest.json
readonly BOOTSTRAP_BROADCAST_FILE=broadcast/BootstrapBurntatoBuyback.s.sol/4663/run-latest.json
readonly BUYBACK_BROADCAST_FILE=broadcast/ExecuteBurntatoBuyback.s.sol/4663/run-latest.json

usage() {
  echo "usage: ROBINHOOD_MAINNET=... $0 --preflight|--deploy|--resume-deploy|--inspect|--verify|--launch|--bootstrap|--buyback|--initialize|--enable|--initialize-bundle|--enable-bundle|--check|--record" >&2
  echo "state-changing modes require PRIVATE_KEY; --verify requires BLOCKSCOUT_API_URL" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }
mode=$1
case "$mode" in
  --preflight|--deploy|--resume-deploy|--inspect|--verify|--launch|--bootstrap|--buyback|--initialize|--enable|--initialize-bundle|--enable-bundle|--check|--record) ;;
  *) usage; exit 2 ;;
esac

for command_name in cast forge git jq; do
  command -v "$command_name" >/dev/null || { echo "missing required command: $command_name" >&2; exit 1; }
done

export ETH_RPC_URL=${ROBINHOOD_MAINNET:?ROBINHOOD_MAINNET is required}
redact_value() {
  local value=$1
  value=${value//"$ETH_RPC_URL"/<redacted-rpc>}
  printf '%s' "$value"
}

run_redacted() {
  "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    redact_value "$line"
    printf '\n'
  done
}

if ! actual_chain=$(cast chain-id 2>&1); then
  echo "unable to read Robinhood mainnet chain: $(redact_value "$actual_chain")" >&2
  exit 1
fi
[[ "$actual_chain" == "$CHAIN_ID" ]] || { echo "Robinhood mainnet chain $CHAIN_ID is required" >&2; exit 1; }

if [[ "${BURNTATO_ANVIL_REHEARSAL:-false}" == "true" ]]; then
  if ! anvil_probe=$(cast rpc anvil_getAutomine 2>&1); then
    echo "BURNTATO_ANVIL_REHEARSAL requires an Anvil RPC: $(redact_value "$anvil_probe")" >&2
    exit 1
  fi
fi

broadcast_fee_args=()
if [[ "${BURNTATO_ANVIL_REHEARSAL:-false}" == "true" ]]; then
  broadcast_fee_args=(--legacy)
fi

require_roles() {
  : "${BURNTATO_DEPLOYER:?BURNTATO_DEPLOYER is required}"
  : "${BURNTATO_FINAL_ADMIN:?BURNTATO_FINAL_ADMIN is required}"
  : "${BURNTATO_GUARDIAN:?BURNTATO_GUARDIAN is required}"
  : "${BURNTATO_TREASURY:?BURNTATO_TREASURY is required}"
  : "${BURNTATO_REWARD_ALLOCATOR:?BURNTATO_REWARD_ALLOCATOR is required}"
}

require_key() {
  : "${PRIVATE_KEY:?PRIVATE_KEY is required}"
}

require_clean_source() {
  git diff --quiet || { echo "tracked source changes must be committed before mainnet deployment" >&2; exit 1; }
  git diff --cached --quiet || { echo "staged source changes must be committed before mainnet deployment" >&2; exit 1; }
}

export_current_source_commit() {
  require_clean_source
  export BURNTATO_SOURCE_COMMIT
  BURNTATO_SOURCE_COMMIT=$(git rev-parse HEAD)
}

require_recorded_source_commit() {
  require_clean_source
  local expected
  expected=$(jq -er '.sourceCommit' "$ARTIFACT")
  local actual
  actual=$(git rev-parse HEAD)
  [[ "$actual" == "$expected" ]] || {
    echo "current source commit does not match the deployment artifact" >&2
    exit 1
  }
  export BURNTATO_SOURCE_COMMIT="$expected"
}

require_artifact() {
  [[ -f "$ARTIFACT" ]] || { echo "missing deployment artifact: $ARTIFACT" >&2; exit 1; }
  jq -e --argjson chainId "$CHAIN_ID" '.chainId == $chainId and .diamond != null and .hook != null' "$ARTIFACT" \
    >/dev/null
}

run_operation() {
  local signature=$1
  run_redacted forge script "$OPERATE_SCRIPT" --sig "$signature" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
    --broadcast "${broadcast_fee_args[@]}" --slow \
    --gas-estimate-multiplier 200 -vv
}

record_phase() {
  local phase=$1
  local broadcast_file=$2
  [[ -f "$broadcast_file" ]] || { echo "missing phase broadcast artifact: $broadcast_file" >&2; exit 1; }
  jq -e '(.receipts | length) > 0
    and all(.receipts[];
      .status == "0x1"
      and (.transactionHash | type == "string" and test("^0x[0-9a-fA-F]{64}$")))' \
    "$broadcast_file" >/dev/null
  mkdir -p "${OPERATION_LEDGER%/*}"
  local existing='[]'
  [[ ! -f "$OPERATION_LEDGER" ]] || existing=$(<"$OPERATION_LEDGER")
  local temporary_ledger
  temporary_ledger=$(mktemp "${OPERATION_LEDGER%/*}/operations.XXXXXX")
  jq -n \
    --argjson existing "$existing" \
    --arg phase "$phase" \
    --slurpfile broadcast "$broadcast_file" \
    '$existing + [{phase: $phase, transactionHashes: [$broadcast[0].receipts[].transactionHash]}]' \
    >"$temporary_ledger"
  mv "$temporary_ledger" "$OPERATION_LEDGER"
}

require_successful_transaction() {
  local transaction_hash=$1
  local name=$2
  [[ "$transaction_hash" =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "invalid $name" >&2; exit 1; }
  local receipt
  if ! receipt=$(cast receipt "$transaction_hash" --json 2>&1); then
    echo "unable to read $name receipt: $(redact_value "$receipt")" >&2
    exit 1
  fi
  if ! jq -e '.status == "0x1" or .status == "1" or .status == true' <<<"$receipt" >/dev/null; then
    echo "$name does not identify a successful chain-$CHAIN_ID transaction" >&2
    exit 1
  fi
}

if [[ "$mode" == "--preflight" ]]; then
  require_roles
  run_redacted forge script "$DEPLOY_SCRIPT" --sig 'preflight()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--deploy" ]]; then
  require_roles
  require_key
  export_current_source_commit
  [[ ! -e "$ARTIFACT" && ! -e "$BROADCAST_FILE" && ! -e "$OPERATION_LEDGER" \
      && ! -e "$INITIALIZE_CALL" && ! -e "$ENABLE_CALL" && ! -e "$RELEASE_RECORD" ]] || {
    echo "deployment state already exists; inspect it or use --resume-deploy" >&2
    exit 1
  }
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
    --broadcast "${broadcast_fee_args[@]}" --slow \
    --gas-estimate-multiplier 200 -vv
  exit 0
fi

if [[ "$mode" == "--resume-deploy" ]]; then
  require_roles
  require_key
  [[ -f "$ARTIFACT" && -f "$BROADCAST_FILE" ]] || {
    echo "deployment artifact and broadcast sequence are required for resume" >&2
    exit 1
  }
  require_recorded_source_commit
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
    --resume "${broadcast_fee_args[@]}" --slow \
    --gas-estimate-multiplier 200 -vv
  exit 0
fi

require_artifact
require_recorded_source_commit

if [[ "$mode" == "--inspect" ]]; then
  env BROADCAST_FILE="$BROADCAST_FILE" RPC_URL="$ETH_RPC_URL" scripts/check-deployment.sh "$ARTIFACT"
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkDeployed()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--verify" ]]; then
  : "${BLOCKSCOUT_API_URL:?BLOCKSCOUT_API_URL is required}"
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --resume --verify --verify-external \
    --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL" -vv
  exit 0
fi

if [[ "$mode" == "--launch" ]]; then
  require_key
  run_operation 'launchMarket()'
  record_phase launch-market "$LAUNCH_BROADCAST_FILE"
  exit 0
fi

export BURNTATO_DIAMOND
BURNTATO_DIAMOND=$(jq -er '.diamond' "$ARTIFACT")

if [[ "$mode" == "--bootstrap" ]]; then
  require_key
  export BURNTATO_BOOTSTRAP_BUYBACK_WEI="$BOOTSTRAP_BUYBACK_WEI"
  run_redacted forge script script/BootstrapBurntatoBuyback.s.sol:BootstrapBurntatoBuyback \
    --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --broadcast "${broadcast_fee_args[@]}" --slow \
    --gas-estimate-multiplier 200 -vv
  record_phase bootstrap-buyback "$BOOTSTRAP_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--buyback" ]]; then
  require_key
  run_redacted forge script script/ExecuteBurntatoBuyback.s.sol:ExecuteBurntatoBuyback \
    --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --broadcast "${broadcast_fee_args[@]}" --slow \
    --gas-estimate-multiplier 200 -vv
  record_phase buyback "$BUYBACK_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--initialize" ]]; then
  require_key
  run_operation 'initializePurchases()'
  record_phase initialize-purchases "$INITIALIZE_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--enable" ]]; then
  require_key
  run_operation 'enableExternalBuys()'
  record_phase enable-external-buys "$ENABLE_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--initialize-bundle" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkReadyForInitialization()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
  mkdir -p "${INITIALIZE_CALL%/*}"
  temporary_bundle=$(mktemp "${INITIALIZE_CALL%/*}/initialize-call.XXXXXX")
  jq -n \
    --argjson chainId "$CHAIN_ID" \
    --arg admin "$(jq -er '.admin' "$ARTIFACT")" \
    --arg diamond "$BURNTATO_DIAMOND" \
    --arg initializeData "$(cast calldata 'initializePurchases()')" \
    '{schemaVersion: 1, chainId: $chainId, admin: $admin,
      call: {phase: "initialize-purchases", to: $diamond, value: "0", data: $initializeData}}' \
    >"$temporary_bundle"
  mv "$temporary_bundle" "$INITIALIZE_CALL"
  echo "wrote public initialization call: $INITIALIZE_CALL"
  exit 0
fi

if [[ "$mode" == "--enable-bundle" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkReadyForExternalBuys()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
  mkdir -p "${ENABLE_CALL%/*}"
  temporary_bundle=$(mktemp "${ENABLE_CALL%/*}/enable-call.XXXXXX")
  jq -n \
    --argjson chainId "$CHAIN_ID" \
    --arg admin "$(jq -er '.admin' "$ARTIFACT")" \
    --arg hook "$(jq -er '.hook' "$ARTIFACT")" \
    --arg enableData "$(cast calldata 'setExternalBuysEnabled(bool)' true)" \
    '{schemaVersion: 1, chainId: $chainId, admin: $admin,
      call: {phase: "enable-external-buys", to: $hook, value: "0", data: $enableData}}' \
    >"$temporary_bundle"
  mv "$temporary_bundle" "$ENABLE_CALL"
  echo "wrote public buy-opening call: $ENABLE_CALL"
  exit 0
fi

if [[ "$mode" == "--check" || "$mode" == "--record" ]]; then
  env EXPECTED_MARKET_READY=false BROADCAST_FILE="$BROADCAST_FILE" RPC_URL="$ETH_RPC_URL" \
    scripts/check-deployment.sh "$ARTIFACT"
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkFinalized()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
fi

if [[ "$mode" == "--record" ]]; then
  [[ ! -e "$RELEASE_RECORD" ]] || { echo "release record already exists: $RELEASE_RECORD" >&2; exit 1; }
  [[ -f "$BROADCAST_FILE" ]] || { echo "missing broadcast artifact: $BROADCAST_FILE" >&2; exit 1; }
  [[ -f "$OPERATION_LEDGER" ]] || { echo "missing operation ledger: $OPERATION_LEDGER" >&2; exit 1; }
  jq -e '(.receipts | length) > 0
    and all(.receipts[];
      .status == "0x1"
      and (.transactionHash | type == "string" and test("^0x[0-9a-fA-F]{64}$")))' \
    "$BROADCAST_FILE" >/dev/null
  jq -e 'any(.[]; .phase == "launch-market")
    and any(.[]; .phase == "bootstrap-buyback")
    and ([.[] | select(.phase == "buyback")] | length == 5)
    and all(.[];
      (.transactionHashes | type == "array" and length > 0)
      and all(.transactionHashes[]; type == "string" and test("^0x[0-9a-fA-F]{64}$")))' \
    "$OPERATION_LEDGER" >/dev/null
  while IFS= read -r transaction_hash; do
    require_successful_transaction "$transaction_hash" deploymentTransactionHash
  done < <(jq -er '.receipts[].transactionHash' "$BROADCAST_FILE")
  while IFS= read -r transaction_hash; do
    require_successful_transaction "$transaction_hash" operationTransactionHash
  done < <(jq -er '.[].transactionHashes[]' "$OPERATION_LEDGER")
  initialize_transaction_hash=
  if ! jq -e 'any(.[]; .phase == "initialize-purchases")' "$OPERATION_LEDGER" >/dev/null; then
    : "${BURNTATO_INITIALIZE_TX_HASH:?BURNTATO_INITIALIZE_TX_HASH is required for an externally executed admin call}"
    require_successful_transaction "$BURNTATO_INITIALIZE_TX_HASH" BURNTATO_INITIALIZE_TX_HASH
    initialize_transaction_hash=$BURNTATO_INITIALIZE_TX_HASH
  fi
  enable_transaction_hash=
  if ! jq -e 'any(.[]; .phase == "enable-external-buys")' "$OPERATION_LEDGER" >/dev/null; then
    : "${BURNTATO_ENABLE_TX_HASH:?BURNTATO_ENABLE_TX_HASH is required for an externally executed admin call}"
    require_successful_transaction "$BURNTATO_ENABLE_TX_HASH" BURNTATO_ENABLE_TX_HASH
    enable_transaction_hash=$BURNTATO_ENABLE_TX_HASH
  fi
  source_commit=$(jq -er '.sourceCommit' "$ARTIFACT")
  if ! recorded_block=$(cast block-number 2>&1); then
    echo "unable to read record block: $(redact_value "$recorded_block")" >&2
    exit 1
  fi
  mkdir -p "${RELEASE_RECORD%/*}"
  temporary_record=$(mktemp "${RELEASE_RECORD%/*}/robinhood-mainnet-launch.XXXXXX")
  jq \
    --arg sourceCommit "$source_commit" \
    --argjson recordedBlock "$recorded_block" \
    --arg initializeTransactionHash "$initialize_transaction_hash" \
    --arg enableTransactionHash "$enable_transaction_hash" \
    --slurpfile broadcast "$BROADCAST_FILE" \
    --slurpfile operations "$OPERATION_LEDGER" \
    '. + {
      sourceCommit: $sourceCommit,
      recordedBlock: $recordedBlock,
      deploymentTransactionHashes: [$broadcast[0].receipts[].transactionHash],
      operations: ($operations[0]
        + (if $initializeTransactionHash == "" then [] else [{phase: "initialize-purchases", transactionHashes: [$initializeTransactionHash]}] end)
        + (if $enableTransactionHash == "" then [] else [{phase: "enable-external-buys", transactionHashes: [$enableTransactionHash]}] end))
    }' "$ARTIFACT" >"$temporary_record"
  mv "$temporary_record" "$RELEASE_RECORD"
  echo "wrote public mainnet release record: $RELEASE_RECORD"
fi
