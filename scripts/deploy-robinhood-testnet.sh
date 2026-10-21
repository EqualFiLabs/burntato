#!/usr/bin/env bash
set -euo pipefail

set -a
. /home/hooftly/.openclaw/workspace/.rpc
set +a

readonly CHAIN_ID=46630
readonly STATICS_HANDOFF=artifacts/robinhood-testnet/statics-handoff.json
readonly STATICS_OPERATOR_MANIFEST=deployments/statics-operators-robinhood-testnet-46630.json
readonly INITIALIZE_CALL=artifacts/robinhood-testnet/initialize-call.json
readonly ARTIFACT=artifacts/robinhood-testnet/deployment.json
readonly OPERATION_LEDGER=artifacts/robinhood-testnet/operations.json
readonly RELEASE_RECORD=${BURNTATO_RELEASE_RECORD:-deployments/robinhood-testnet-46630-launch.json}
readonly PREPARE_SCRIPT=script/PrepareBurntatoRobinhoodTestnet.s.sol:PrepareBurntatoRobinhoodTestnet
readonly DEPLOY_SCRIPT=script/DeployBurntatoRobinhoodTestnet.s.sol:DeployBurntatoRobinhoodTestnet
readonly OPERATE_SCRIPT=script/OperateBurntatoRobinhoodTestnet.s.sol:OperateBurntatoRobinhoodTestnet
readonly BROADCAST_FILE=broadcast/DeployBurntatoRobinhoodTestnet.s.sol/46630/run-latest.json
readonly INITIALIZE_BROADCAST_FILE=broadcast/OperateBurntatoRobinhoodTestnet.s.sol/46630/initializePurchases-latest.json
readonly BOOTSTRAP_BROADCAST_FILE=broadcast/BootstrapBurntatoBuyback.s.sol/46630/run-latest.json
readonly BUYBACK_BROADCAST_FILE=broadcast/ExecuteBurntatoBuyback.s.sol/46630/run-latest.json
readonly DEFAULT_VERIFIER_URL=https://explorer.testnet.chain.robinhood.com/api/

usage() {
  echo "usage: ROBINHOOD_TESTNET=... $0 --prepare-statics|--preflight|--deploy|--resume-deploy|--inspect|--verify|--bootstrap|--buyback|--check-staged|--initialize|--initialize-bundle|--check|--record" >&2
  echo "state-changing modes require PRIVATE_KEY; Statics handoff and release modes require their documented public artifacts" >&2
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }
mode=$1
[[ "$mode" == --* ]] || mode="--$mode"
if [[ "$mode" == --deploy || "$mode" == --resume-deploy ]]; then
  [[ "${2:-}" == --broadcast ]] || { echo "Explicit --broadcast required" >&2; exit 2; }
elif [[ $# -ne 1 ]]; then
  usage; exit 2
fi
case "$mode" in
  --prepare-statics|--preflight|--deploy|--resume-deploy|--inspect|--verify|--bootstrap|--buyback|--check-staged|--initialize|--initialize-bundle|--check|--record) ;;
  *) usage; exit 2 ;;
esac

for command_name in cast forge git jq; do
  command -v "$command_name" >/dev/null || { echo "missing required command: $command_name" >&2; exit 1; }
done

export ETH_RPC_URL=${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET is required}

