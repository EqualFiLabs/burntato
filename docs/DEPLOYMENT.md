# Deployment

`DeployBurntato.s.sol` deploys a complete local system in this order: timelock,
timelock-owned PoolManager, local Permit2 and WETH9, PositionDescriptor,
PositionManager, Diamond shell and facets, optional immutable Operator rewards
router, initializer, CREATE2 hook deployer, and mined-address canonical hook. It
installs the selector manifest, configures the market, enables the initial
Treasury distributor, configures buybacks, appoints the reward allocator and
guardian, and transfers Diamond authority to the timelock.

The hook and PoolManager are independently owned by the timelock. Deployment
does not renounce either owner and does not disable the PoolManager protocol-fee
controller surface. The hook starts with the configured Treasury fee recipient
and bilateral fee. Self-contained local deployment keeps Operator rewards
disabled. Robinhood deployment requires an explicit nonzero Operator share.
External buys start disabled.

## Deployment modes

| Mode | Dependencies | Swap proof | Ownership boundary |
| --- | --- | --- | --- |
| Self-contained local | Newly deployed PoolManager, Permit2, WETH, descriptor, and PositionManager | Fast `PoolSwapTest` regression | Burntato timelock owns the local PoolManager and hook |
| Robinhood fork | Pinned v4 and Statics contracts from both chain-4663 manifests | Canonical Universal Router and Permit2 | Burntato timelock owns only the Diamond authority and Burntato hook |
| Robinhood testnet | Pinned chain-46630 v4 contracts plus a fresh standalone Statics Genesis replica | Live market launch against the canonical PoolManager and PositionManager | 120-second Burntato timelock owns the Diamond authority and Burntato hook |

The committed manifest pins block `45234855`, its block hash, and exact runtime
hashes for all nine canonical dependencies. Addresses and hashes are not
environment-overridable. Canonical deployment validates code plus PoolManager,
Permit2, PositionDescriptor, and WETH bindings before deploying any Burntato
contract. `deployments/statics-operators-robinhood-4663.json` separately pins
the finalized Statics integration at block `47690599`, including the Operators
NFT and Activation Registry hashes and their reciprocal bindings.

## Local defaults

| Setting | Default |
| --- | --- |
| Timelock delay | 1 day |
| Starting Hot Potato price | 0.01 ETH |
| Price increase | 1,000 BPS |
| Round timeout | 1 hour |
| Round timeout decay | 5 minutes |
| Minimum round timeout | 5 minutes |
| Round emission budget | 100,000 POTATO |
| Emission step | 1,000 BPS |
| Emission vesting | 120 seconds |
| Purchase split | 2,500 / 4,000 / 2,500 / 1,000 / 0 BPS |
| Recovery split | 9,000 burn / 1,000 Treasury BPS |
| Hook fee | 100 BPS |
| Operator share of hook fee | Disabled locally; required Robinhood input |
| Buyback cap / reward / delay | 2 ETH / 50 BPS / 1 block |
| Tick spacing | 60 |
| Initial tick | 92,100 |
| Genesis POTATO launch allocation | 100,000,000 POTATO |
| Reward allocator | Treasury recipient |

Defaults are operational inputs, not protocol immutability claims. Zero
timelock delay is accepted, and the proposer may equal the bootstrap authority.
Starting price, round timeout, minimum round timeout, and emission vesting must
remain nonzero. Round timeout is bounded by `type(uint64).max` for deadline
safety. Minimum timeout cannot exceed the initial timeout, and timeout decay
cannot exceed the initial timeout. Zero timeout decay is valid and produces
fixed resets. Protocol and Operator-share BPS values are bounded to 10,000; the
purchase and Recovery splits must each sum to 10,000. The bilateral hook fee
has the narrower 0-to-200 BPS domain, and the buyback caller reward has the
narrower 0-to-100 BPS domain. Zero price growth, emission step, emission budget,
or hook fee is valid.

## Environment

The deployment and verification scripts accept:

```text
BURNTATO_DEPLOYER
BURNTATO_PROPOSER
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_REWARD_ALLOCATOR
BURNTATO_TIMELOCK_DELAY
BURNTATO_STARTING_PRICE
BURNTATO_PRICE_INCREASE_BPS
BURNTATO_ROUND_TIMEOUT
BURNTATO_ROUND_TIMEOUT_DECAY
BURNTATO_MINIMUM_ROUND_TIMEOUT
BURNTATO_ROUND_EMISSION_BUDGET
BURNTATO_EMISSION_STEP_BPS
BURNTATO_EMISSION_VESTING_DURATION
BURNTATO_WINNER_BPS
BURNTATO_RECOVERY_BPS
BURNTATO_TREASURY_BPS
BURNTATO_BUYBACK_BPS
BURNTATO_OPERATOR_PURCHASE_BPS
BURNTATO_RECOVERY_BURN_BPS
BURNTATO_RECOVERY_TREASURY_BPS
BURNTATO_BUYBACK_MAX_SPEND
BURNTATO_BUYBACK_CALLER_REWARD_BPS
BURNTATO_BUYBACK_DELAY_BLOCKS
BURNTATO_HOOK_FEE_BPS
BURNTATO_OPERATOR_REWARD_SHARE_BPS
BURNTATO_INITIAL_TICK
BURNTATO_TICK_SPACING
BURNTATO_TICK_LOWER
BURNTATO_TICK_UPPER
BURNTATO_POTATO_SEED
```

