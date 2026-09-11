# Economics

## Governed configuration and round snapshots

`ProtocolConfig` contains every configurable game percentage and timing value:

```text
startingPrice
priceIncreaseBps
roundTimeout
roundTimeoutDecay
minimumRoundTimeout
roundEmissionBudget
emissionStepBps
emissionVestingDuration
winnerBps / nextRoundWinnerBps / recoveryBps / treasuryBps / buybackBps / operatorPurchaseBps
recoveryBurnBps / recoveryTreasuryBps
```

The six configured purchase shares must sum to 10,000 BPS and apply from the
second purchase of each round onward. The two Recovery shares must sum to
10,000 BPS. Every `ProtocolConfig` BPS value is bounded by 10,000;
the separate hook fee and installed buyback facet use narrower ceilings
described below. The latter becomes immutable only after Diamond cuts are
finalized.
Starting price, round timeout, minimum round timeout, and emission vesting
duration must be nonzero. Minimum round timeout cannot exceed the initial round
timeout, and timeout decay cannot exceed the initial timeout. Round timeout is
at most `type(uint64).max`, which keeps every accepted snapshotted deadline
addition inside `uint256`. Zero timeout decay restores fixed-duration resets.
Zero price growth, zero emission step, and a zero round emission budget are
valid configurations.

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
| Timeout decay per purchase | 5 minutes |
| Minimum round timeout | 5 minutes |
| Round emission budget | 100,000 POTATO |
| Emission opportunity | 10% of remaining budget |
| Emission vesting duration | 4 minutes |
| Winner / next Winner / Recovery / Treasury / buyback / Operator split | 25% / 2% / 40% / 23% / 10% / 0% |
| Initial Winner reserve | 0.0105 ETH; opens Round 1 at 105% of its first-Grab price |
| Recovery burn / Treasury POTATO split | 90% / 10% |
| Bilateral hook fee | 1% |
| Operator share of hook fee | Disabled; required for Robinhood deployment |
| Maximum buyback slice | 2 ETH |
| Buyback caller reward | 0.5% |
| Buyback delay | 1 block |

## Purchases

A successful purchase pays exactly `nextPrice`, finalizes the outgoing holder's
emission, allocates ETH, installs the new holder, resets the deadline, and
calculates the next price. The first purchase of every round funds the next
round's Winner reserve in full:

```text
if purchaseIndex == 0:
    nextRoundWinnerShare = price
    winnerShare = recoveryShare = buybackShare = operatorShare = treasuryShare = 0
```

The second and later purchases use the round's configured six-way split:

```text
winnerShare          = floor(price * winnerBps / 10_000)
nextRoundWinnerShare = floor(price * nextRoundWinnerBps / 10_000)
recoveryShare        = floor(price * recoveryBps / 10_000)
buybackShare         = floor(price * buybackBps / 10_000)
operatorShare        = floor(price * operatorPurchaseBps / 10_000)
treasuryShare        = price - all five rounded-down shares

priorPurchaseCount = purchaseIndex
maximumReduction = roundTimeout - minimumRoundTimeout
reduction = min(priorPurchaseCount * roundTimeoutDecay, maximumReduction)
resetDuration = roundTimeout - reduction
deadline = purchaseTimestamp + resetDuration
purchaseIndex += 1

nextPrice = price + ceil(price * priceIncreaseBps / 10_000)
```

With the local defaults, successful purchases receive 60, 55, 50, and so on
down to 5 minutes; the twelfth and every later purchase remain at 5 minutes.
Each deadline is based on the successful purchase timestamp, not the previous
deadline or elapsed time. Every successful purchase counts, including multiple
purchases at one timestamp. Failed transactions do not count, and a new round
starts again with the initial timeout.

The Treasury receives deterministic split dust on configured splits so the six
allocations always equal the purchase exactly. First-purchase funding,
`nextRoundWinnerShare`, and permissionless direct funding accumulate in the
Winner reserve. Round activation moves the complete reserve into that round's
Winner pool and clears it exactly once. `fundWinnerReserve(expectedRoundId)`
targets Round 1 before launch and Round N+1 during Round N; it reverts if the
expected target became stale before execution. Raw ETH transfers do not enter
reserve accounting.

