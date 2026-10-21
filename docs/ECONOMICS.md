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
```

The six configured purchase shares must sum to 10,000 BPS and apply from the
second purchase of each round onward. Every `ProtocolConfig` BPS value is
bounded by 10,000; the installed buyback facet uses the narrower caller-reward
ceiling described below. That ceiling becomes immutable when upgrades are
removed or Diamond cuts are finalized.
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

The canonical launch profile is:

| Setting | Default |
| --- | ---: |
| Starting price | 0.01 ETH |
| Price increase | 10% |
| Round timeout | 1 hour |
| Timeout decay per purchase | 5 minutes |
| Minimum round timeout | 5 minutes |
| Round emission budget | 5,000 POTATO |
| Emission opportunity | 10% of remaining budget |
| Emission vesting duration | 4 minutes |
| Winner / next Winner / Recovery / Treasury / buyback / Operator split | 25% / 5% / 30% / 15% / 10% / 15% |
| Initial Winner reserve | 0.0105 ETH; opens Round 1 at 105% of its first-Grab price |
| Public wrap cap | 2,000,000 POTATO |
| Backing and redemption | 1 STATICS per POTATO |
| Recovery settlement | 100% redeemed to STATICS for Treasury |
| Maximum buyback slice | 1 ETH |
| Buyback caller reward | 0.5% |
| Buyback delay | 1 block |

## Purchases

A successful purchase pays exactly `nextPrice`, finalizes the outgoing holder's
emission, allocates ETH, installs the new holder, resets the deadline, and
calculates the next price. The first purchase requires enough accounted base
reward reserve to cover that round's complete snapshotted emission budget;
insufficient funding reverts the purchase and payment. The first purchase of
every round funds the next round's Winner reserve in full:

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
allocations always equal the purchase exactly. First-purchase funding and
`nextRoundWinnerShare` accumulate in the immediately following round's Winner
reserve. Permissionless direct funding may target any future round. Round
activation moves only that round's reserve into its Winner pool, clears the
per-round amount exactly once, and leaves later reserves untouched.
`fundWinnerReserve(targetRoundId)` rejects an active or past target.
`fundRoundReserves(targetRoundId, winnerAmount, recoveryAmount)` can fund either
or both reserves atomically and requires the two amounts to equal `msg.value`.
`roundFunding(roundId)` returns both aggregate reserves and the portions funded
through these permissionless contribution paths. The difference is protocol/game
funding: the genesis seed, the first Grab, and later configured next-round
allocations. Funding is irreversible, and raw ETH transfers do not enter reserve
accounting.

Fresh deployments fund the initial reserve to `ceil(startingPrice * 105%)`, so
Round 1 opens with a Winner pool above its first-Grab price before any purchase.
At 0.01 ETH the default seed is 0.0105 ETH; at 0.003 ETH it is 0.00315 ETH.
With an unchanged next-round starting price, a one-Grab round funds the next
opening Winner pool exactly 1:1; later Grabs or direct sponsorship increase it.
Buyback ETH remains separate from Winner, Recovery, and Treasury-claim
accounting.

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
deducted from both the round budget and the accounted base reward reserve.
Rewards transfer existing backed POTATO. An unearned portion remains available
inside the same round budget and informs the next holder's opportunity.
Same-timestamp cycling earns zero and does not advance the curve.

At the default four-minute vesting duration, a first holder earns 250 POTATO
after two minutes and reaches the same 500 POTATO maximum after four minutes.
An uninterrupted holder can fully vest one minute before the five-minute
minimum round deadline. The duration is governed and snapshotted per round;
changing deployment defaults does not alter an existing deployment.

The next successful purchase finalizes the outgoing opportunity. After full
vesting, anyone may materialize it while the round is active and the protocol is
unpaused. Unpaused settlement finalizes any unresolved final holder. The
per-opportunity finalized flag prevents double payment and no holder can exceed
their snapshotted maximum. During an emergency pause neither entry point may
materialize holder emission.

At the default 10% step, fully vested opportunities reproduce:

```text
5,000 -> 4,500 -> 4,050 -> 3,645 remaining
```

Unused inventory remains in the base reward reserve for later rounds; it is not
transferred to Recovery or Treasury or awarded to the winner. Every round starts
from its own configured budget. At the default, actual round rewards are at most
5,000 POTATO. Base reserve accounting excludes Recovery escrow and reserved or
unreserved Treasury inventory; there is no separate reserve vault.

## Recovery

POTATO commitments are forward-only to `currentRoundId + 1`. The target terms
have already been snapshotted before commitment opens. POTATO moves into Diamond
escrow through an exact transaction-scoped protocol transfer.

Anyone may sponsor any future round's Recovery ETH through
`fundRecoveryReserve(targetRoundId)` or the combined `fundRoundReserves` entry
point. Multiple contributions are additive, remain available while paused, and
are consumed exactly once into the named round's Recovery pool at activation.
Only these explicit permissionless contributions count as sponsorship in
`roundFunding`; automatic protocol/game allocations never do.
Sponsorship does not snapshot distant round configuration. Raw ETH transfers are
not credited. Sponsored ETH follows the ordinary claim rules and rolls forward
with the pool when the round has no commitments. POTATO commitments remain
limited to the immediately next round.

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
burnedPotato     = totalCommitted
staticsToTreasury = totalCommitted
```

Settlement burns every committed POTATO base unit and transfers exactly equal
STATICS to the current Treasury recipient. It uses the same capacity-reopening
rule as public redemption. No configurable Recovery ratio remains. A failed
underlying transfer reverts the complete settlement. Settlement still sets up
the next round when its reserve is underfunded; funding is checked at its first
purchase, independently of settlement and existing claims.

