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
- administer POTATO distributors, public wrap capacity, and buyback cap, reward,
  and delay;
- replace or zero the Treasury reward allocator;
- appoint or remove the guardian;
- set or clear the global protocol pause; and
- configure the existing STATICS/WETH buyback market.

Fresh deployments begin configured and unpaused with purchases inactive. Only
`buyPotato()` checks `purchasesInitialized()`. The current Diamond authority may
call `initializePurchases()` exactly once, directly and without a Burntato
timelock. The initializer does not gate wrapping, reserve funding, buybacks,
Recovery, settlement, claims, reward scheduling, or administrative selectors.
The activation helper checks actual backing and first-round reserve funding;
the first purchase of every round separately enforces its full snapshotted
reward budget. Next-round underfunding does not block settlement or claims.

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
commitments, public wrapping, matured holder-emission materialization,
buybacks, round settlement, and all Diamond Winner, Recovery, Treasury ETH, and
Treasury POTATO claims. The pause deliberately does not stop ordinary POTATO
approvals, Permit, allowed transfers, unwrapping, an already-eligible stalled
Recovery withdrawal, direct ETH or backed reward-reserve funding, Treasury
reward scheduling, views, or governance administration. Standalone Operator
router operations remain independent of the Diamond pause.

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
- disable protocol, Treasury, buyback-market or external-contract administration;
- transfer or renounce authority; or
- change any economic or custody state.

`protocolFinalized()` reports the Diamond-cut-disabled state. Parameter-freeze,
selector-freeze, and one-time authority-lock APIs do not exist.

Alternatively, authority may remove `IDiamondCut.diamondCut.selector` through a
Diamond cut when the system is mature. This leaves no installed upgrade entry
point but does not set `protocolFinalized()`; inspect the loupe as well as that
flag. Deployment performs neither maturity action.

## Independently governed market components

The configured STATICS/WETH market and its token, PoolManager and hook contracts
retain their external governance. Burntato neither deploys nor owns them.
Diamond finalization does not affect those independent roles. Authority can
change the configured buyback route after activation and finalization; the
setter validates deployed code, sorted STATICS/WETH currencies and compatible
recipients. Deployment additionally verifies pinned provenance/runtime and an
initialized pool.

The immutable Operator rewards router retains its fixed Diamond, Operators NFT
and Activation Registry bindings, with no administrator or sweep function. Its
Treasury fallback resolves Burntato's current Treasury recipient.

Diamond authority may also change buyback cap, caller reward, and block delay
before or after purchase activation and finalization. Setting the cap to zero
disables execution without changing accrued reserve accounting. The caller-reward rate
is capped at 100 BPS by the installed facet and applies to actual ETH spent,
not the selected reserve slice. Until Diamond cuts are finalized, authority can
replace that facet or its storage rules; after finalization, the 100 BPS ceiling
is permanent.

The Treasury reward allocator is independent from the Treasury recipient and
distributor registry. Deployment sets both roles explicitly and enables the
initial Treasury distributor, but authority may replace or zero only the
allocator before or after finalization.
Changing any one of these three roles does not implicitly mutate the others.
Authority and distributor endpoint exemptions remain in place. Changing public
wrap capacity never blocks redemption, and protocol reserve funding does not
consume that capacity. No backing or base reserve withdrawal API exists.

## Operational checks

For a deployment, verify:

- `authority()` is the intended final-admin EOA, Safe, or governance address;
- `foundationConfigured()` is true before purchase activation;
- `purchasesInitialized()` is false during deployment verification and becomes
  true only after the current authority's one-shot call;
- `guardian()` and `paused()` match intended operations state;
- `underlying()`, actual backing, supply, public wrap cap and outstanding usage;
- dedicated base reserve inventory and `nextRoundFundingStatus()`;
- `buybackMarket()` matches the pinned external STATICS/WETH pool;
- the Operator router matches the source-verified immutable bindings;
- buyback split, cap, caller reward, delay, reserve, and last execution block
  match Treasury policy;
- the reward allocator and funded POTATO escrow match Treasury policy;
- `protocolFinalized()` and the loupe's `diamondCut` lookup match the intended
  upgrade posture;
- any planned authority renunciation follows purchase initialization and is
  preceded by a zero guardian and an unpaused protocol; and
- after finalization, governance setters still work while `diamondCut` reverts.
