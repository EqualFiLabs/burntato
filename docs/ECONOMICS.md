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
winnerBps / recoveryBps / treasuryBps
recoveryBurnBps / recoveryTreasuryBps
```

The three purchase shares must sum to 10,000 BPS and the two Recovery shares
must sum to 10,000 BPS. Every individual BPS value is bounded by 10,000.
Starting price, round timeout, and emission vesting duration must be nonzero.
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
| Round emission budget | 100,000 POTATO |
| Emission opportunity | 10% of remaining budget |
| Emission vesting duration | 120 seconds |
| Winner / Recovery / Treasury purchase split | 25% / 50% / 25% |
| Recovery burn / Treasury POTATO split | 90% / 10% |
| Bilateral hook fee | 1% |

## Purchases

A successful purchase pays exactly `nextPrice`, finalizes the outgoing holder's
emission, allocates ETH under the round snapshot, installs the new holder,
resets the deadline, and calculates the next price:

```text
winnerShare   = floor(price * winnerBps / 10_000)
recoveryShare = floor(price * recoveryBps / 10_000)
treasuryShare = price - winnerShare - recoveryShare

nextPrice = price + ceil(price * priceIncreaseBps / 10_000)
deadline  = purchaseTimestamp + roundTimeout
```

The Treasury receives deterministic split dust so the three allocations always
equal the purchase exactly. Purchase count and price progression do not consume
POTATO emission.

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

Diamond Treasury accounting includes purchase ETH and Recovery-derived POTATO.
Prelaunch seed reservations cannot be claimed. When both configured reserves are
available, anyone may launch the exact canonical native ETH/POTATO v4 pool. The
initial position NFT is sent permanently to the dead address and the native LP
fee is fixed at zero.

The hook's governed `feeBps` applies bilaterally:

- buys retain the configured fraction of gross POTATO output, sell it once to
  ETH without recursively charging the internal conversion, and send all ETH
  directly to `feeAddress`;
- sells retain the configured fraction of gross ETH output and send it directly
  to `feeAddress`.

Hook revenue never enters the Diamond, is not launch reserve accounting, and is
not auto-compounded. The default fee is 1%, while 0% through 100% are valid.
