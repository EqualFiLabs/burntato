#!/usr/bin/env bash
set -euo pipefail

readonly CHAIN_ID=46630
readonly RPC_ALIAS=robinhood_testnet
readonly BOOTSTRAP_BUYBACK_WEI=5025000000000000000
readonly STATICS_HANDOFF=artifacts/robinhood-testnet/statics-handoff.json
readonly STATICS_OPERATOR_MANIFEST=deployments/statics-operators-robinhood-testnet-46630.json
readonly ARTIFACT=artifacts/robinhood-testnet/deployment.json
readonly OPERATION_LEDGER=artifacts/robinhood-testnet/operations.json
readonly RELEASE_RECORD=deployments/robinhood-testnet-46630-launch.json
readonly PREPARE_SCRIPT=script/PrepareBurntatoRobinhoodTestnet.s.sol:PrepareBurntatoRobinhoodTestnet
readonly DEPLOY_SCRIPT=script/DeployBurntatoRobinhoodTestnet.s.sol:DeployBurntatoRobinhoodTestnet
readonly OPERATE_SCRIPT=script/FinalizeBurntatoRobinhoodTestnet.s.sol:FinalizeBurntatoRobinhoodTestnet
readonly BROADCAST_FILE=broadcast/DeployBurntatoRobinhoodTestnet.s.sol/46630/run-latest.json
readonly LAUNCH_BROADCAST_FILE=broadcast/FinalizeBurntatoRobinhoodTestnet.s.sol/46630/launchMarket-latest.json
readonly INITIALIZE_BROADCAST_FILE=broadcast/FinalizeBurntatoRobinhoodTestnet.s.sol/46630/initializePurchases-latest.json
readonly ENABLE_BROADCAST_FILE=broadcast/FinalizeBurntatoRobinhoodTestnet.s.sol/46630/enableExternalBuys-latest.json
readonly BOOTSTRAP_BROADCAST_FILE=broadcast/BootstrapBurntatoBuyback.s.sol/46630/run-latest.json
readonly BUYBACK_BROADCAST_FILE=broadcast/ExecuteBurntatoBuyback.s.sol/46630/run-latest.json
readonly DEFAULT_VERIFIER_URL=https://explorer.testnet.chain.robinhood.com/api/

usage() {
  echo "usage: ROBINHOOD_TESTNET=... $0 --prepare-statics|--preflight|--deploy|--resume-deploy|--inspect|--verify|--launch|--bootstrap|--buyback|--check-staged|--initialize|--enable|--check|--record" >&2
  echo "state-changing modes require PRIVATE_KEY; Statics handoff and release modes require their documented public artifacts" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }
mode=$1
case "$mode" in
  --prepare-statics|--preflight|--deploy|--resume-deploy|--inspect|--verify|--launch|--bootstrap|--buyback|--check-staged|--initialize|--enable|--check|--record) ;;
  *) usage; exit 2 ;;
esac

for command_name in cast forge git jq; do
  command -v "$command_name" >/dev/null || { echo "missing required command: $command_name" >&2; exit 1; }
done

export ETH_RPC_URL=${ROBINHOOD_TESTNET:?ROBINHOOD_TESTNET is required}

