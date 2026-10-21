# Deployment

`DeployBurntato.s.sol` deploys the Diamond shell and facets, immutable Operator
rewards router and initializer. It installs the selector manifest, configures
the existing STATICS/WETH buyback market, enables the initial Treasury
distributor, configures buybacks and public wrap capacity, appoints the reward
allocator and guardian, and transfers Diamond authority to the configured
`finalAdmin`. The payable Diamond creation also funds the configured initial
Winner reserve, which foundation initialization records before purchases can
be enabled.

No `TimelockController` is deployed automatically. `finalAdmin` may be an EOA,
Safe, or governance contract. STATICS, WETH, PoolManager and the external pool
hook retain their existing governance. Burntato creates no POTATO pool, LP,
hook, Permit2 deployment or token seed. Initial POTATO supply, backing, reward
reserve and public outstanding are zero.

Deployment completes fully configured with `paused()` false while
`purchasesInitialized()` remains false. Only `buyPotato()` is gated by this
one-shot state. The current Diamond authority calls `initializePurchases()`
directly after verification and actual reserve funding; no delay is imposed by
Burntato. Wrapping, buybacks, Recovery, claims, settlement, and all other
selectors are not gated by purchase initialization. They remain subject to
their ordinary lifecycle checks, including the global emergency pause where applicable.

## Deployment modes

| Mode | Dependencies | Swap proof | Ownership boundary |
| --- | --- | --- | --- |
| Standalone Anvil | Local STATICS/WETH and PoolManager fixtures, chain 31337 | Real local pool swap | Operator-free local profile; disposable development only |
| Robinhood fork | Pinned chain-4663 STATICS market and Operator manifests | Real WETH settlement and STATICS swap | `finalAdmin` holds Diamond authority; market governance is external |
| Robinhood testnet | Pinned chain-46630 STATICS market and Operator manifests | Existing STATICS/WETH pool | Explicit `finalAdmin`; market governance is external |
| Robinhood mainnet | Pinned chain-4663 STATICS market and Operator manifests | Existing STATICS/WETH pool | Explicit `finalAdmin`; market governance is external |

The read-only `PrepareBurntatoRobinhoodTestnet` script validates a Statics
Genesis replica's source revision, active epoch, reciprocal Genesis NFT and
Activation Registry bindings, finalized launch state, live Genesis vault epoch,
runtime hashes, and Robinhood block provenance. Its public handoff does not
replace the committed market and Operator dependency manifests, which must be
reviewed before deployment preflight can pass.

Public-network deployment uses the full Robinhood launch defaults. Local Anvil
mainnet-fork deployment also accepts the economic overrides below. Verification distinguishes
three states: deployed with zero supply and inactive purchases; funded while
inactive; and purchases initialized. No market-launch or external-buy-opening
phase remains.

The committed `statics-market-robinhood-4663.json` manifest pins block
`47690599`, its block hash, STATICS, WETH, PoolManager and hook runtime hashes,
and the exact initialized PoolKey/PoolId. Addresses and hashes are not
environment-overridable. Canonical deployment validates code, token decimals,
currency ordering, pool identity and initialized state before deploying any
Burntato contract. `deployments/statics-operators-robinhood-4663.json`
separately pins the finalized Statics integration at block `47690599`, including
the Operators NFT and Activation Registry hashes and their reciprocal bindings.
Both validators read Robinhood's L2 block number and recent block hashes from
the ArbSys precompile; Solidity's `block.number` exposes the Ethereum parent
height on Robinhood and is not comparable to the manifest's L2 block height.
The local-fork entrypoint checks historical hashes through Anvil RPC instead.

## Launch defaults

