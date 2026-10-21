# Burntato

Burntato is a fully onchain Hot Potato game built as an EIP-2535 Diamond. ETH
accounting advances with purchases, while POTATO emission advances only with
actual holder time. Forward Recovery commitments, restricted token movement,
and a restricted 1:1 STATICS-backed wrapper connect gameplay to a funded reward
reserve. Buybacks acquire STATICS through its existing Uniswap v4 market.

The launch profile gives the first holder one hour and shortens each later
purchase reset by five minutes until reaching a five-minute floor, alongside a
10% price step, a fresh 5,000 POTATO base reward budget, 10% holder
opportunities vesting over four minutes, a 25% Winner / 5% next-Winner / 30%
Recovery / 15% Treasury / 10% buyback / 15% Operators purchase split. Recovery
settlement burns all committed POTATO and sends equal underlying STATICS to
the current Treasury recipient. These game
values are governed defaults, not immutable constants. Each active or
already-snapshotted target round keeps its terms while changes apply to future
unsnapshotted rounds. Every successful purchase resets from its own timestamp;
purchase count drives the urgency schedule but still does not consume POTATO
emission.

Fresh deployments are fully configured and unpaused but begin with Hot Potato
purchases inactive. Only `buyPotato()` is blocked until the current Diamond
authority calls `initializePurchases()` once; wrapping, Recovery,
settlement, claims, and other selectors remain available. Burntato deploys no
mandatory timelock. The final admin may itself be an EOA, Safe, or governance
contract.

POTATO uses a Solady transfer-lock pattern adapted from the pinned FWA.fun
implementation: backed issuance, redemption, transfers involving the current
authority or an administered distributor, and exact protocol movements are
allowed; ordinary wallet transfers revert. The initial Treasury recipient is a
distributor, and later Treasury-recipient and distributor changes are administered
independently. Users wrap STATICS 1:1 and unwrap POTATO for equal STATICS. Public
wrapping initially allows 2,000,000 POTATO outstanding; redemption reopens that
capacity, including redemption of reserve-origin rewards. Lowering the cap never
blocks redemption. There is no standalone burn selector, unbacked token seed,
or default POTATO market.

Anyone can fund the Diamond's dedicated reward reserve with STATICS, minting
backed POTATO directly into that reserve without using public capacity. The first
Grab requires enough reserve for the entire snapshotted base budget. Holder-time
rewards transfer from the reserve; unused inventory remains for later rounds.
Settlement and existing claims remain available when the next round is underfunded.
Recovery escrow and funded Treasury reward schedules are accounted for separately.

The buyback share accumulates as dedicated Diamond ETH, and anyone may add a
positive amount directly through the tracked reserve funding entry point. Anyone
may spend a governed reserve slice to acquire STATICS through WETH, wrap exactly
the received amount into reward-reserve POTATO, and receive a caller tip in the
same transaction. The default gross slice is 1 ETH, the tip is 50 BPS, and the
delay is one block. Normal STATICS pool fees apply. The installed facet caps the
caller-reward rate at 1%; that ceiling becomes permanent when Diamond cuts are
finalized. A zero-output or partial-fill attempt reverts without consuming
reserve or cooldown. Swap, backing, reserve credit and tip failures all revert
together.

Recovery commitments normally remain locked through their target round. If an
activated predecessor remains completely holderless, its target commitments may
instead be withdrawn after one shared 30-day deadline. The first predecessor
purchase permanently closes that exceptional exit.

The Treasury Safe can also fund existing POTATO into future-round reward
schedules. Each target round applies that separate budget through the same
holder-time curve as base rewards, drawing from its own funded POTATO escrow. Unearned or canceled future allocations return to claimable Treasury
inventory. The reward allocator is independently administered and may be
replaced or disabled without changing the Treasury recipient or distributor
registry.

Administration remains available through the configured final-admin authority.
The guardian can activate one global emergency pause but cannot clear it. While
active, the pause stops purchases, Recovery commitments, holder-emission
materialization, public wrapping, buybacks, round settlement, and every Diamond
claim. It leaves redemption, stalled-Recovery withdrawals, reserve funding, reward
scheduling, views, and administration live. Protocol finalization permanently
disables only future Diamond cuts; it does not disable economic, Treasury, pause,
or authority administration. Removing the `diamondCut` selector is also a
supported maturity path; fresh deployment does neither. Diamond authority can be
relinquished only after purchases are initialized, the guardian is zero, and
the protocol is unpaused; independent ownership roles retain their own
zero-address transfer rules.

## Repository guide

- [`src/`](src/) — Diamond facets, namespaced storage, backed Solady POTATO, and the
  STATICS buyback integration.
- [`script/`](script/) — deterministic local deployment and verification.
- [`test/`](test/) — unit, integration, fuzz, invariant, and deployment flows.
- [`docs/ECONOMICS.md`](docs/ECONOMICS.md) — configurable game and Recovery
  accounting.
- [`docs/INTEGRATION.md`](docs/INTEGRATION.md) — backed token, reserve, and buyback
  integration.
- [`docs/GOVERNANCE.md`](docs/GOVERNANCE.md) — authority, guardian, economic
  administration, and finalization.
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — local defaults, self-contained
  deployment, pinned Robinhood fork qualification, and persistent frontend setup.

The implementation is licensed under BUSL-1.1. FWA.fun is reference precedent,
not part of Burntato and not security assurance for it; see the pinned links in
the integration guide.
