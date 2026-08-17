# Deployment

`DeployBurntato.s.sol` deploys a complete local system in this order: timelock,
timelock-owned PoolManager, local Permit2 and WETH9, PositionDescriptor,
PositionManager, Diamond and facets, initializer, CREATE2 hook deployer, and
mined-address canonical hook. It installs the selector manifest, configures the
market, enables the initial Treasury distributor, configures buybacks, appoints
the guardian, and transfers Diamond authority to the timelock.

The hook and PoolManager are independently owned by the timelock. Deployment
does not renounce either owner and does not disable the PoolManager protocol-fee
controller surface. The hook starts with the configured Treasury fee recipient
and bilateral fee. External buys start disabled.

## Local defaults

| Setting | Default |
| --- | --- |
| Timelock delay | 1 day |
| Starting Hot Potato price | 0.01 ETH |
| Price increase | 1,000 BPS |
| Round timeout | 1 hour |
| Round emission budget | 100,000 POTATO |
| Emission step | 1,000 BPS |
| Emission vesting | 120 seconds |
| Purchase split | 2,500 / 4,000 / 2,500 / 1,000 BPS |
| Recovery split | 9,000 burn / 1,000 Treasury BPS |
| Hook fee | 100 BPS |
| Buyback cap / reward / delay | 2 ETH / 50 BPS / 1 block |
| Tick spacing | 60 |
| Initial tick | 92,100 |
| Genesis POTATO launch allocation | 100,000,000 POTATO |

Defaults are operational inputs, not protocol immutability claims. Zero
timelock delay is accepted, and the proposer may equal the bootstrap authority.
Starting price, round timeout, and emission vesting must remain nonzero. Round
timeout is bounded by `type(uint64).max` for deadline safety. BPS values are
bounded to 10,000; the purchase and Recovery splits must each sum to 10,000.
Zero price growth, emission step, emission budget, or hook fee is valid.

## Environment

The deployment and verification scripts accept:

```text
BURNTATO_DEPLOYER
BURNTATO_PROPOSER
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_TIMELOCK_DELAY
BURNTATO_STARTING_PRICE
BURNTATO_PRICE_INCREASE_BPS
BURNTATO_ROUND_TIMEOUT
BURNTATO_ROUND_EMISSION_BUDGET
BURNTATO_EMISSION_STEP_BPS
BURNTATO_EMISSION_VESTING_DURATION
BURNTATO_WINNER_BPS
BURNTATO_RECOVERY_BPS
BURNTATO_TREASURY_BPS
BURNTATO_BUYBACK_BPS
BURNTATO_RECOVERY_BURN_BPS
BURNTATO_RECOVERY_TREASURY_BPS
BURNTATO_BUYBACK_MAX_SPEND
BURNTATO_BUYBACK_CALLER_REWARD_BPS
BURNTATO_BUYBACK_DELAY_BLOCKS
BURNTATO_HOOK_FEE_BPS
BURNTATO_INITIAL_TICK
BURNTATO_TICK_SPACING
BURNTATO_TICK_LOWER
BURNTATO_TICK_UPPER
BURNTATO_POTATO_SEED
```

Numeric values use base units. Narrow BPS and tick inputs are range-checked
before conversion. Tick spacing must be inside the PoolManager domain; bounds
must be aligned to spacing, and the initial tick must equal the upper bound so
the locked genesis position starts entirely in POTATO.

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
```

Then run:

```bash
forge script script/VerifyBurntato.s.sol:VerifyBurntato \
  --rpc-url http://127.0.0.1:8545
```

## Verification checks

The verifier checks code and selector routing, complete protocol configuration,
timelock delay and roles, Diamond authority, guardian and pause state,
timelock-owned hook and PoolManager, hook token/fee/tick configuration, exact
uninitialized PoolKey, PositionManager dependencies, the configured genesis
POTATO supply and Diamond reservation, empty initial round state, disabled
external buys, the initial Treasury
distributor, and zeroed buyback state with the configured execution defaults.

After deployment, operations should separately exercise a timelock call to the
Diamond, a hook fee update, and a PoolManager owner function. Diamond
finalization should be tested only when the intent is to end all future cuts.