| Setting | Default |
| --- | --- |
| Final admin | Explicit deployment input |
| Starting Hot Potato price | 0.01 ETH |
| Price increase | 1,000 BPS |
| Round timeout | 1 hour |
| Round timeout decay | 5 minutes |
| Minimum round timeout | 5 minutes |
| Round emission budget | 5,000 POTATO |
| Emission step | 1,000 BPS |
| Emission vesting | 4 minutes |
| Purchase split from Grab 2 | 2,500 Winner / 500 next Winner / 3,000 Recovery / 1,500 Treasury / 1,000 buyback / 1,500 Operator BPS |
| First Grab | 100% to the next round Winner reserve |
| Initial Winner reserve | 0.0105 ETH |
| Recovery settlement | 100% of committed POTATO redeemed to STATICS for Treasury |
| Public wrap cap | 2,000,000 POTATO |
| Buyback cap / reward / delay | 1 ETH / 50 BPS / 1 block |
| Initial POTATO supply | Zero |
| Reward allocator | Explicit deployment input |

Public-network and mainnet-fork entrypoints use `launchDefaults()`. The
standalone development profile and Operator-free unit fixture use `localDefaults()`,
which assigns its 15% Operator allocation to Treasury instead.
Game defaults are operational inputs, not protocol immutability claims. The final
admin must be nonzero and may equal the bootstrap authority. Starting price,
round timeout, minimum round timeout, and emission vesting must
remain nonzero. Round timeout is bounded by `type(uint64).max` for deadline
safety. Minimum timeout cannot exceed the initial timeout, and timeout decay
cannot exceed the initial timeout. Zero timeout decay is valid and produces
fixed resets. Protocol BPS values are bounded to 10,000; the six-way purchase
split used from Grab two onward must sum to 10,000. The buyback caller reward
has the narrower 0-to-100 BPS domain. Zero price growth, emission step or
emission budget is valid. Every issued POTATO requires deposited or acquired
STATICS backing.

## Environment

The deployment and verification scripts accept:

```text
BURNTATO_DEPLOYER
BURNTATO_FINAL_ADMIN
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_REWARD_ALLOCATOR
PRIVATE_KEY
BURNTATO_SOURCE_COMMIT
BURNTATO_DEPLOYMENT_ARTIFACT
BURNTATO_DEPLOYMENT_PHASE
```

Mainnet requires all roles explicitly. Testnet defaults final admin, guardian,
Treasury and reward allocator to the canonical testnet deployer, while accepting
explicit role overrides. The local fork defaults to the standard Anvil roles and
can derive its deployer from `PRIVATE_KEY`; explicit role overrides take precedence.

Only `DeployBurntatoLocalFork` accepts these economic environment overrides:

```text
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
BURNTATO_INITIAL_WINNER_RESERVE
BURNTATO_BUYBACK_MAX_SPEND
BURNTATO_BUYBACK_CALLER_REWARD_BPS
BURNTATO_BUYBACK_DELAY_BLOCKS
```

Testnet and mainnet use fixed deployment defaults; their authorized onchain
configuration setters remain available. The obsolete Recovery-ratio and POTATO
hook-fee overrides are removed. Local overrides use checked narrowing and the
same protocol configuration validation as deployment. Numeric values use base units. The initial Winner reserve
defaults to `ceil(startingPrice * 105%)` using the selected local starting price,
unless explicitly overridden on the fork; the broadcaster must hold it in addition to gas.
Shell wrappers set the source commit and artifact path. Keep signing keys and
private RPC configuration outside the repository and load them through the
private operations environment.

## Commands

With the persistent Robinhood Anvil fork running, explicit roles set and an
Anvil signing key loaded in `PRIVATE_KEY`:

```bash
export BURNTATO_SOURCE_COMMIT=$(git rev-parse HEAD)
python3 scripts/run-private-rpc.py --network local -- \
  forge script script/DeployBurntatoLocalFork.s.sol:DeployBurntatoLocalFork \
  --sig 'runLocalFork()' --broadcast
```

Set `BURNTATO_LOCAL_RPC` to the loopback fork endpoint before either command.
After inspecting the deployment, approve STATICS and call `fundRewardReserve(amount)`, or fund through
buybacks below. Verify the dedicated reserve covers the complete first-round
budget before activating purchases. Set `BURNTATO_DIAMOND`, then initialize:

```bash
python3 scripts/run-private-rpc.py --network local -- \
  forge script script/InitializeBurntato.s.sol:InitializeBurntato --broadcast
```

The helper checks actual reserve funding and backing before accessing the
signing key. The first purchase of every round independently enforces the full
snapshotted base budget. Underfunding the successor does not block settlement
or existing claims.

For a standalone development chain, start `anvil --host 127.0.0.1 --chain-id 31337`
and run `DeployBurntatoLocal.s.sol:DeployBurntatoLocal` through the same local RPC
runner. It creates disposable STATICS, WETH and a real PoolManager with a funded
STATICS/WETH pool. Its Anvil broadcaster needs 100 ETH for fixture liquidity,
the initial Winner reserve, and gas. It mints local STATICS to that broadcaster;
POTATO still starts at zero and must be backed through wrapping or reserve funding.
The Operator-free local economics are fixed. These fixtures cannot run on public
network chain IDs.

## Initial buyback bootstrap

After deployment and before game purchases are initialized, an operator may
fund the complete bootstrap reserve and execute the first capped permissionless buyback:

```bash
BURNTATO_DIAMOND="<diamond>" \
BURNTATO_BOOTSTRAP_BUYBACK_WEI="<amount-in-wei>" \
python3 scripts/run-private-rpc.py --network mainnet -- \
  forge script script/BootstrapBurntatoBuyback.s.sol:BootstrapBurntatoBuyback \
  --broadcast
```

Load `PRIVATE_KEY` privately and select `mainnet`, `testnet` or `local` as
appropriate. No amount or call count is hardcoded; measure the actual backed
POTATO credited to `rewardReserve()`. The contribution may exceed
`maxSpend`; the contract limits each execution to the configured 1 ETH gross
slice. The helper refuses an unconfigured market, initialized game purchases, a
prior buyback, or unrelated reserve contents. Funding and execution are
deliberately separate transactions. If execution is interrupted after funding,
the same command resumes at the buyback only when the reserve still equals the
requested amount. It does not activate purchases.

Execute each remaining slice in a later block with the execution-only helper:

```bash
BURNTATO_DIAMOND="<diamond>" \
python3 scripts/run-private-rpc.py --network mainnet -- \
  forge script script/ExecuteBurntatoBuyback.s.sol:ExecuteBurntatoBuyback \
  --broadcast
```

Execute later slices in eligible blocks until the actual base reserve covers
the full snapshotted budget. The helper never funds the reserve, and it refuses
an unconfigured market, a global pause, or an empty reserve. Integer rounding
may leave a negligible tracked remainder. Each buyback atomically swaps ETH
through WETH to STATICS, credits backed reserve POTATO and pays the caller tip;
funding and the first execution remain separate transactions.

## Persistent Robinhood fork

Use an archive-capable RPC privately. The launcher does not print the URL:

```bash
ROBINHOOD_MAINNET="$ROBINHOOD_MAINNET" scripts/start-robinhood-fork.sh
```

The process stays in the foreground and serves chain `4663` on
`http://127.0.0.1:8545` until stopped. Never point the broadcast commands below
at a public Robinhood endpoint; they are guarded for Anvil and intentionally
use a localhost fork account.

Load a disposable Anvil signing key in `PRIVATE_KEY` and set the five public
roles from the Environment section. Run `DeployBurntatoLocalFork.runLocalFork()`
through the local command above. This entrypoint verifies Anvil support, fork
chain ID, both historical block hashes and runtime bindings. It uses the pinned
existing STATICS market and Operator dependencies. The initial preflight requires
the exact pinned fork height; `preflightDeployedLocalFork()` checks the same
provenance after local blocks have advanced. `runLocalForkReplica()` instead
accepts `STATICS_GENESIS_NFT_ADDRESS` and
`STATICS_GENESIS_ACTIVATION_REGISTRY_ADDRESS` for locally deployed Operator
replicas and validates their reciprocal bindings. This exception is confined
to chain-4663 Anvil; the STATICS market remains pinned.

