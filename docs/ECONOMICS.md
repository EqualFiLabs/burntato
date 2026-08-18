# Economics

## Governed configuration and round snapshots

`ProtocolConfig` contains every configurable game percentage and timing value:

```text
startingPrice
priceIncreaseBps
roundTimeout
roundEmissionBudget
emissionStepBps
emissionVestingDuration
winnerBps / recoveryBps / treasuryBps / buybackBps
recoveryBurnBps / recoveryTreasuryBps
```

The four purchase shares must sum to 10,000 BPS and the two Recovery shares
must sum to 10,000 BPS. Every individual BPS value is bounded by 10,000.
Starting price, round timeout, and emission vesting duration must be nonzero.
Round timeout is at most `type(uint64).max`, which keeps every accepted
snapshotted deadline addition inside `uint256`. Zero price growth, zero emission
step, and a zero round emission budget are valid configurations.

Round N snapshots the complete configuration for Round N+1 when Round N
activates. Later governance changes cannot rewrite the active round or the
already-open target Recovery market. `Round.activated` is the lifecycle marker;
the emission budget is not used as a sentinel.

The local genesis defaults are:

| Setting | Default |
| --- | ---: |
| Starting price | 0.01 ETH |
| Price increase | 10% |
| Round timeout | 1 hour |
| Round emission budget | 100,000 POTATO |
| Emission opportunity | 10% of remaining budget |
| Emission vesting duration | 120 seconds |
| Winner / Recovery / Treasury / buyback split | 25% / 40% / 25% / 10% |
| Recovery burn / Treasury POTATO split | 90% / 10% |
| Bilateral hook fee | 1% |
| Maximum buyback slice | 2 ETH |
| Buyback caller reward | 0.5% |
| Buyback delay | 1 block |

## Purchases

A successful purchase pays exactly `nextPrice`, finalizes the outgoing holder's
emission, allocates ETH under the round snapshot, installs the new holder,
resets the deadline, and calculates the next price:

```text
winnerShare   = floor(price * winnerBps / 10_000)
recoveryShare = floor(price * recoveryBps / 10_000)
buybackShare  = floor(price * buybackBps / 10_000)
treasuryShare = price - winnerShare - recoveryShare - buybackShare

nextPrice = price + ceil(price * priceIncreaseBps / 10_000)
deadline  = purchaseTimestamp + roundTimeout
```

The Treasury receives deterministic split dust so the four allocations always
equal the purchase exactly. Buyback ETH is held in a dedicated reserve and is
not Winner, Recovery, Treasury-claim, or launch-seed accounting. Purchase count
and price progression do not consume POTATO emission.

## Holder-time emission budget

At round activation:

```text
remainingEmission = roundEmissionBudget
emittedPotato      = 0
```

Each incoming holder receives one snapshotted opportunity:

```text
maxReward = floor(remainingEmission * emissionStepBps / 10_000)
earned = floor(
    maxReward * min(heldSeconds, emissionVestingDuration)
    / emissionVestingDuration
)
```

Multiplication occurs before division in POTATO base units. Only `earned` is
deducted. An unearned portion remains unissued inside the same round budget and
informs the next holder's opportunity. Same-timestamp cycling earns zero and
does not advance the curve.

The next successful purchase finalizes the outgoing opportunity. After full
vesting, anyone may materialize it while the round is active. Settlement
finalizes any unresolved final holder. The per-opportunity finalized flag
prevents double minting and no holder can exceed their snapshotted maximum.

At the default 10% step, fully vested opportunities reproduce:

```text
100,000 -> 90,000 -> 81,000 -> 72,900 remaining
```

Unused budget is never force-minted, rolled forward, transferred to Recovery or
Treasury, or awarded to the winner. Every round starts from its own configured
budget. At the default, actual round emission is at most 100,000 POTATO.

## Recovery

POTATO commitments are forward-only to `currentRoundId + 1` and are irrevocable.
The target terms have already been snapshotted before commitment opens. POTATO
moves into Diamond escrow through an exact transaction-scoped protocol transfer.

At target-round settlement:

```text
treasuryPotato = floor(totalCommitted * recoveryTreasuryBps / 10_000)
burnedPotato   = totalCommitted - treasuryPotato
```

The burn-as-remainder rule consumes every committed base unit exactly once.
Recovery ETH is claimable pro rata. If the target round has zero commitments,
its Recovery ETH rolls into the next round; unused POTATO emission never does.

## Treasury and canonical market

