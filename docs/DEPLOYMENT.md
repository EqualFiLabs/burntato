# Deployment

`DeployBurntato.s.sol` deploys a complete local system in this order: a
final-admin-owned PoolManager, local Permit2 and WETH9, PositionDescriptor,
PositionManager, Diamond shell and facets, optional immutable Operator rewards
router, initializer, CREATE2 hook deployer, and mined-address canonical hook. It
installs the selector manifest, configures the market, enables the initial
Treasury distributor, configures buybacks, appoints the reward allocator and
guardian, and transfers Diamond authority to the configured `finalAdmin`.
The payable Diamond creation also funds the configured initial Winner reserve,
which foundation initialization records before purchases can be enabled.

No `TimelockController` is deployed automatically. `finalAdmin` may be an EOA,
Safe, or governance contract. The hook and self-contained PoolManager are
independently owned by that address. Deployment does not renounce either owner
and does not disable the PoolManager protocol-fee controller surface. The hook
starts with the configured Treasury fee recipient and bilateral fee.
Self-contained local deployment keeps Operator rewards disabled. Robinhood
deployment requires an explicit nonzero Operator share. External buys start
disabled.

Deployment completes fully configured with `paused()` false while
`purchasesInitialized()` remains false. Only `buyPotato()` is gated by this
one-shot state. The current Diamond authority calls `initializePurchases()`
directly after verification; no delay is imposed by Burntato. Market launch,
Recovery, claims, settlement, and all other selectors are not gated by purchase
initialization. They remain subject to their ordinary lifecycle checks,
including the global emergency pause where applicable.

## Deployment modes

| Mode | Dependencies | Swap proof | Ownership boundary |
| --- | --- | --- | --- |
| Self-contained local | Newly deployed PoolManager, Permit2, WETH, descriptor, and PositionManager | Fast `PoolSwapTest` regression | `finalAdmin` owns the local PoolManager, hook, and Diamond authority |
| Robinhood fork | Pinned v4 and Statics contracts from both chain-4663 manifests | Canonical Universal Router and Permit2 | `finalAdmin` owns the Diamond authority and Burntato hook only |
| Robinhood testnet | Pinned chain-46630 v4 contracts plus a standalone Statics Genesis replica | Live market launch against the canonical PoolManager and PositionManager | Profile deployer is `finalAdmin`; canonical PoolManager ownership is external |

The committed manifest pins block `45234855`, its block hash, and exact runtime
hashes for all nine canonical dependencies. Addresses and hashes are not
environment-overridable. Canonical deployment validates code plus PoolManager,
Permit2, PositionDescriptor, and WETH bindings before deploying any Burntato
contract. `deployments/statics-operators-robinhood-4663.json` separately pins
the finalized Statics integration at block `47690599`, including the Operators
NFT and Activation Registry hashes and their reciprocal bindings. Both
validators read Robinhood's L2 block number and recent block hashes from the
ArbSys precompile; Solidity's `block.number` exposes the Ethereum parent height
on Robinhood and is not comparable to the manifest's L2 block height.

## Local defaults

| Setting | Default |
| --- | --- |
| Final admin | Second standard Anvil account |
| Starting Hot Potato price | 0.01 ETH |
| Price increase | 1,000 BPS |
| Round timeout | 1 hour |
| Round timeout decay | 5 minutes |
| Minimum round timeout | 5 minutes |
| Round emission budget | 10,000 POTATO |
| Emission step | 1,000 BPS |
| Emission vesting | 4 minutes |
| Purchase split from Grab 2 | 2,500 Winner / 200 next Winner / 4,000 Recovery / 2,300 Treasury / 1,000 buyback / 0 Operator BPS |
| First Grab | 100% to the next round Winner reserve |
| Initial Winner reserve | 0.0105 ETH |
| Recovery split | 9,000 burn / 1,000 Treasury BPS |
| Hook fee | 100 BPS |
| Operator share of hook fee | Disabled locally; required Robinhood input |
| Buyback cap / reward / delay | 2 ETH / 50 BPS / 1 block |
| Tick spacing | 60 |
| Initial tick | 170,280 |
| Genesis POTATO launch allocation | 100,000,000 POTATO across 56 locked positions |
| Reward allocator | Treasury recipient |

Game defaults are operational inputs, not protocol immutability claims. The final
admin must be nonzero and may equal the bootstrap authority. Starting price,
round timeout, minimum round timeout, and emission vesting must
remain nonzero. Round timeout is bounded by `type(uint64).max` for deadline
safety. Minimum timeout cannot exceed the initial timeout, and timeout decay
cannot exceed the initial timeout. Zero timeout decay is valid and produces
fixed resets. Protocol and Operator-share BPS values are bounded to 10,000; the
six-way purchase split used from Grab two onward and the Recovery split must
each sum to 10,000. The
bilateral hook fee has the narrower 0-to-200 BPS domain, and the buyback caller reward has the
narrower 0-to-100 BPS domain. Zero price growth, emission step, emission budget,
or hook fee is valid. The launch uses the fixed aggressive six-band profile at
tick spacing 60 and initial tick 170,280. The genesis allocation must fit the
aggregate `uint128` domain, and each of its 56 derived positions must have a
nonzero `uint128` amount maximum and liquidity value.