The public-only frontend handoff is
`artifacts/robinhood-local/deployment.json`. It contains the fork identity,
Diamond, final admin, Operator router, Statics dependencies, facets,
initializer, launch configuration, runtime hashes, exact PoolKey and PoolId.
It never contains the RPC URL or private key.

The launcher pins block `47690599`. If a UI needs advancing timestamps on an
otherwise idle fork, deployment sets one-second interval mining by default.
`BURNTATO_LOCAL_INTERVAL_SECONDS=0` disables timed blocks and retains automining; set another number
of seconds to choose a different cadence.

Fork tests skip when `ROBINHOOD_MAINNET` is absent. Strict release mode fails
instead. Run archive-RPC qualification locally; it is intentionally excluded
from CI so pull-request code never receives the RPC credential:

```bash
BURNTATO_STRICT_FORK=true \
forge test --match-path test/fork/BackedStaticsFork.t.sol -j 2 -vv
```

This pins block `47690599` and executes real WETH/STATICS buybacks, backed holder
rewards, public redemption, Recovery-to-Treasury redemption and ETH claims.

Frontends connect to chain ID `4663` at `http://127.0.0.1:8545` and read the
persisted artifact rather than scraping script output.

## Robinhood testnet launch

The chain-selected testnet manifests pin the existing STATICS/WETH market and
Statics Operator dependencies. The testnet deployer is fixed to
`0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316`; final admin, guardian, Treasury
and reward allocator may be overridden explicitly or default to that deployer. The testnet signing key is
restricted to testnet and is read as data only after chain verification; its derived address is checked
before it can sign. Run preflight before choosing a state-changing phase.

Use the phased wrapper so deployment inspection occurs before purchase
initialization:

```bash
scripts/deploy-robinhood-testnet.sh --preflight
scripts/deploy-robinhood-testnet.sh --deploy --broadcast
scripts/deploy-robinhood-testnet.sh --inspect
```

Use `--prepare-statics` to validate and export a replica handoff before reviewing
the dependency manifest. Fund the backed reserve, then run `--check-staged`.
The final admin can use `--initialize` or export `--initialize-bundle` for a Safe;
this does not finalize upgrades. Run `--check` after activation. The wrapper
supports the same resume, verification and receipt-recording modes as mainnet.

The ignored `artifacts/robinhood-testnet/deployment.json` file is the local
machine-readable handoff. It contains only public addresses and launch
configuration. Existing checked-in deployed-address manifests remain historical
records of their original architecture.

## Robinhood mainnet launch

Mainnet reuses the validated chain-4663 STATICS market and finalized Statics
Operator manifests. It deploys only Burntato-owned contracts. The mainnet profile pins
the reviewed launch economics in code and requires every role explicitly:

```text
BURNTATO_DEPLOYER
BURNTATO_FINAL_ADMIN
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_REWARD_ALLOCATOR
```

The existing EqualFi Labs role separation is recorded in
`deployments/equalfi-roles-robinhood-4663.json`. The record preserves the
Statics Genesis deployer, governance Safe, Treasury Safe, and the absence of a
timelock for that standalone deployment. It is a public operational reference,
not an implicit Burntato role assignment; the Burntato roles remain explicit
deployment inputs.

`BURNTATO_DEPLOYER` must equal the address derived from `PRIVATE_KEY` during
deployment. The final admin, Treasury, and reward allocator must be nonzero.
The guardian may be the zero address. Mainnet does not accept environment
overrides for economics or canonical dependencies.

To rehearse the actual mainnet wrapper on the pinned Anvil fork, set
`BURNTATO_ANVIL_REHEARSAL=true` and `BURNTATO_LOCAL_RPC` to the loopback endpoint.
The rehearsal path requires chain 4663 and Anvil RPC support, then checks the
historical manifest hashes through RPC. It retains fixed mainnet economics and
explicit role inputs. Without that flag the wrapper targets Robinhood and uses
ArbSys provenance. Use `DeployBurntatoLocalFork` when testing economic overrides.

