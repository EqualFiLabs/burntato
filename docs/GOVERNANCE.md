# Governance and administration

## Authority model

The Diamond recognizes one `authority` address. Deployment assigns it to an
OpenZeppelin `TimelockController`, but the protocol does not hard-code a minimum
delay or require the authority to have contract code. The current authority may
transfer the role repeatedly to any address, including `address(0)` when
governance intentionally relinquishes control.

While authority exists it can:

- add, replace, or remove Diamond selectors until Diamond cuts are finalized;
- atomically update the complete default `ProtocolConfig`;
- update the Diamond Treasury recipient;
- administer POTATO distributors and buyback cap, reward, and delay;
- appoint or remove the guardian;
- set or clear purchase and commitment pauses;
- reconfigure canonical market infrastructure before launch;
- administer the independently owned canonical hook and PoolManager; and
- transfer any of those independent ownership roles under their native APIs.

Economic updates do not rewrite active obligations. Round N snapshots the full
configuration for Round N+1 when Round N activates. An active round and an
already-open target Recovery market therefore keep the terms participants saw;
updates apply to future unsnapshotted rounds.

## Guardian

The guardian is containment-only. It may change either pause bit from `false`
to `true`, but it cannot clear a pause. Only the Diamond authority can unpause.
The guardian cannot change economics, recipients, market configuration,
ownership, selectors, claims, settlement, emission materialization, or token
movement rules. Authority may set the guardian to `address(0)`.

Pauses stop only new Hot Potato purchases and/or new Recovery commitments.
Settlement, claims, matured emission materialization, POTATO self-burning, and
canonical trading remain live.

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

The timelock owns both the canonical `BurntatoSwapFeeHook` and the Uniswap v4
PoolManager at genesis. Hook ownership controls `feeAddress`, `feeBps`, and the
repeatable external-buy gate.
PoolManager ownership retains the native v4 administrative surface, including
the protocol-fee controller. Diamond finalization does not affect either owner.

The PoolKey, token-only launch range, and reserved POTATO allocation may be
corrected before launch. Once the pool launches, the PoolKey, PoolManager, hook,
range, allocation, and locked LP are structurally fixed for that market.
Post-launch fee recipient and hook fee
administration remain available through hook ownership.
Diamond authority may also change buyback cap, caller reward, and block delay
before or after launch and finalization. Setting the cap to zero disables
execution without changing accrued reserve accounting.

## Operational checks

For a deployment, verify:

- `authority()` is the intended timelock or governance address;
- the timelock delay and roles equal deployment configuration;
- `guardian()` and both pause bits match intended operations state;
- the hook and PoolManager owners are the intended timelock;
- `feeAddress()` and `feeBps()` match Treasury policy;
- `externalBuysEnabled()` matches current launch policy;
- buyback split, cap, caller reward, delay, reserve, and last execution block
  match Treasury policy;
- `protocolFinalized()` is false unless Diamond cuts were intentionally ended;
  and
- after finalization, governance setters still work while `diamondCut` reverts.
