# Burntato

Burntato is a fully onchain Hot Potato game built as an EIP-2535 Diamond. ETH
accounting advances with purchases, while POTATO emission advances only with
actual holder time. Forward Recovery commitments, restricted token movement,
and a canonical Uniswap v4 market turn settled activity into permanently locked
liquidity and direct Treasury trading revenue.

The deployed defaults are one-hour rounds, a 10% price step, a fresh 100,000
POTATO emission budget, 10% holder opportunities vesting over 120 seconds, a
25% Winner / 50% Recovery / 25% Treasury purchase split, a 90% burn / 10%
Treasury Recovery split, and a 1% bilateral market fee. These are governed
defaults, not immutable constants. Each active or already-snapshotted target
round keeps its terms while changes apply to future unsnapshotted rounds.

POTATO uses the same Solady transfer-lock pattern proven by FWA.fun: minting,
burning, transfers involving the current authority or an administered
distributor, exact protocol movements, and exact transaction-scoped canonical
PoolManager movements are allowed; ordinary wallet transfers revert. The
initial Treasury recipient is a distributor, and later Treasury-recipient and
distributor changes are administered independently. Users can self-burn. The
initial v4 LP is permanently sent to the dead address, its native LP fee is
fixed at zero, and all hook fee ETH is sent directly to the hook's governed
Treasury recipient.

Administration remains available through the configured authority. The
guardian can add purchase or commitment pauses but cannot unpause. Protocol
finalization permanently disables only future Diamond cuts; it does not disable
economic, Treasury, hook, PoolManager, pause, or authority administration.
Explicitly transferring an authority or ownership role to the zero address is
the mechanism for relinquishing that role.

## Repository guide

- [`src/`](src/) — Diamond facets, namespaced storage, Solady POTATO, and the
  canonical v4 hook.
- [`script/`](script/) — deterministic local deployment and verification.
- [`test/`](test/) — unit, integration, fuzz, invariant, and deployment flows.
- [`docs/ECONOMICS.md`](docs/ECONOMICS.md) — configurable game and Recovery
  accounting.
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md) — token and canonical market
  integration.
- [`docs/GOVERNANCE.md`](docs/GOVERNANCE.md) — authority, guardian, market
  administration, and finalization.
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — local defaults, environment
  configuration, deployment, and verification.

The implementation is licensed under BUSL-1.1. FWA.fun is reference precedent,
not part of Burntato; see the pinned links in the integration guide.
