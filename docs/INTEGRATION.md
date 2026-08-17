# Burntato integration guide

## Canonical addresses

Gameplay, POTATO, Recovery, settlement, claims, Treasury accounting, governance, and loupe inspection all resolve through one `BurntatoDiamond` address. Facet implementation addresses are not user-facing integration targets.

The Uniswap v4 hook is a separate immutable-binding contract. Integrators should obtain the canonical hook and PoolKey from `marketConfig()` and `canonicalPoolKey()` rather than constructing alternatives.

## External Diamond surfaces

| Domain | Write methods | Primary views |
| --- | --- | --- |
| Game | `buyPotato()`, `materializeMaturedEmission()` | `currentRoundId()`, `getRound()`, `currentEarnedEmission()` |
| POTATO | `approve()`, `transfer()`, `transferFrom()`, `burn()` | ERC-20 metadata, balances, allowances, transient PoolManager allowance |
| Recovery | `commitRecovery()` | account and total commitment by target round |
| Settlement | `settleRound()` | round state through `getRound()` |
| Claims | winner, Recovery, Treasury ETH, and Treasury POTATO claims | Treasury recipient and unreserved availability |
| Market | `launchMarket()` | configuration, canonical PoolKey, launch state, readiness, locked recipient |
| Governance | timelocked configuration/freezing/finalization; guardian pause | authority, guardian, pause, freeze, and finalization state |
| Diamond | `diamondCut()` | EIP-2535 facet and selector loupe methods |

Canonical Solidity interfaces live in [`src/interfaces`](../src/interfaces/).

## Round identifiers and reads

Before the first purchase, `currentRoundId()` is zero. The first purchase activates Round 1. Settlement increments the identifier and activates the next round immediately.

`getRound(roundId)` returns the complete snapshotted round state: price parameters, holder and timing, Purchase Index, current emission opportunity, remaining/emitted POTATO, Winner and Recovery pools, carry-in, commitment denominator, and settlement flag. Indexers should consume `RoundStarted`, `PotatoPurchased`, `EmissionFinalized`, and `RoundSettled` in addition to reading current state.

Recovery commitments emitted during Round N target Round N+1. The `RecoveryCommitted.roundId` field is the target round, not the current source round.

## Restricted POTATO behavior

POTATO exposes familiar ERC-20 approvals for router compatibility, but approvals do not authorize wallet-to-wallet transfers. Both `transfer()` and `transferFrom()` still pass through the movement restriction and revert unless the movement is an exact authorized canonical PoolManager settlement.

Supported user actions are:

- receive POTATO from finalized holder-time emission;
- approve and commit POTATO to the next Recovery Market;
- approve a canonical router and trade through the exact hooked pool after launch; and
- call `burn(amount)` to destroy the caller's own balance.

There is no public or administrative mint, arbitrary third-party burn, permanent PoolManager exemption, or reusable transfer bypass. The hook opens an amount-bounded transient allowance, and each PoolManager movement consumes it in the same transaction.

## Canonical v4 market

The canonical `PoolKey` is:

```text
currency0    = native ETH (address(0))
currency1    = BurntatoDiamond / POTATO
fee          = 0
tickSpacing  = configured immutable launch spacing
hooks        = configured BurntatoSwapFeeHook
```

The initial implementation supports exact-input swaps only. Exact-output swaps, foreign keys, alternate hooks, repeated initialization, repeated launch, and post-launch liquidity additions revert. A different pool cannot move POTATO because it cannot obtain the canonical transient transfer allowance.

Hook events are `PoolLaunched`, `HookFee`, and `Trade`. Diamond market events are `MarketConfigured`, `MarketLaunched`, and `HookRevenueRecorded`. `MarketLaunched.poolId` is the canonical PoolId derived from the exact PoolKey.

## FWA.fun precedent and Burntato deviations

Burntato deliberately adapts the public TokenWorks FWA.fun relaunch implementation pinned at commit [`1085bf6ee255d6d4d13c374a66110bb25229dc76`](https://github.com/token-works/fwa-relaunch/tree/1085bf6ee255d6d4d13c374a66110bb25229dc76):

- [`FWAToken.sol`](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol) — one-shot launch and transaction-scoped PoolManager movement.
- [`FWATokenHook.sol`](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWATokenHook.sol) — canonical initialization gating and bilateral after-swap fee deltas.
- [`FWAToken.t.sol`](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/test/FWAToken.t.sol) and [`FWATokenHookSquat.t.sol`](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/test/FWATokenHookSquat.t.sol) — transfer-lock, fee, one-shot launch, and initialization-squatting regressions.

These are implementation precedents, not dependencies or authorities. Burntato differs by using namespaced Diamond and transient storage, fixed Treasury accounting instead of a mutable fee wallet, a two-sided Treasury seed, a permanently burned LP recipient, no fee auto-compounding, timelocked administration, and progressive immutability.