redact_value() {
  local value=$1
  value=${value//"$ETH_RPC_URL"/<redacted-rpc>}
  printf '%s' "$value"
}

uint_ge() {
  local left=$1
  local right=$2
  while [[ ${#left} -gt 1 && ${left:0:1} == 0 ]]; do left=${left:1}; done
  while [[ ${#right} -gt 1 && ${right:0:1} == 0 ]]; do right=${right:1}; done
  (( ${#left} > ${#right} )) || {
    (( ${#left} == ${#right} )) && [[ "$left" > "$right" || "$left" == "$right" ]]
  }
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
  : "${PRIVATE_KEY:?PRIVATE_KEY is required}"
}

require_deployer() {
  : "${BURNTATO_DEPLOYER:?BURNTATO_DEPLOYER is required}"
}

require_clean_source() {
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
    '.schemaVersion == 3 and .chainId == $chainId and .diamond != null and .hook != null and .sourceCommit != null' \
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
  run_redacted forge script "$OPERATE_SCRIPT" --sig "$signature" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
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
  run_redacted forge script "$PREPARE_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
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
  echo "wrote reviewed Statics Operator manifest: $STATICS_OPERATOR_MANIFEST"
  exit 0
fi

if [[ "$mode" == "--preflight" ]]; then
  require_deployer
  export_current_source_commit
  run_redacted forge script "$DEPLOY_SCRIPT" --sig 'preflight()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
  exit 0
fi

if [[ "$mode" == "--deploy" ]]; then
  require_deployer
  require_key
  export_current_source_commit
  [[ ! -e "$ARTIFACT" && ! -e "$BROADCAST_FILE" && ! -e "$OPERATION_LEDGER" ]] || {
    echo "deployment state already exists; archive the prior disposable run or use --resume-deploy" >&2
    exit 1
  }
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
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
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" \
    --resume --slow --gas-estimate-multiplier 200 -vv
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
  run_redacted forge script "$DEPLOY_SCRIPT" --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --resume --verify \
    --verify-external --verifier blockscout --verifier-url "${BLOCKSCOUT_API_URL:-$DEFAULT_VERIFIER_URL}" -vv
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
    --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --broadcast --slow --gas-estimate-multiplier 200 -vv
  record_phase bootstrap-buyback "$BOOTSTRAP_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--buyback" ]]; then
  require_key
  run_redacted forge script script/ExecuteBurntatoBuyback.s.sol:ExecuteBurntatoBuyback \
    --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" --broadcast --slow --gas-estimate-multiplier 200 -vv
  record_phase buyback "$BUYBACK_BROADCAST_FILE"
  exit 0
fi

if [[ "$mode" == "--check-staged" ]]; then
  env EXPECTED_MARKET_READY=false BROADCAST_FILE="$BROADCAST_FILE" RPC_URL="$ETH_RPC_URL" \
    scripts/check-deployment.sh "$ARTIFACT"
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkStaged()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
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

if [[ "$mode" == "--check" || "$mode" == "--record" ]]; then
  env EXPECTED_MARKET_READY=false BROADCAST_FILE="$BROADCAST_FILE" RPC_URL="$ETH_RPC_URL" \
    scripts/check-deployment.sh "$ARTIFACT"
  run_redacted forge script "$OPERATE_SCRIPT" --sig 'checkFinalized()' --rpc-url "$RPC_ALIAS" --chain-id "$CHAIN_ID" -vv
fi

if [[ "$mode" == "--record" ]]; then
  : "${STATICS_GENESIS_BROADCAST_FILE:?STATICS_GENESIS_BROADCAST_FILE is required}"
  : "${STATICS_FAUCET_BROADCAST_FILE:?STATICS_FAUCET_BROADCAST_FILE is required}"
  : "${STATICS_FAUCET_ARTIFACT:?STATICS_FAUCET_ARTIFACT is required}"
  [[ -f "$STATICS_HANDOFF" ]] || { echo "missing Statics handoff: $STATICS_HANDOFF" >&2; exit 1; }
  [[ -f "$OPERATION_LEDGER" ]] || { echo "missing operation ledger: $OPERATION_LEDGER" >&2; exit 1; }
  [[ -f "$STATICS_FAUCET_ARTIFACT" ]] || { echo "missing Statics faucet artifact" >&2; exit 1; }
  jq -ne \
    --slurpfile handoff "$STATICS_HANDOFF" \
    --slurpfile manifest "$STATICS_OPERATOR_MANIFEST" \
    --slurpfile burntato "$ARTIFACT" \
    '$handoff[0].chainId == 46630
      and $manifest[0].chainId == 46630
      and ($handoff[0].genesis | ascii_downcase) == ($manifest[0].contracts.operatorsNft.address | ascii_downcase)
      and ($handoff[0].genesis | ascii_downcase) == ($burntato[0].operatorsNft | ascii_downcase)
      and ($handoff[0].activationRegistry | ascii_downcase) == ($manifest[0].contracts.activationRegistry.address | ascii_downcase)
      and ($handoff[0].activationRegistry | ascii_downcase) == ($burntato[0].activationRegistry | ascii_downcase)
      and ($handoff[0].genesisVault | ascii_downcase) == ($manifest[0].contracts.genesisVault.address | ascii_downcase)
      and ($handoff[0].operatorsNftRuntimeCodeHash | ascii_downcase) == ($manifest[0].contracts.operatorsNft.runtimeCodeHash | ascii_downcase)
      and ($handoff[0].activationRegistryRuntimeCodeHash | ascii_downcase) == ($manifest[0].contracts.activationRegistry.runtimeCodeHash | ascii_downcase)
      and ($handoff[0].genesisVaultRuntimeCodeHash | ascii_downcase) == ($manifest[0].contracts.genesisVault.runtimeCodeHash | ascii_downcase)
      and $handoff[0].genesisEpochEnd == $manifest[0].genesisEpochEnd
      and $handoff[0].finalizedBlock == $manifest[0].finalizedBlock
      and $handoff[0].finalizedBlock == $burntato[0].staticsFinalizedBlock
      and ($handoff[0].finalizedBlockHash | ascii_downcase) == ($manifest[0].finalizedBlockHash | ascii_downcase)
      and ($handoff[0].finalizedBlockHash | ascii_downcase) == ($burntato[0].staticsFinalizedBlockHash | ascii_downcase)
      and $handoff[0].staticsSourceCommit == $manifest[0].source.commit
      and $handoff[0].mainnetGenesisSourceCommit == $manifest[0].source.mainnetGenesisSourceCommit
      and $handoff[0].genesisArtifactHash == $manifest[0].source.genesisArtifactHash' >/dev/null
  require_successful_broadcast "$BROADCAST_FILE"
  require_successful_broadcast "$STATICS_GENESIS_BROADCAST_FILE"
  require_successful_broadcast "$STATICS_FAUCET_BROADCAST_FILE"
  jq -e --slurpfile handoff "$STATICS_HANDOFF" '
    any(.transactions[];
      .transactionType == "CREATE"
      and .contractName == "StaticsGenesis"
      and (.contractAddress | ascii_downcase) == ($handoff[0].genesis | ascii_downcase))
    and any(.transactions[];
      .transactionType == "CREATE"
      and .contractName == "GenesisActivationRegistry"
      and (.contractAddress | ascii_downcase) == ($handoff[0].activationRegistry | ascii_downcase))' \
    "$STATICS_GENESIS_BROADCAST_FILE" >/dev/null
  jq -e --slurpfile faucet "$STATICS_FAUCET_ARTIFACT" '
    any(.transactions[];
      .transactionType == "CREATE"
      and .contractName == "StaticsGenesisTestnetFaucet"
      and (.contractAddress | ascii_downcase) == ($faucet[0].address | ascii_downcase))
    and [.transactions[].hash] == $faucet[0].transactions' \
    "$STATICS_FAUCET_BROADCAST_FILE" >/dev/null
  jq -e 'any(.[]; .phase == "launch-market")
    and any(.[]; .phase == "bootstrap-buyback")
    and ([.[] | select(.phase == "buyback")] | length == 5)
    and any(.[]; .phase == "initialize-purchases")
    and any(.[]; .phase == "enable-external-buys")
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
  while IFS= read -r transaction_hash; do
    require_successful_transaction "$transaction_hash" staticsTransactionHash
  done < <(jq -er '.receipts[].transactionHash' "$STATICS_GENESIS_BROADCAST_FILE")
  while IFS= read -r transaction_hash; do
    require_successful_transaction "$transaction_hash" faucetTransactionHash
  done < <(jq -er '.receipts[].transactionHash' "$STATICS_FAUCET_BROADCAST_FILE")

  expected_statics=$(jq -er '.statics' "$STATICS_HANDOFF")
  statics_faucet=$(jq -er --arg expectedStatics "$expected_statics" '
    select(.schemaVersion == 1)
    | select((.statics | ascii_downcase) == ($expectedStatics | ascii_downcase))
    | select(.claimAmount == "200000000000000000000000")
    | select(.cooldownSeconds == 86400)
    | select(.fundedClaims >= 1)
    | .address' "$STATICS_FAUCET_ARTIFACT")
  faucet_statics=$(cast call "$statics_faucet" 'STATICS()(address)')
  [[ "${faucet_statics,,}" == "${expected_statics,,}" ]] || { echo "faucet STATICS binding mismatch" >&2; exit 1; }
  faucet_code=$(cast code "$statics_faucet")
  [[ "$faucet_code" != "0x" && "$faucet_code" != "0x0" ]] || { echo "faucet has no runtime code" >&2; exit 1; }
  expected_faucet_hash=$(jq -er '.runtimeCodeHash' "$STATICS_FAUCET_ARTIFACT")
  actual_faucet_hash=$(cast keccak "$faucet_code")
  [[ "${actual_faucet_hash,,}" == "${expected_faucet_hash,,}" ]] || { echo "faucet runtime hash mismatch" >&2; exit 1; }
  faucet_claim_amount=$(cast call "$statics_faucet" 'CLAIM_AMOUNT()(uint256)')
  faucet_claim_amount=${faucet_claim_amount%% *}
  [[ "$faucet_claim_amount" == "200000000000000000000000" ]] || {
    echo "unexpected faucet claim amount" >&2
    exit 1
  }
  faucet_cooldown=$(cast call "$statics_faucet" 'COOLDOWN()(uint256)')
  faucet_cooldown=${faucet_cooldown%% *}
  [[ "$faucet_cooldown" == "86400" ]] || {
    echo "unexpected faucet cooldown" >&2
    exit 1
  }
  faucet_balance=$(cast call "$expected_statics" 'balanceOf(address)(uint256)' "$statics_faucet")
  faucet_balance=${faucet_balance%% *}
  uint_ge "$faucet_balance" "$faucet_claim_amount" || { echo "faucet is not funded for one claim" >&2; exit 1; }

  recorded_block=$(cast block-number)
  temporary_record=$(mktemp "${RELEASE_RECORD%/*}/robinhood-testnet-launch.XXXXXX")
  jq -n \
    --argjson recordedBlock "$recorded_block" \
    --arg faucet "$statics_faucet" \
    --slurpfile statics "$STATICS_HANDOFF" \
    --slurpfile burntato "$ARTIFACT" \
    --slurpfile staticsBroadcast "$STATICS_GENESIS_BROADCAST_FILE" \
    --slurpfile faucetBroadcast "$STATICS_FAUCET_BROADCAST_FILE" \
    --slurpfile burntatoBroadcast "$BROADCAST_FILE" \
    --slurpfile operations "$OPERATION_LEDGER" \
    '{
      schemaVersion: 2,
      network: "Robinhood Chain Testnet",
      chainId: 46630,
      status: "live",
      recordedBlock: $recordedBlock,
      source: {
        staticsCommit: $statics[0].staticsSourceCommit,
        mainnetGenesisSourceCommit: $statics[0].mainnetGenesisSourceCommit,
        burntatoCommit: $burntato[0].sourceCommit
      },
      staticsGenesis: $statics[0],
      staticsFaucet: {
        address: $faucet,
        claimAmount: "200000000000000000000000",
        cooldownSeconds: 86400
      },
      burntato: $burntato[0],
      transactions: {
        staticsGenesisDeployment: [$staticsBroadcast[0].receipts[].transactionHash],
        staticsFaucetDeploymentAndFunding: [$faucetBroadcast[0].receipts[].transactionHash],
        burntatoDeployment: [$burntatoBroadcast[0].receipts[].transactionHash],
        burntatoOperations: $operations[0]
      }
    }' >"$temporary_record"
  mv "$temporary_record" "$RELEASE_RECORD"
  echo "wrote public combined testnet release record: $RELEASE_RECORD"
fi