## Environment

The deployment and verification scripts accept:

```text
BURNTATO_DEPLOYER
BURNTATO_FINAL_ADMIN
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_REWARD_ALLOCATOR
BURNTATO_STARTING_PRICE
BURNTATO_PRICE_INCREASE_BPS
BURNTATO_ROUND_TIMEOUT
BURNTATO_ROUND_TIMEOUT_DECAY
BURNTATO_MINIMUM_ROUND_TIMEOUT
BURNTATO_ROUND_EMISSION_BUDGET
BURNTATO_EMISSION_STEP_BPS
BURNTATO_EMISSION_VESTING_DURATION
BURNTATO_WINNER_BPS
BURNTATO_NEXT_ROUND_WINNER_BPS
BURNTATO_RECOVERY_BPS
BURNTATO_TREASURY_BPS
BURNTATO_BUYBACK_BPS
BURNTATO_OPERATOR_PURCHASE_BPS
BURNTATO_RECOVERY_BURN_BPS
BURNTATO_RECOVERY_TREASURY_BPS
BURNTATO_INITIAL_WINNER_RESERVE
BURNTATO_BUYBACK_MAX_SPEND
BURNTATO_BUYBACK_CALLER_REWARD_BPS
BURNTATO_BUYBACK_DELAY_BLOCKS
BURNTATO_HOOK_FEE_BPS
BURNTATO_OPERATOR_REWARD_SHARE_BPS
```

Numeric values use base units. Narrow BPS inputs are range-checked before
conversion. Launch ticks, tick spacing, and the default 100 million POTATO seed
are intentionally not environment inputs; they are pinned to the reviewed
multicurve deployment profile. Deployment rejects a
hook fee above 200 BPS or buyback caller reward above
100 BPS. `BURNTATO_OPERATOR_REWARD_SHARE_BPS` remains independently configurable
through 10,000 BPS because it divides the already-capped hook fee rather than
increasing the fee charged to traders.

When `BURNTATO_INITIAL_WINNER_RESERVE` is absent, deployment derives
`ceil(startingPrice * 105%)` after the final price override so Round 1 opens
with a Winner pool equal to 105% of its first-Grab price. The variable can
explicitly override that funding amount. The broadcaster must hold the reserve
in addition to gas.

The CREATE2 hook helper accepts deployment only from the address that created
it. This keeps the mined hook address available to the same local broadcast
sequence between helper creation and hook creation.

## Commands

With Anvil running and the required account available:

```bash
forge script script/DeployBurntato.s.sol:DeployBurntato \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

After inspecting the deployment, initialize purchases:

```bash
forge script script/InitializeBurntato.s.sol:InitializeBurntato \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

## Initial buyback bootstrap

After the token-only market has launched and before game purchases are
initialized, an operator may seed initial sell-side liquidity with one direct
reserve contribution followed by one permissionless buyback:

```bash
BURNTATO_DIAMOND="<diamond>" \
BURNTATO_BOOTSTRAP_BUYBACK_WEI="<amount-in-wei>" \
PRIVATE_KEY="<broadcaster-key>" \
forge script script/BootstrapBurntatoBuyback.s.sol:BootstrapBurntatoBuyback \
  --rpc-url "<rpc-url>" --broadcast
```

No amount is hardcoded. The chosen amount must be positive and no greater than
the configured `maxSpend`. The helper refuses an unlaunched market, initialized
game purchases, a prior buyback, or unrelated reserve contents. Funding and
execution are deliberately separate transactions. If execution is interrupted
after funding, the same command resumes at the buyback only when the reserve
still equals the requested amount. It does not change the external-buy gate.

## Persistent Robinhood fork

Use an archive-capable RPC privately. The launcher does not print the URL:

```bash
ROBINHOOD_MAINNET="$ROBINHOOD_MAINNET" scripts/start-robinhood-fork.sh
```

The process stays in the foreground and serves chain `4663` on
`http://127.0.0.1:8545` until stopped. Never point the broadcast commands below
at a public Robinhood endpoint; they are guarded for Anvil and intentionally
use a localhost fork account.

```bash
PRIVATE_KEY="$ANVIL_PRIVATE_KEY" \
BURNTATO_OPERATOR_REWARD_SHARE_BPS="<required-bps>" \
forge script script/DeployBurntatoLocalFork.s.sol:DeployBurntatoLocalFork \
  --sig 'runLocalFork()' --rpc-url http://127.0.0.1:8545 --broadcast -vv

RPC_URL=http://127.0.0.1:8545 \
scripts/check-deployment.sh artifacts/robinhood-local/deployment.json
```