Numeric values use base units. Narrow BPS and tick inputs are range-checked
before conversion. Tick spacing must be inside the PoolManager domain; bounds
must be aligned to spacing, and the initial tick must equal the upper bound so
the locked genesis position starts entirely in POTATO. Deployment and
verification both reject a hook fee above 200 BPS or buyback caller reward above
100 BPS. `BURNTATO_OPERATOR_REWARD_SHARE_BPS` remains independently configurable
through 10,000 BPS because it divides the already-capped hook fee rather than
increasing the fee charged to traders.

The CREATE2 hook helper accepts deployment only from the address that created
it. This keeps the mined hook address available to the same local broadcast
sequence between helper creation and hook creation.

## Commands

With Anvil running and the required account available:

```bash
forge script script/DeployBurntato.s.sol:DeployBurntato \
  --rpc-url http://127.0.0.1:8545 --broadcast
```

Set the emitted addresses before verification:

```text
BURNTATO_DIAMOND
BURNTATO_TIMELOCK
BURNTATO_POOL_MANAGER
BURNTATO_POSITION_MANAGER
BURNTATO_PERMIT2
BURNTATO_HOOK
BURNTATO_OPERATOR_REWARDS_ROUTER
```

Then run:

```bash
forge script script/VerifyBurntato.s.sol:VerifyBurntato \
  --rpc-url http://127.0.0.1:8545
```

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

forge script script/VerifyBurntatoLocalFork.s.sol:VerifyBurntatoLocalFork \
  --rpc-url http://127.0.0.1:8545 -vv
```

The public-only frontend handoff is
`artifacts/robinhood-local/deployment.json`. It contains the fork identity,
Diamond, timelock, hook, Operator router/share, Statics dependencies, facets,
initializer, and canonical dependency addresses. It never contains the RPC URL
or private key.

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

The testnet profile is fixed in code: the deployer holds proposer, guardian,
Treasury, and reward-allocator roles; timelock delay is 120 seconds; purchase
revenue is split 25% Winner, 30% Recovery, 20% Treasury, 10% buyback, and 15%
Operators. The bilateral swap hook fee is 1%, with 40% of that fee sent to the
same Operator rewards router (0.4% of swap volume) and 60% sent to Treasury.
Hot Potato purchases start at 0.00001 ETH and grow by 1%. The first holder in a
round receives a ten-minute timer; each later purchase reduces the reset by one
minute until the one-minute floor. Emission, Recovery, buyback, and market
settings retain the reviewed release defaults.

Use the phased wrapper so deployment verification occurs before market launch,
and so the timelock delay remains visible rather than hidden inside one command:

```bash
export ROBINHOOD_TESTNET_RPC_URL="$ROBINHOOD_TESTNET"
export PRIVATE_KEY="$PRIVATE_KEY"

scripts/deploy-robinhood-testnet.sh --deploy
scripts/deploy-robinhood-testnet.sh --verify
scripts/deploy-robinhood-testnet.sh --launch
scripts/deploy-robinhood-testnet.sh --schedule
# Wait until the reported timelock timestamp.
scripts/deploy-robinhood-testnet.sh --execute
scripts/deploy-robinhood-testnet.sh --check
```

The ignored `artifacts/robinhood-testnet/deployment.json` file is the local
machine-readable handoff. It contains only public addresses and the complete
launch configuration; deployment transaction hashes and final live readback
belong in the checked-in testnet deployment record.

## Verification checks

The verifier checks code and selector routing, complete protocol configuration
including the diminishing timeout domain,
timelock delay and roles, Diamond authority, guardian and pause state,
timelock-owned hook, hook token/fee/tick configuration, exact uninitialized
PoolKey, PositionManager dependencies, the configured genesis POTATO supply and
Diamond reservation, empty initial round state, disabled external buys, the
exact Operator router/share and immutable Statics bindings, the initial
Treasury distributor, independently configured reward allocator with zero
reward escrow, and zeroed buyback state with the configured execution defaults.
Self-contained verification additionally requires the Burntato timelock to own
its newly deployed PoolManager. Robinhood verification instead pins the
external canonical PoolManager and its dependency bindings without asserting
Burntato ownership.

After deployment, operations should separately exercise a timelock call to the
Diamond and a hook fee update. A PoolManager owner function belongs only in the
self-contained qualification path; Robinhood deployments must validate the
external owner's published operating process separately. Diamond finalization
should be tested only when the intent is to end all future cuts.