Genesis mints a separately reserved market allocation into Diamond custody; the
local default is 100 million POTATO. It is not holder-time emission and cannot
be claimed before launch. Governance may resize the allocation before launch,
subject to the Diamond's available POTATO inventory.

Anyone may launch the exact canonical native ETH/POTATO v4 pool once the token
reservation is available. The initial price equals the position's upper tick,
so launch supplies POTATO only and consumes no Treasury ETH. The position NFT
is sent permanently to the dead address and the native LP fee is fixed at zero.
Buybacks subsequently supply ETH-side demand while external buys remain closed;
POTATO holders can sell into that liquidity immediately after ETH has entered
the pool.

The hook's governed `feeBps` applies bilaterally:

- buys retain the configured fraction of gross POTATO output, sell it once to
  ETH without recursively charging the internal conversion, and send all ETH
  directly to `feeAddress`;
- sells retain the configured fraction of gross ETH output and send it directly
  to `feeAddress`.

Hook revenue never enters the Diamond, is not launch reserve accounting, and is
not auto-compounded. The default fee is 1%, while 0% through 100% are valid.

## Treasury buybacks and external-buy gate

The buyback reserve accumulates from every purchase, including before launch.
After launch, anyone may call parameterless `buyback()`. The governed defaults
select at most 2 ETH gross, pay 50 BPS of that gross slice to the caller, and
enforce a one-block delay:

```text
grossSlice = min(buybackReserveEth, maxSpend)
callerReward = floor(grossSlice * callerRewardBps / 10_000)
requestedInput = grossSlice - callerReward
```

The Diamond executes an exact-input native-ETH-to-POTATO swap against only the
canonical pool with `sqrtPriceLimitX96 = MIN_SQRT_PRICE + 1`. It deliberately
uses no quote, TWAP, minimum output, deadline, or offchain sequencing. This
matches the deployed FWA.fun buyback behavior and accepts public execution and
MEV exposure as part of the demand mechanism. If the pool partially fills,
unspent requested input returns to the tracked reserve. The caller reward is
still based on the gross slice. A caller can therefore earn the configured
reward when the pool consumes little or none of the requested input. The
unspent swap input is restored, but the reward is not; governance bounds this
explicit tradeoff through the cap, reward rate, and block delay.

Buyback swaps bypass the bilateral hook fee and send purchased POTATO directly
from PoolManager to the current Diamond Treasury recipient. Treasury may hold,
burn, distribute, sell, or commit that POTATO under the normal token and
Recovery rules. No purchased POTATO is automatically burned.

External ETH-to-POTATO pool buys start disabled. While disabled, exact-input
sells remain available and only the Diamond buyback may buy. Hook ownership may
enable, disable, or re-enable external buys at any time, including after launch
and Diamond finalization.

## Treasury-funded round rewards

The configured reward allocator, initially the Treasury Safe, may move existing
POTATO into a schedule for future unactivated rounds:

```text
perRound = floor(amount / roundCount)
firstRoundRemainder = amount - perRound * roundCount
```

Every target round receives `perRound`; the first also receives the exact
base-unit remainder. Start/end rate deltas make allocation, cancellation, and
round activation constant-time even when schedules overlap. Funding increases
Diamond POTATO inventory and reservation together, so scheduled tokens are not
Treasury-claimable and cannot be spent by the market reservation.

At activation the scheduled amount becomes a separate Treasury reward budget.
Each holder snapshots:

```text
treasuryMaxReward =
    floor(remainingTreasuryEmission * emissionStepBps / 10_000)
treasuryEarned = floor(
    treasuryMaxReward * min(heldSeconds, emissionVestingDuration)
    / emissionVestingDuration
)
```

Base and Treasury rewards finalize together. Base reward is minted; Treasury
reward transfers existing escrowed POTATO. The transfer is normal POTATO, so it
can be self-burned, sold, distributed through an allowed endpoint, or committed
to the immediately next Recovery market. It never increases total supply.

Settlement releases every unearned Treasury reward base unit into unreserved,
claimable Treasury inventory instead of rolling it forward. The current reward
allocator may likewise cancel only still-unactivated schedule rounds. Current
round opportunity and already-earned reward are never reduced. Authority can
replace or zero the allocator independently of Treasury-recipient and
distributor administration, including after Diamond finalization.

Reference precedent:

- [FWA permissionless buyback](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol#L310-L383)
- [FWA external-buy gate](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWATokenHook.sol)
