# Burntato economics

## Hot Potato rounds

The first successful `buyPotato()` starts Round 1. Each successful purchase must pay the exact current price, records the buyer as the Current Holder, starts a fresh one-hour deadline, increments the Purchase Index, and raises the next price using upward basis-point rounding.

Every purchase is split exactly as follows:

- 25% Winner Pool;
- 50% Recovery Pool; and
- 25% Treasury purchase ETH.

The displaced holder receives no ETH from the purchase. The Current Holder at expiration remains the winner even if settlement is delayed. Anyone may call `settleRound()` after the deadline.

Purchase Index remains useful for price progression and analytics. It does not advance POTATO emission.

## Holder-time POTATO emission

Each round starts with a new emission budget of `100_000 * 1e18` POTATO base units. This is a hard ceiling and asymptotic target, not an amount force-minted at settlement.

When a purchase installs a new holder, Burntato snapshots:

```text
maxReward = floor(remainingEmission * 1,000 / 10,000)
earned = floor(maxReward * min(heldSeconds, 120) / 120)
```

All multiplication occurs before division. A holder surviving 120 seconds earns the full snapshot; a 30-second holder earns one quarter. Only `earned` is deducted from `remainingEmission`. Any unearned part stays unissued in the same round budget and informs the next holder's snapshot.

The next purchase finalizes the outgoing opportunity. Once 120 seconds have elapsed, anyone may call `materializeMaturedEmission()` while the round is active. Settlement finalizes any unresolved last-holder opportunity. Each opportunity is finalized once and can never exceed its snapshotted maximum.

This preserves the intended geometric curve for full holds:

```text
100,000 -> 90,000 -> 81,000 -> 72,900 remaining
```

Fast cycling still increases ETH volume and Hot Potato price, but same-timestamp cycling earns zero POTATO and does not consume the emission budget. Unused emission disappears at settlement. It is not minted, rolled over, sent to Treasury, Recovery, or the winner. The next round receives a fresh 100,000 POTATO budget.

## Forward Recovery Market

POTATO may be committed only to `currentRoundId + 1`, before that target round begins. A commitment is irrevocable and moves liquid POTATO into Diamond escrow without changing total supply. Splitting a position across addresses or transactions does not change aggregate pro-rata ownership.

When the target round settles with total commitment `B`:

```text
treasuryPotato = floor(B * 1,000 / 10,000)
burnedPotato = B - treasuryPotato
```

The burn-as-remainder calculation ensures every committed base unit is consumed exactly once. Recovery ETH belongs pro rata to committed accounts and is claimed with `claimRecovery(roundId, recipient)`. If no POTATO was committed for a round, its Recovery ETH rolls into the next round. Unclaimed fractional Recovery dust remains accounted inside the Diamond.

The winner claims with `claimWinner(roundId, recipient)`. Settlement itself makes no external ETH payout calls.

## Treasury and canonical market

Treasury accounting distinguishes purchase ETH, hook-fee ETH, and the 10% POTATO inventory created by Recovery settlement. Configured launch reserves cannot be claimed before pool launch; only unencumbered excess is available through the Treasury claim functions.

Once both configured reserves exist, anyone may call `launchMarket()`. The launch:

- initializes the exact native ETH/POTATO `PoolKey` with zero native LP fee;
- contributes the predetermined two-sided Treasury inventory;
- mints the only initial position directly to `0x000000000000000000000000000000000000dEaD`; and
- permanently marks the market launched.

No post-launch liquidity addition is accepted through the canonical hook. The locked position cannot be recovered by governance.

Exact-input buys pay 1% of gross POTATO output. The hook internally sells that POTATO fee to ETH without charging itself recursively. Exact-input sells pay 1% of gross ETH output. All realized fee ETH is recorded in canonical Treasury accounting; fees are not auto-compounded.

## Fixed protocol constants

| Constant | Value |
| --- | ---: |
| Round timeout | 1 hour |
| Round emission budget | 100,000 POTATO |
| Emission opportunity | 10% of remaining budget |
| Emission vesting maximum | 120 seconds |
| Winner / Recovery / Treasury purchase split | 25% / 50% / 25% |
| Recovery burn / Treasury POTATO split | 90% / 10% |
| POTATO decimals | 18 |
| Native pool LP fee | 0% |
| Bilateral hook fee | 1% |
| Locked LP recipient | `0x000000000000000000000000000000000000dEaD` |