redact_value() {
  local value=$1
  value=${value//"$ETH_RPC_URL"/<redacted-rpc>}
  if [[ -n "${PRIVATE_KEY:-}" ]]; then value=${value//"$PRIVATE_KEY"/<redacted-key>}; fi
  printf '%s' "$value"
}

run_redacted() {
  "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
    redact_value "$line"
    printf '\n'
  done
}

if ! actual_chain=$(cast chain-id 2>&1); then
  echo "unable to read Robinhood testnet chain: $(redact_value "$actual_chain")" >&2
  exit 1
fi
[[ "$actual_chain" == "$CHAIN_ID" ]] || { echo "Robinhood testnet chain $CHAIN_ID is required" >&2; exit 1; }

require_key() {
  if [[ -z "${PRIVATE_KEY:-}" ]]; then
    [[ "$(stat -c %a /home/hooftly/.openclaw/workspace/.rhdeploy)" == 600 ]] || { echo "Restrict testnet key permissions to 600" >&2; exit 1; }
    PRIVATE_KEY=$(cat /home/hooftly/.openclaw/workspace/.rhdeploy)
    export PRIVATE_KEY
    local signer
    if ! signer=$(cast wallet address --private-key "$PRIVATE_KEY" 2>&1); then
      echo "unable to derive canonical testnet signer: $(redact_value "$signer")" >&2
      exit 1
    fi
    [[ "${signer,,}" == 0x6ae2ad9905fedc8270b828294d4b9cec7cbbe316 ]] || {
      echo "canonical testnet key address mismatch" >&2; exit 1;
    }
  fi
}

require_deployer() {
  : "${BURNTATO_DEPLOYER:?BURNTATO_DEPLOYER is required}"
}

require_clean_source() {
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || { echo "untracked source must be committed before deployment" >&2; exit 1; }
  git diff --quiet || { echo "tracked source changes must be committed before testnet deployment" >&2; exit 1; }
  git diff --cached --quiet || { echo "staged source changes must be committed before testnet deployment" >&2; exit 1; }
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
  jq -e --argjson chainId "$CHAIN_ID" \
    '.schemaVersion == 4 and .chainId == $chainId and .diamond != null and .statics != null and .sourceCommit != null' \
    "$ARTIFACT" >/dev/null
}

require_successful_broadcast() {
  local broadcast_file=$1
  [[ -f "$broadcast_file" ]] || { echo "missing broadcast artifact: $broadcast_file" >&2; exit 1; }
  jq -e '(.receipts | length) > 0
    and all(.receipts[];
      .status == "0x1"
      and (.transactionHash | type == "string" and test("^0x[0-9a-fA-F]{64}$")))' \
    "$broadcast_file" >/dev/null
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
  jq -e '.status == "0x1" or .status == "1" or .status == true' <<<"$receipt" >/dev/null || {
    echo "$name does not identify a successful chain-$CHAIN_ID transaction" >&2
    exit 1
  }
}

record_phase() {
  local phase=$1
  local broadcast_file=$2
  require_successful_broadcast "$broadcast_file"
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

run_operation() {
  local signature=$1
  run_redacted forge script "$OPERATE_SCRIPT" --sig "$signature" --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" \
    --broadcast --slow --gas-estimate-multiplier 200 -vv
}

if [[ "$mode" == "--prepare-statics" ]]; then
  : "${STATICS_GENESIS_TESTNET_ARTIFACT:?STATICS_GENESIS_TESTNET_ARTIFACT is required}"
  : "${STATICS_SOURCE_COMMIT:?STATICS_SOURCE_COMMIT is required}"
  [[ "$STATICS_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "STATICS_SOURCE_COMMIT must be a full lowercase commit" >&2; exit 1; }
  [[ -f "$STATICS_GENESIS_TESTNET_ARTIFACT" ]] || {
    echo "missing Statics Genesis artifact" >&2
    exit 1
  }
  run_redacted forge script "$PREPARE_SCRIPT" --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
  jq -e --argjson chainId "$CHAIN_ID" \
    '.chainId == $chainId
      and (.genesisEpochEnd | type == "number")
      and (.genesis | type == "string")
      and (.activationRegistry | type == "string")
      and (.finalizedBlock | type == "number")
      and (.finalizedBlockHash | type == "string")' \
    "$STATICS_HANDOFF" >/dev/null
  temporary_manifest=$(mktemp "${STATICS_OPERATOR_MANIFEST%/*}/statics-operators-testnet.XXXXXX")
  jq -n \
    --slurpfile handoff "$STATICS_HANDOFF" \
    '{
      network: "Robinhood Chain Testnet",
      chainId: $handoff[0].chainId,
      genesisEpochEnd: $handoff[0].genesisEpochEnd,
      finalizedBlock: $handoff[0].finalizedBlock,
      finalizedBlockHash: $handoff[0].finalizedBlockHash,
      source: {
        repository: "EqualFiLabs/statics",
        commit: $handoff[0].staticsSourceCommit,
        mainnetGenesisSourceCommit: $handoff[0].mainnetGenesisSourceCommit,
        genesisArtifactHash: $handoff[0].genesisArtifactHash
      },
      contracts: {
        operatorsNft: {
          address: $handoff[0].genesis,
          runtimeCodeHash: $handoff[0].operatorsNftRuntimeCodeHash
        },
        activationRegistry: {
          address: $handoff[0].activationRegistry,
          runtimeCodeHash: $handoff[0].activationRegistryRuntimeCodeHash
        },
        genesisVault: {
          address: $handoff[0].genesisVault,
          runtimeCodeHash: $handoff[0].genesisVaultRuntimeCodeHash
        }
      }
    }' >"$temporary_manifest"
  mv "$temporary_manifest" "$STATICS_OPERATOR_MANIFEST"
  echo "wrote Statics Operator manifest; review before deployment: $STATICS_OPERATOR_MANIFEST"
  exit 0
fi

if [[ "$mode" == "--preflight" ]]; then
  require_deployer
  export_current_source_commit
  run_redacted forge script "$DEPLOY_SCRIPT" --sig 'preflight()' --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--deploy" ]]; then
  require_deployer
  require_key
  export_current_source_commit
  [[ ! -e "$ARTIFACT" && ! -e "$BROADCAST_FILE" && ! -e "$OPERATION_LEDGER" && ! -e "$INITIALIZE_CALL" && ! -e "$RELEASE_RECORD" ]] || {
    echo "deployment state already exists; archive the prior disposable run or use --resume-deploy" >&2
    exit 1
  }
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" \
    --broadcast --slow --gas-estimate-multiplier 200 -vv
  exit 0
fi

if [[ "$mode" == "--resume-deploy" ]]; then
  require_deployer
  require_key
  [[ -f "$ARTIFACT" && -f "$BROADCAST_FILE" ]] || {
    echo "deployment artifact and broadcast sequence are required for resume" >&2
    exit 1
  }
  require_recorded_source_commit
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" \
    --resume --slow --gas-estimate-multiplier 200 -vv
  exit 0
fi

require_artifact
require_recorded_source_commit
export BURNTATO_DEPLOYMENT_ARTIFACT="$ARTIFACT"

if [[ "$mode" == "--inspect" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkDeployed()' --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--verify" ]]; then
  export BLOCKSCOUT_API_URL=${BLOCKSCOUT_API_URL:-$DEFAULT_VERIFIER_URL}
  run_redacted bash scripts/verify-deployment.sh "$ARTIFACT" "$CHAIN_ID"
  exit 0
fi


export BURNTATO_DIAMOND
BURNTATO_DIAMOND=$(jq -er '.diamond' "$ARTIFACT")

if [[ "$mode" == "--bootstrap" ]]; then
  require_key
  : "${BURNTATO_BOOTSTRAP_BUYBACK_WEI:?explicit buyback funding amount required}"
  export BURNTATO_BOOTSTRAP_BUYBACK_WEI
  run_redacted forge script script/BootstrapBurntatoBuyback.s.sol:BootstrapBurntatoBuyback \
    --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" --broadcast --slow --gas-estimate-multiplier 200 -vv
  record_phase bootstrap-buyback "$BOOTSTRAP_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--buyback" ]]; then
  require_key
  run_redacted forge script script/ExecuteBurntatoBuyback.s.sol:ExecuteBurntatoBuyback \
    --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" --broadcast --slow --gas-estimate-multiplier 200 -vv
  record_phase buyback "$BUYBACK_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--check-staged" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkStaged()' --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--initialize" ]]; then
  require_key
  run_operation 'initializePurchases()'
  record_phase initialize-purchases "$INITIALIZE_BROADCAST_FILE"
  exit 0
fi


if [[ "$mode" == "--initialize-bundle" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkReadyForInitialization()' --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
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

if [[ "$mode" == "--check" || "$mode" == "--record" ]]; then
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkActive()' --rpc-url "$ETH_RPC_URL" --chain-id "$CHAIN_ID" -vv
fi

if [[ "$mode" == "--record" ]]; then
  [[ ! -e "$RELEASE_RECORD" ]] || { echo "release record already exists: $RELEASE_RECORD" >&2; exit 1; }
  [[ -f "$BROADCAST_FILE" ]] || { echo "missing broadcast artifact: $BROADCAST_FILE" >&2; exit 1; }
  [[ -f "$OPERATION_LEDGER" ]] || printf '[]\n' >"$OPERATION_LEDGER"
  jq -e '(.receipts | length) > 0
    and all(.receipts[];
      .status == "0x1"
      and (.transactionHash | type == "string" and test("^0x[0-9a-fA-F]{64}$")))' \
    "$BROADCAST_FILE" >/dev/null
  jq -e 'all(.[];
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
  funding_transaction_hash=
  if ! jq -e 'any(.[]; .phase == "bootstrap-buyback" or .phase == "fund-reward-reserve")' "$OPERATION_LEDGER" >/dev/null; then
    : "${BURNTATO_FUNDING_TX_HASH:?BURNTATO_FUNDING_TX_HASH is required for external reserve funding}"
    require_successful_transaction "$BURNTATO_FUNDING_TX_HASH" BURNTATO_FUNDING_TX_HASH
    funding_transaction_hash=$BURNTATO_FUNDING_TX_HASH
  fi
  source_commit=$(jq -er '.sourceCommit' "$ARTIFACT")
  if ! recorded_block=$(cast block-number 2>&1); then
    echo "unable to read record block: $(redact_value "$recorded_block")" >&2
    exit 1
  fi
  mkdir -p "${RELEASE_RECORD%/*}"
  temporary_record=$(mktemp "${RELEASE_RECORD%/*}/robinhood-testnet-launch.XXXXXX")
  jq \
    --arg sourceCommit "$source_commit" \
    --argjson recordedBlock "$recorded_block" \
    --arg initializeTransactionHash "$initialize_transaction_hash" \
    --arg fundingTransactionHash "$funding_transaction_hash" \
    --slurpfile broadcast "$BROADCAST_FILE" \
    --slurpfile operations "$OPERATION_LEDGER" \
    '. + {
      sourceCommit: $sourceCommit,
      recordedBlock: $recordedBlock,
      deploymentTransactionHashes: [$broadcast[0].receipts[].transactionHash],
      operations: ($operations[0]
        + (if $initializeTransactionHash == "" then [] else [{phase: "initialize-purchases", transactionHashes: [$initializeTransactionHash]}] end)
        + (if $fundingTransactionHash == "" then [] else [{phase: "fund-reward-reserve", transactionHashes: [$fundingTransactionHash]}] end))
    }' "$ARTIFACT" >"$temporary_record"
  mv "$temporary_record" "$RELEASE_RECORD"
  echo "wrote public testnet release record: $RELEASE_RECORD"
fi
