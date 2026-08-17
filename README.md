# Burntato

Burntato is a fully onchain Hot Potato game built as an EIP-2535 Diamond. ETH accounting advances with purchases, while POTATO emission advances only with actual holder time. Forward Recovery commitments, restricted token movement, and a canonical Uniswap v4 pool turn settled game activity into permanently locked liquidity and Treasury trading revenue.

## Protocol at a glance

- A Hot Potato purchase resets a one-hour deadline, raises the next price by the snapshotted increase, and allocates ETH 25% to the winner, 50% to Recovery, and 25% to Treasury.
- Every round starts with a fresh 100,000 POTATO emission budget. Each holder can earn at most 10% of the then-remaining budget, linearly over 120 seconds.
- Only earned POTATO reduces the round budget. Rapid or atomic purchases still move price and ETH accounting but consume little or no emission.
- POTATO committed before the target round starts receives that round's Recovery share pro rata. Settlement burns 90% of committed POTATO and credits 10% to Treasury inventory.
- Ordinary wallet-to-wallet POTATO transfers revert. Users may self-burn or trade through the exact canonical hooked pool.
- The canonical pool has zero native LP fee, a 1% bilateral hook fee, and permanently locked initial liquidity. All realized fee ETH belongs to Treasury.

## Repository map

- [`src/`](src/) — Diamond, facets, shared storage, interfaces, and the canonical hook.
- [`script/`](script/) — deterministic local deployment and independent verification.
- [`test/`](test/) — unit, integration, fuzz, invariant, and deployment flows.
- [`docs/ECONOMICS.md`](docs/ECONOMICS.md) — round, emission, Recovery, Treasury, and market mechanics.
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md) — Diamond interfaces, events, token restrictions, and pool integration.
- [`docs/GOVERNANCE.md`](docs/GOVERNANCE.md) — timelock, guardian, freezing, and finalization.
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — local Anvil defaults, deployment commands, and verification.

## Focused development

```bash
forge test --match-path test/unit/PotatoGameLifecycle.t.sol -j 1
forge test --match-path test/integration/CanonicalMarketLifecycle.t.sol -j 1
forge test --match-path test/deployment/DeterministicDeployment.t.sol -j 1
```

The Uniswap v4 dependency graph is large. Prefer focused tests during development and reserve the complete suite for release qualification.

## License

Burntato is licensed under the [Business Source License 1.1](LICENSE). The Change Date is August 16, 2030, after which the Change License is MIT.
