# Deterministic local deployment

## Scope

`DeployBurntato.s.sol` deploys a complete local Anvil system in a fixed order: TimelockController, PoolManager, local Permit2-compatible allowance transfer, WETH9, PositionDescriptor, PositionManager, Diamond and facets, initializer, CREATE2 hook deployer, and mined-address canonical hook. It then installs the selector manifest, initializes game and market configuration, assigns the guardian, and transfers Diamond authority to the timelock.

The local Permit2-compatible contract exists only to provide a compiler-compatible, self-contained Anvil flow. A production deployment must use the canonical Permit2 deployment for its chain.

## Local defaults

These values are development defaults, not final production genesis decisions:

| Parameter | Local value |
| --- | ---: |
| Deployer | Anvil account 0 |
| Timelock proposer/canceller | Anvil account 1 |
| Guardian | Anvil account 2 |
| Treasury recipient | Anvil account 3 |
| Timelock delay | 1 day |
| Hot Potato starting price | 0.01 ETH |
| Price increase | 10% |
| Initial market tick | 92,100, approximately 10,000 POTATO/ETH |
| Tick spacing | 60 |
| Tick range | full usable range for spacing 60 |
| Native launch reserve | 0.1 ETH |
| POTATO launch reserve | 1,000 POTATO |
| LP recipient | `0x000000000000000000000000000000000000dEaD` |

The production starting price, initial market price, tick range, spacing, seed amounts, and chain-specific v4 addresses remain explicit release decisions. Do not promote local defaults by accident.

## Deploy to Anvil

Start a fresh local node:

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337
```

In another shell, broadcast from the unlocked default deployer:

```bash
forge script script/DeployBurntato.s.sol:DeployBurntato \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --unlocked \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  -vv
```

No private key is stored in the repository or required for this local unlocked-account flow. The ignored `broadcast/` directory records local transaction data.

## Configuration overrides

The deployment reads the following optional environment variables:

```text
BURNTATO_DEPLOYER
BURNTATO_PROPOSER
BURNTATO_GUARDIAN
BURNTATO_TREASURY
BURNTATO_TIMELOCK_DELAY
BURNTATO_STARTING_PRICE
BURNTATO_PRICE_INCREASE_BPS
BURNTATO_INITIAL_TICK
BURNTATO_TICK_SPACING
BURNTATO_TICK_LOWER
BURNTATO_TICK_UPPER
BURNTATO_NATIVE_SEED
BURNTATO_POTATO_SEED
```

Numeric token and ETH values use base units. Environment values are range-checked before narrowing, so oversized basis-point or tick inputs revert instead of truncating. Tick spacing must remain within the PoolManager-supported domain, and tick bounds must be multiples of spacing and surround the initial tick. The timelock delay cannot be less than one day. The proposer must differ from the bootstrap deployer so the deployer cannot retain proposal authority.

## Verify the deployment

Copy the six core addresses from the deployment log and run:

```bash
BURNTATO_DIAMOND=<diamond> \
BURNTATO_TIMELOCK=<timelock> \
BURNTATO_POOL_MANAGER=<pool-manager> \
BURNTATO_PERMIT2=<permit2> \
BURNTATO_POSITION_MANAGER=<position-manager> \
BURNTATO_HOOK=<hook> \
forge script script/VerifyBurntato.s.sol:VerifyBurntato \
  --rpc-url http://127.0.0.1:8545 \
  -vv
```

The verifier reconstructs every expected selector group through the Diamond loupe and checks:

- nine facets and all canonical selector routes;
- Timelock delay, self-administration, intended proposer/canceller, open execution, and absent deployer roles;
- immutable Timelock authority of the Diamond and disabled PoolManager owner/protocol-fee controller;
- guardian, complete Hot Potato configuration, Treasury recipient, token metadata, empty initial supply, and unpaused/unfinalized state;
- complete market configuration, zero native LP fee, canonical PoolKey, and locked LP recipient;
- mined hook flags, immutable Diamond/PoolManager binding, and uninitialized pool state; and
- PositionManager binding to the exact PoolManager and Permit2-compatible contract.

The deployment test additionally executes the first purchase, full holder maturity, forward Recovery commitment, two settlements, Treasury accumulation, permissionless pool launch, and locked LP ownership.