Fresh deployments fund the initial reserve to `ceil(startingPrice * 105%)`, so
Round 1 opens with a Winner pool above its first-Grab price before any purchase.
At 0.01 ETH the default seed is 0.0105 ETH; at 0.003 ETH it is 0.00315 ETH.
With an unchanged next-round starting price, a one-Grab round funds the next
opening Winner pool exactly 1:1; later Grabs or direct sponsorship increase it.
Buyback ETH remains separate from Winner, Recovery, Treasury-claim, and
launch-seed accounting.

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

At the default four-minute vesting duration, a first holder earns 5,000 POTATO
after two minutes and reaches the same 10,000 POTATO maximum after four minutes.
An uninterrupted holder can fully vest one minute before the five-minute
minimum round deadline. The duration is governed and snapshotted per round;
changing deployment defaults does not alter an existing deployment.

The next successful purchase finalizes the outgoing opportunity. After full
vesting, anyone may materialize it while the round is active and the protocol is
unpaused. Unpaused settlement finalizes any unresolved final holder. The
per-opportunity finalized flag prevents double minting and no holder can exceed
their snapshotted maximum. During an emergency pause neither entry point may
materialize holder emission or reach the central protocol-mint path.

At the default 10% step, fully vested opportunities reproduce:

```text
100,000 -> 90,000 -> 81,000 -> 72,900 remaining
```

Unused budget is never force-minted, rolled forward, transferred to Recovery or
Treasury, or awarded to the winner. Every round starts from its own configured
budget. At the default, actual round emission is at most 100,000 POTATO.

## Recovery

POTATO commitments are forward-only to `currentRoundId + 1`. The target terms
have already been snapshotted before commitment opens. POTATO moves into Diamond
escrow through an exact transaction-scoped protocol transfer.

Anyone may sponsor the next round's Recovery ETH through
`fundRecoveryReserve(expectedRoundId)`. The expected-round guard prevents a
transaction from silently retargeting after settlement. Multiple contributions
are additive, remain available while paused, and are consumed exactly once into
the target round's Recovery pool at activation. Raw ETH transfers are not
credited. Sponsored ETH follows the ordinary claim rules and rolls forward with
the pool when the round has no commitments.

Commitments normally remain irrevocable once the predecessor receives its first
holder. There is one liveness escape for an activated predecessor that has never
had a holder: its first target commitment starts a shared 30-day deadline. After
that deadline, each committer may withdraw their complete target commitment
while the predecessor is still current and holderless and the target remains
inactive. A later commitment does not restart the clock. The final withdrawal
clears it, so a later first commitment starts a new 30-day period. The exit stays
available while the global protocol pause is active. The predecessor's first
purchase permanently closes the exit, and normal settlement consumes
commitments exactly as before.

At target-round settlement:

```text
treasuryPotato = floor(totalCommitted * recoveryTreasuryBps / 10_000)
burnedPotato   = totalCommitted - treasuryPotato
```

The burn-as-remainder rule consumes every committed POTATO base unit exactly
once. Recovery ETH claims are executable only while the protocol is unpaused
and remain state-dependent. Each ordinary claimant receives
`floor(recoveryPool * commitment / totalCommitted)`. The claimant whose weight
completes `totalCommitted` receives the exact remaining
`recoveryPool - recoveryPaid`, assigning all accumulated division dust to the
final outstanding commitment. A valid ordinary claim may therefore pay zero;
it still consumes its full weight so the eventual final claimant can close the
pool exactly. If the target round has zero commitments, its Recovery ETH rolls
into the next round; unused POTATO emission never does.

## Treasury and canonical market

Genesis mints a separately reserved market allocation into Diamond custody; the
local default is 100 million POTATO. It is not holder-time emission and cannot
be claimed before launch. Governance may resize the allocation before launch,
subject to the Diamond's available POTATO inventory.

The default initial and upper tick is 170,280. With the default 100 million
POTATO allocation, an otherwise untouched pool, and the full 2 ETH gross
bootstrap, the first buyback acquires approximately 33.06 million POTATO. At
the resulting pool state, selling a fully vested first-holder emission of
10,000 POTATO returns approximately 0.00089 ETH after the default bilateral
hook fee. That is below the 0.001 ETH the corresponding 0.01 ETH game purchase
contributes to the buyback reserve. These figures describe the deterministic
default bootstrap path, not a minimum-output or market-price guarantee; prior
pool activity, configuration changes, and transaction ordering change the
realized result.

