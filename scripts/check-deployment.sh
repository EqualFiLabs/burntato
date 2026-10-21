#!/usr/bin/env bash
set -euo pipefail
set -a
. /home/hooftly/.openclaw/workspace/.rpc
set +a
export BURNTATO_DEPLOYMENT_ARTIFACT=${1:?deployment artifact required}
export BURNTATO_DEPLOYMENT_PHASE=${2:-3} # 0 fresh, 1 funded, 2 active, 3 inspect
network=${3:-mainnet}
if [[ -n "${RPC_URL:-}" ]]; then
  export BURNTATO_LOCAL_RPC="$RPC_URL"
  network=local
fi
exec python3 scripts/run-private-rpc.py --network "$network" -- forge script script/VerifyBurntato.s.sol:VerifyBurntato --sig 'run()'