To bind Burntato to a freshly deployed Genesis replica on the same fork, pass
the replica addresses logged by `DeployStaticsGenesisLocalFork` and use the
Anvil-only replica entry point:

```bash
PRIVATE_KEY="$ANVIL_PRIVATE_KEY" \
STATICS_GENESIS_NFT_ADDRESS="<replica-genesis>" \
STATICS_GENESIS_ACTIVATION_REGISTRY_ADDRESS="<replica-registry>" \
BURNTATO_OPERATOR_REWARD_SHARE_BPS="<required-bps>" \
forge script script/DeployBurntatoLocalFork.s.sol:DeployBurntatoLocalFork \
  --sig 'runLocalForkReplica()' --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

The public-only frontend handoff is
`artifacts/robinhood-local/deployment.json`. It contains the fork identity,
Diamond, final admin, hook, Operator router/share, Statics dependencies, facets,
initializer, launch configuration, and canonical dependency addresses. It never
contains the RPC URL or private key.

Both local-fork deployment entry points enable one-second interval mining after
the deployment completes so block timestamps continue advancing for the UI.
Set `BURNTATO_LOCAL_INTERVAL_SECONDS` to choose another Anvil interval.

Fork tests skip when `ROBINHOOD_MAINNET` is absent. Strict release mode fails
instead. Run archive-RPC qualification locally; it is intentionally excluded
from CI so pull-request code never receives the RPC credential:

```bash
REQUIRE_ROBINHOOD_FORK=true ROBINHOOD_FORK_BLOCK=45234855 \
ROBINHOOD_MAINNET="$ROBINHOOD_MAINNET" \
forge test --match-path test/fork/RobinhoodBurntatoFork.t.sol -j 1 -vv

REQUIRE_ROBINHOOD_FORK=true ROBINHOOD_MAINNET="$ROBINHOOD_MAINNET" \
ROBINHOOD_OPERATOR_FORK_BLOCK=47690599 \
forge test --match-path test/fork/OperatorRewardsRobinhoodFork.t.sol -j 1 -vv
```

Frontends connect to chain ID `4663` at `http://127.0.0.1:8545` and read the
persisted artifact rather than scraping script output.

## Robinhood testnet launch

The chain-selected testnet manifests pin all canonical v4 bytecode and the
fresh Statics Genesis Operator NFT plus Activation Registry. Robinhood
testnet's PositionManager and descriptor report the absent mainnet WETH
address; the validator pins that observed binding explicitly while separately
validating the deployed testnet WETH. Burntato's market is native/POTATO and
does not route through either wrapped-native address.

The testnet profile is fixed in code: the deployer is final admin, guardian,
Treasury recipient, and reward allocator; purchase
revenue is split 25% Winner, 30% Recovery, 20% Treasury, 10% buyback, and 15%
Operators. The bilateral swap hook fee is 1%, with 40% of that fee sent to the
same Operator rewards router (0.4% of swap volume) and 60% sent to Treasury.

Use the phased wrapper so deployment inspection occurs before purchase
initialization. The final admin calls each post-deployment action directly:

```bash
export ROBINHOOD_TESTNET_RPC_URL="$ROBINHOOD_TESTNET"
export PRIVATE_KEY="$PRIVATE_KEY"

scripts/deploy-robinhood-testnet.sh --deploy
scripts/deploy-robinhood-testnet.sh --inspect
scripts/deploy-robinhood-testnet.sh --verify
scripts/deploy-robinhood-testnet.sh --launch
scripts/deploy-robinhood-testnet.sh --initialize
scripts/deploy-robinhood-testnet.sh --enable
scripts/deploy-robinhood-testnet.sh --check
```

The ignored `artifacts/robinhood-testnet/deployment.json` file is the local
machine-readable handoff. It contains only public addresses and launch
configuration; deployment transaction hashes and final live readback belong in
the checked-in testnet deployment record.

## Post-deployment inspection

`scripts/check-deployment.sh` performs read-only `cast` calls and emits compact
`PASS` or `FAIL` lines. It checks receipt status when `BROADCAST_FILE` is set,
deployed code presence, chain ID, governance roles, pause and foundation state,
market readiness, Treasury and reward roles, hook configuration, PositionManager
bindings, and Statics Operator bindings. It does not compare runtime code hashes
or deploy helper contracts. Set `RPC_URL` and pass the deployment JSON path.

The testnet wrapper's `--verify` mode uses Foundry's standard Blockscout source
verification flow. Override `BLOCKSCOUT_API_URL` only when the explorer changes
its API endpoint.

After deployment inspection, operations should execute the one-shot purchase
initializer from `finalAdmin`, then separately exercise an admin call to the
Diamond and a hook fee update. A PoolManager owner function belongs only in the
self-contained qualification path; Robinhood deployments must validate the
external owner's published operating process separately. Diamond finalization
should be tested only when the intent is to end all future cuts.