Anyone may launch the exact canonical native ETH/POTATO v4 pool once the token
reservation is available. The initial price equals the position's upper tick,
so launch supplies POTATO only and consumes no Treasury ETH. The position NFT
is sent permanently to the dead address and the native LP fee is fixed at zero.
Buybacks subsequently supply ETH-side demand while external buys remain closed;
POTATO holders can sell into that liquidity immediately after ETH has entered
the pool.

The hook's governed `feeBps` applies bilaterally. Its separately governed
`operatorRewardShareBps` splits that existing fee without increasing it:

```text
operatorAmount = floor(realizedNativeFee * operatorRewardShareBps / 10_000)
treasuryAmount = realizedNativeFee - operatorAmount
```

- buys retain the configured fraction of gross POTATO output, sell it once to
  ETH without recursively charging the internal conversion, and split the
  realized ETH; and
- sells retain the configured fraction of gross ETH output and split that ETH
  identically.

Hook revenue never enters the Diamond, is not launch reserve accounting, and is
not auto-compounded. The Treasury remainder, including split dust, goes to
`feeAddress`; the Operator portion goes to the standalone rewards router. The
default fee is 1%, while 0% through 2% are valid. The Operator share remains
valid from 0% through 100% of that already-capped fee.

The Robinhood launch profile uses a 25/30/20/10/15 purchase split for Winner,
Recovery, nominal Treasury, buyback, and Operators. It also routes 40% of the
existing 1% hook fee to Operators, equal to 0.4% of swap volume; Treasury
receives the other 0.6% of volume. Both sources enter the same router.

Registered Statics Operators share router revenue by their stored activation
multiplier. Registration and higher-tier synchronization are prospective.
Ownership changes or a lower observed multiplier invalidate the registration;
its entire unpaid whole and fractional entitlement is redistributed over the
remaining registered weight. With no remaining weight, or when revenue arrives
with no registrations, the amount is claimable by Burntato's current Treasury
recipient. A new owner must register explicitly.

## Treasury buybacks and external-buy gate

The buyback reserve accumulates from every purchase, including before launch.
Anyone may also call payable `fundBuybackReserve()` with a positive amount.
Direct funding increases the tracked reserve exactly and does not execute a
buyback or change its cooldown. It remains available before purchase
initialization and regardless of the global protocol pause, market launch, or
Diamond finalization. Plain native transfers to the Diamond increase its balance
but do not enter reserve accounting.

After launch, anyone may call parameterless `buyback()`. The governed defaults
select at most 2 ETH gross, reward the caller at 50 BPS of actual ETH spent, and
enforce a one-block delay. The caller-reward rate may be configured from 0
through 100 BPS:

```text
grossSlice = min(buybackReserveEth, maxSpend)
requestedInput = floor(grossSlice * 10_000 / (10_000 + callerRewardBps))
(ethSpent, potatoBought) = canonicalSwap(requestedInput)
require ethSpent > 0 and potatoBought > 0
callerReward = floor(ethSpent * callerRewardBps / 10_000)
reserveRestored = grossSlice - ethSpent - callerReward
```

The Diamond executes an exact-input native-ETH-to-POTATO swap against only the
canonical pool with `sqrtPriceLimitX96 = MIN_SQRT_PRICE + 1`. It deliberately
uses no quote, TWAP, user minimum output, deadline, or offchain sequencing.
Public execution and MEV exposure remain part of the demand mechanism. If the
pool partially fills, every unspent base unit outside actual spend and its
proportional reward returns to the tracked reserve. A zero-spend or zero-output
attempt reverts atomically, preserving reserve, caller balance, and cooldown.
The extreme terminal-price path also reverts atomically. This removes the
reserve leakage present when compensation was calculated from requested input
without imposing a full-fill or user-facing slippage requirement.

Buyback swaps bypass the bilateral hook fee and send purchased POTATO directly
from PoolManager to the current Diamond Treasury recipient. Treasury may hold,
burn, distribute, sell, or commit that POTATO under the normal token and
Recovery rules. No purchased POTATO is automatically burned.

External ETH-to-POTATO pool buys start disabled. While disabled, exact-input
sells remain available and only the Diamond buyback may buy. Hook ownership may
enable, disable, or re-enable external buys at any time, including after launch
and Diamond finalization.

An initial demand bootstrap can therefore launch the token-only pool, fund the
reserve directly, and execute one buyback while game purchases and external
pool buys remain closed. The resulting pool inventory supports POTATO sells
without pre-minting a fixed circulating supply. The funding amount is an
explicit deployment input and remains subject to the governed buyback cap.

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