Recovery ETH claims are executable only while the protocol is unpaused and
remain state-dependent. Each ordinary claimant receives
`floor(recoveryPool * commitment / totalCommitted)`. The claimant whose weight
completes `totalCommitted` receives the exact remaining
`recoveryPool - recoveryPaid`, assigning all accumulated division dust to the
final outstanding commitment. A valid ordinary claim may therefore pay zero;
it still consumes its full weight so the eventual final claimant can close the
pool exactly. If the target round has zero commitments, its Recovery ETH rolls
into the next round; unused POTATO emission never does.

## STATICS-backed POTATO and Treasury

Fresh deployments start with zero POTATO supply. `wrap(amount)` deposits the
caller's STATICS and mints equal POTATO to that caller. The initial public cap
is 2,000,000 POTATO:

```text
availableCapacity = max(publicWrapCap - publicWrapOutstanding, 0)
publicWrapOutstanding += publicWrapAmount
```

`unwrap(amount)` burns the caller's POTATO and returns equal STATICS. Public
and Recovery redemption share the same accounting:

```text
publicWrapOutstanding -= min(amount, publicWrapOutstanding)
STATICS balance >= totalSupply
```

Capacity reopening is independent of token origin, so redeeming reserve-origin
rewards can reopen public capacity. Lowering the cap below outstanding usage
blocks additional public wrapping but never redemption. Unsolicited STATICS
creates surplus without changing the 1:1 redemption rate. Exact token balance
checks reject transfer-fee behavior and failures revert the complete operation.

Anyone may `fundRewardReserve(amount)` with their own STATICS, minting equal
backed POTATO only into the Diamond's base reward reserve. This funding and
buyback reserve credits do not consume public capacity. There is no unbacked
mint, standalone public burn, administrator backing withdrawal or base reserve
withdrawal. Treasury schedules remain separate inventory accounting.

No POTATO AMM, market seed, hook, launch curve or LP allocation is installed.
The 15% later-purchase Operator allocation continues to enter the standalone
rewards router.

Registered Statics Operators share router revenue by their stored activation
multiplier. Registration and higher-tier synchronization are prospective.
Ownership changes or a lower observed multiplier invalidate the registration;
its entire unpaid whole and fractional entitlement is redistributed over the
remaining registered weight. With no remaining weight, or when revenue arrives
with no registrations, the amount is claimable by Burntato's current Treasury
recipient. A new owner must register explicitly.

## Treasury buybacks

The buyback reserve accumulates from the second purchase of each round onward.
Anyone may also call payable `fundBuybackReserve()` with a positive amount.
Direct funding increases the tracked reserve exactly and does not execute a
buyback or change its cooldown. It remains available before purchase
initialization and regardless of the global protocol pause or Diamond
finalization. Plain native transfers to the Diamond increase its balance
but do not enter reserve accounting.

With a configured STATICS/WETH market, anyone may call parameterless
`buyback()`. The governed defaults select at most 1 ETH gross, reward the caller at 50 BPS of actual ETH spent, and
enforce a one-block delay. The caller-reward rate may be configured from 0
through 100 BPS:

```text
grossSlice = min(buybackReserveEth, maxSpend)
requestedInput = floor(grossSlice * 10_000 / (10_000 + callerRewardBps))
(ethSpent, staticsBought) = staticsSwap(requestedInput)
require ethSpent == requestedInput and staticsBought > 0
potatoReserveCredit = staticsBought
callerReward = floor(ethSpent * callerRewardBps / 10_000)
reserveRestored = grossSlice - ethSpent - callerReward
```

The Diamond wraps ETH into WETH and executes an exact-input WETH-to-STATICS
swap through the configured PoolManager. Direction follows the sorted pool
currencies; the price limit is `MIN_SQRT_PRICE + 1` or `MAX_SQRT_PRICE - 1`
accordingly. Normal market fees apply. Received STATICS is measured and backs
an exactly equal POTATO mint into the base reward reserve, outside public
capacity. The caller receives the tip in the same transaction.

A partial fill, zero spend, zero output, backing/reserve-credit failure or
rejected tip reverts atomically, preserving the PoolManager state, reserve,
caller balance and cooldown. The global emergency pause blocks execution while
leaving direct reserve funding live. There is no caller-provided quote,
slippage, deadline or recipient, and no additional oracle/minimum-price policy.

An initial reserve contribution and buybacks may fund rewards while game
purchases remain inactive. Funding must be measured in actual reserve POTATO;
there is no fixed ETH bootstrap target or call count.

## Treasury-funded round rewards

The configured reward allocator may move existing POTATO into a schedule for
future unactivated rounds:

```text
perRound = floor(amount / roundCount)
firstRoundRemainder = amount - perRound * roundCount
```

Every target round receives `perRound`; the first also receives the exact
base-unit remainder. Start/end rate deltas make allocation, cancellation, and
round activation constant-time even when schedules overlap. Funding increases
Diamond POTATO inventory and reservation together, so scheduled tokens are not
Treasury-claimable and cannot be spent by the base reward reserve.

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

Base and Treasury rewards finalize together. Both transfer existing backed
POTATO from their separately accounted inventory. The transfer is normal
POTATO, so it can be unwrapped, distributed through an allowed endpoint, or
committed to the immediately next Recovery market. It never increases total
supply.

Settlement releases every unearned Treasury reward base unit into unreserved,
claimable Treasury inventory instead of rolling it forward. The current reward
allocator may likewise cancel only still-unactivated schedule rounds. Current
round opportunity and already-earned reward are never reduced. Authority can
replace or zero the allocator independently of Treasury-recipient and
distributor administration, including after Diamond finalization.

Reference precedent:

- [FWA permissionless buyback](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol#L310-L383)
