# Governance and administration

## Authority model

The Diamond recognizes one `authority` address. Deployment assigns it directly
to the configured `finalAdmin` and does not deploy a timelock. That address may
be an EOA, Safe, or governance contract; Burntato does not require authority to
have contract code or impose a delay. The current authority may transfer the
role repeatedly to any nonzero address. Governance may relinquish authority by
setting it to `address(0)` only after purchases are initialized, the guardian
is already zero, and the protocol is unpaused.

While authority exists it can:

- add, replace, or remove Diamond selectors until Diamond cuts are finalized;
- atomically update the complete default `ProtocolConfig`;
- update the Diamond Treasury recipient;
- administer POTATO distributors and buyback cap, reward, and delay;
- replace or zero the Treasury reward allocator;
- appoint or remove the guardian;
- set or clear the global protocol pause;
- reconfigure the Diamond's canonical market references before launch; and
- administer or transfer the independently owned Burntato hook when the same
  authority separately holds that ownership role.

Fresh deployments begin configured and unpaused with purchases inactive. Only
`buyPotato()` checks `purchasesInitialized()`. The current Diamond authority may
call `initializePurchases()` exactly once, directly and without a Burntato
timelock. The initializer does not gate market launch, Recovery, settlement,
claims, reward scheduling, or administrative selectors.

Economic updates do not rewrite active obligations. Round N snapshots the full
configuration for Round N+1 when Round N activates. An active round and an
already-open target Recovery market therefore keep the terms participants saw;
updates apply to future unsnapshotted rounds.

## Guardian

The guardian is containment-only. It may set the single global pause from
`false` to `true`, including an idempotent repeat call, but it cannot clear the
pause. Only the Diamond authority can unpause. The guardian cannot change
economics, recipients, market configuration, ownership, selectors, or any
other administrative state. Authority may set the guardian to `address(0)`.

While paused, Burntato rejects new Hot Potato purchases, new Recovery
commitments, matured holder-emission materialization and central protocol
minting, round settlement, and all Diamond Winner, Recovery, Treasury ETH, and
Treasury POTATO claims. The pause deliberately does not stop ordinary POTATO
approvals, Permit, allowed transfers, self-burning, an already-eligible stalled
Recovery withdrawal, canonical market launch and swaps, buybacks or direct
reserve funding, Treasury reward scheduling, views, or governance
administration.

Authority renunciation is guarded so an uninitialized game or containment
state cannot become permanent by accident. Purchases must already be
initialized; the remaining safe sequence is to set the guardian to
`address(0)`, clear the global pause if necessary, and only then set authority
to `address(0)`. Once authority is zero, no guardian remains and no address can
pause or administer the Diamond.

## Finalization

`finalizeProtocol()` is deliberately narrow. It permanently sets the Diamond's
`cutsDisabled` flag. After it executes, `diamondCut` always reverts.

Finalization does not:

- clear or change pause state;
- remove or change the guardian;
- freeze parameters or selectors individually;
- disable protocol, Treasury, hook, PoolManager, or market administration;
- transfer or renounce authority; or
- change any economic or custody state.

`protocolFinalized()` reports the Diamond-cut-disabled state. Parameter-freeze,
selector-freeze, and one-time authority-lock APIs do not exist.

## Independently governed market components

The configured final admin owns the `BurntatoSwapFeeHook`. Hook ownership controls
`feeAddress`, `feeBps`, the atomic Operator rewards router/share pair, and the
repeatable external-buy gate. In self-contained local deployments, the same
final admin also owns the newly deployed Uniswap v4 PoolManager and its native
administrative surface. Robinhood deployments instead use an externally
governed canonical PoolManager whose ownership Burntato neither receives nor
verifies. Diamond finalization does not affect any of these independent roles.

The PoolKey, token-only launch range, and reserved POTATO allocation may be
corrected before launch. Once the pool launches, the PoolKey, PoolManager, hook,
range, allocation, and locked LP are structurally fixed for that market.
Post-launch fee recipient, hook fee, and Operator allocation administration
remain available through hook ownership. Rotating away from a router affects
future fees only; its existing pull claims remain available because the router
has no administrator or sweep function. The total bilateral fee is permanently
capped at 200 BPS. The Operator share may still reach 10,000 BPS of that fee, so
governance can direct all realized hook revenue to Operators without raising the
trader fee.
Diamond authority may also change buyback cap, caller reward, and block delay
before or after launch and finalization. Setting the cap to zero disables
execution without changing accrued reserve accounting. The caller-reward rate
is capped at 100 BPS by the installed facet and applies to actual ETH spent,
not the selected reserve slice. Until Diamond cuts are finalized, authority can
replace that facet or its storage rules; after finalization, the 100 BPS ceiling
is permanent.

The Treasury reward allocator is independent from the Treasury recipient and
distributor registry. Genesis configures both roles to the Treasury Safe, but
authority may replace or zero only the allocator before or after finalization.
Changing any one of these three roles does not implicitly mutate the others.

## Operational checks

For a deployment, verify:

- `authority()` is the intended final-admin EOA, Safe, or governance address;
- `foundationConfigured()` is true before purchase activation;
- `purchasesInitialized()` is false during deployment verification and becomes
  true only after the current authority's one-shot call;
- `guardian()` and `paused()` match intended operations state;
- the hook owner is the intended final admin;
- for a self-contained deployment, the PoolManager owner is that final admin; for
  Robinhood, the PoolManager matches the pinned external deployment and owner;
- `feeAddress()`, `feeBps()`, `operatorRewardsRouter()`, and
  `operatorRewardShareBps()` match Treasury policy;
- `externalBuysEnabled()` matches current launch policy;
- buyback split, cap, caller reward, delay, reserve, and last execution block
  match Treasury policy;
- the reward allocator and funded POTATO escrow match Treasury policy;
- `protocolFinalized()` matches whether the installed buyback ceiling and all
  other Diamond facet behavior were intentionally made permanent;
- any planned authority renunciation follows purchase initialization and is
  preceded by a zero guardian and an unpaused protocol; and
- after finalization, governance setters still work while `diamondCut` reverts.
