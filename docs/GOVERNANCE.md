# Burntato governance and immutability

## Timelock authority

After genesis configuration, the Diamond authority is an OpenZeppelin `TimelockController` with a protocol-enforced minimum delay of one day. Genesis permits exactly one bootstrap handoff to that timelock and then permanently locks the authority address. The deployer receives no Timelock admin, proposer, canceller, or protocol authority role. Execution is permissionless after an authorized proposal's delay expires.

The Uniswap v4 PoolManager is deployed with both owner and protocol-fee controller disabled. No Burntato authority can later add a PoolManager protocol fee alongside the canonical 1% hook fee.

Before global finalization, delayed governance may:

- add, replace, or remove unfrozen Diamond selectors;
- update the default starting price and price-increase basis points for future unsnapshotted rounds;
- update the Treasury recipient while that parameter remains unfrozen;
- appoint or replace the guardian while that parameter remains unfrozen;
- irreversibly freeze parameters or installed selectors; and
- irreversibly finalize the protocol.

The canonical market configuration is one-shot. Neither the timelock nor the guardian can redirect hook revenue after configuration, substitute a different PoolManager or hook, relaunch the pool, recover the locked position, mint POTATO, burn another account's POTATO, or create a permanent token-transfer exemption.

## Guardian boundary

The guardian may only change these two pause bits from false to true:

- new Hot Potato purchases; and
- new Recovery commitments.

The guardian cannot clear either pause. Only the timelocked authority can unpause. The guardian also cannot upgrade, configure economics, change recipients, move assets, settle rounds, block claims, block matured emission materialization, block canonical market settlement, mint or burn POTATO, or reverse a freeze. Global finalization removes the guardian and clears both pause bits.

## Progressive immutability

Parameter freezing permanently disables the named setter path. Selector freezing permanently prevents that installed selector from being replaced or removed through `diamondCut()`.

Selector freezing is narrower than freezing an entire storage domain: another unfrozen selector could still be added that reaches the same namespaced Diamond storage. Integrators should not interpret an isolated selector freeze as a proof that all related state is immutable.

Global `finalizeProtocol()` provides the stronger terminal guarantee. It:

- disables every future Diamond cut;
- disables remaining administrative configuration;
- removes guardian authority;
- clears protocol pause state; and
- cannot be reversed.

Claims, permissionless settlement, matured emission materialization, POTATO self-burning, and canonical trading remain operational after finalization.

## Operational inspection

Use the Diamond loupe and governance views to inspect authority:

```text
authority()
authorityLocked()
guardian()
purchasesPaused()
commitmentsPaused()
protocolFinalized()
protocolConfig()
parameterFrozen(key)
selectorFrozen(selector)
facetAddress(selector)
facetFunctionSelectors(facet)
```

For a deployed environment, also confirm that the timelock delay is at least one day, the timelock self-holds `DEFAULT_ADMIN_ROLE`, only the intended governance account has proposer/canceller roles, `EXECUTOR_ROLE` is open at `address(0)`, the deployer has no privileged role, and the PoolManager owner and protocol-fee controller are both zero.