Load `ROBINHOOD_MAINNET` and any required signing key through the private
operations environment. Do not put either value in a command argument. Run
each phase separately and inspect its result before continuing:

```bash
scripts/deploy-robinhood-mainnet.sh --preflight
scripts/deploy-robinhood-mainnet.sh --deploy --broadcast
scripts/deploy-robinhood-mainnet.sh --inspect
```

Fund the reward reserve with actual STATICS or buybacks. There is no fixed ETH
bootstrap target, Treasury output band, required buyback count or external-buy
gate. Confirm the entire first-round budget before activation:

```bash
scripts/deploy-robinhood-mainnet.sh --check-staged
```

When the final admin is an EOA controlled by the operations key, use
`scripts/deploy-robinhood-mainnet.sh --initialize`. The wrapper verifies the
recorded source, runtime, configuration, funding and authority before broadcast.
When the final admin is a Safe or another contract, use `--initialize-bundle` and
submit the exported zero-value `initializePurchases()` call through that authority. No second buy-opening transition is needed.

After activation:

```bash
scripts/deploy-robinhood-mainnet.sh --check
```

Retain the schema-4 deployment artifact, source commit, encoded configuration and
dependencies, configuration hash, public addresses and runtime hashes. The
bootstrap helper resumes an exact completed reserve contribution without funding
it twice. Deployment wrappers require a clean committed candidate;
`--deploy` refuses existing deployment, broadcast, operation-ledger, initialization
bundle or release-record files. `--resume-deploy --broadcast` requires the original
artifact, broadcast sequence and identical committed source. `--verify` publishes
source to Blockscout with constructor arguments and never resumes transactions;
set `BLOCKSCOUT_API_URL` for mainnet (testnet has its explorer default).

`--bootstrap` requires an explicit `BURNTATO_BOOTSTRAP_BUYBACK_WEI`; `--buyback`
executes later slices. Both append successful transaction hashes to the operation
ledger. `--record` checks the activated deployment and successful chain receipts,
then writes the release record without overwriting an existing one. External
reserve funding and Safe initialization require `BURNTATO_FUNDING_TX_HASH` and
`BURNTATO_INITIALIZE_TX_HASH` when absent from that ledger. There is no required
buyback count. `BURNTATO_RELEASE_RECORD` chooses a new output path when a historical
release record already exists; preserve those historical records.

Artifacts include readable economic fields alongside the encoded configuration;
the verifier rejects disagreement between them. The compiler configuration is
Solidity 0.8.26, Cancun, optimizer 200, `via_ir = false`, and IPFS metadata hashes.

## Post-deployment inspection

`scripts/check-deployment.sh ARTIFACT PHASE NETWORK` runs the read-only Solidity
verifier against compiled source and the recorded deployment. It checks complete
facet selectors, owned runtime code, roles, pause/foundation state, economics,
backing, reserve/cap state, pool configuration and Statics Operator dependencies.
The immutable Operator router is compared against source runtime with its
compiler-reported immutable offsets patched to the expected bindings.

Phase 0 checks zero POTATO supply/reserve/outstanding, no active round and exact
initial Winner reserve; unsolicited STATICS surplus is allowed. Phase 1 requires
inactive purchases, no active round and the full first budget funded. Phase 2
requires initialized purchases and ordinary backing/reserve consistency. Before
the first Grab it also requires the complete first-round budget; once gameplay
has begun it does not require continued possession of that initial budget.
Phase 3 performs general deployment inspection without assuming an activation
phase; it is the default for `check-deployment.sh` and is used by `--inspect`. All phases expect the launch
configuration, so later intentional governance changes need their own expected
values. Network is `mainnet`, `testnet` or `local`; wrappers supply the appropriate
artifact and phase. Local modes additionally require Anvil RPC support.

After deployment inspection and reserve funding, operations should execute the
one-shot purchase initializer from `finalAdmin`, then separately exercise an
admin call to the Diamond. External market governance remains independent.
Diamond finalization or removal of `diamondCut` is a later maturity decision;
deployment performs neither.
