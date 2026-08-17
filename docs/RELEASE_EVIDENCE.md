# Release qualification evidence

## Single-sided genesis market candidate

Date: August 17, 2026

Source candidate: `c744882` on `feat/single-sided-launch`, based on merged
`main` commit `e42ffea`.

The candidate mints and reserves the configured genesis market allocation at
initialization. The local deployment default is 100 million POTATO. Canonical
market launch initializes at the configured upper tick, supplies POTATO only,
consumes no Treasury ETH, and permanently sends the position NFT to the dead
address. External buys remain closed by default; a real lifecycle test executes
a permissionless buyback and then sells distributed POTATO into the ETH it put
in the pool.

Qualification selected each owned test category explicitly. It did not use
`forge clean`, a forced build, a fork, or a deployed network.

| Scope | Command | Result |
| --- | --- | --- |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 31 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 44 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' -j 1` | 6 properties, 6,001 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 9 properties, 115,200 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 12 passed |

The deployment verifier confirms the genesis supply, Diamond balance,
reservation-backed readiness, upper-bound initial price, disabled public-buy
gate, and configured 100 million POTATO default. The final stacked audit is
deferred until the Treasury-funded reward-schedule PR is complete.

## Treasury buyback qualification history

Date: August 17, 2026

Source candidate: `32116ed` on `feat/12-treasury-buybacks`, stacked on PR 19
commit `73a9155`. The audit reviewed the equivalent pre-remediation content at
`db57949`; rebasing moved its exact transfer-authorization ordering into PR 19.

Environment: Foundry 1.5.1-stable, Solidity 0.8.26, Cancun EVM, local Linux
host. No fork, testnet, remote CI, or production network was used.

## Candidate behavior

Every Hot Potato purchase now divides native value into Winner, Recovery,
Treasury, and dedicated buyback accounting. Local defaults are 25%, 40%, 25%,
and 10%. The first three explicitly calculated shares round down and Treasury
receives the exact remainder, conserving every wei.

After canonical-market launch, anyone may execute a bounded, rate-limited
native-to-POTATO buyback. The default gross cap is 2 ETH, caller reward is 50
BPS of the gross slice, and delay is one block. The swap uses the canonical v4
PoolKey, exact input, and the terminal Uniswap price bound; it pays no bilateral
hook fee and sends output directly to the current Treasury. Partial-fill input
is restored to the dedicated reserve.

External pool buys start disabled while sells remain open. Only the Diamond's
exact-input buyback path can buy while the gate is closed. Hook ownership can
toggle the gate repeatedly before or after launch and Diamond finalization.
All canonical buy/sell hook fees continue to route directly to the hook's
governed Treasury recipient.

The ignored local specification package was updated but is intentionally not a
versioned PR artifact.

## Tests

Qualification selected every owned test path explicitly and used the repository
profiles: 1,000 fuzz runs and 256 invariant runs at depth 50.

| Scope | Command | Result |
| --- | --- | --- |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 31 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 41 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' -j 1` | 6 properties, 6,000 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 9 properties, 115,200 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 12 passed |

In aggregate, 84 deterministic tests, six fuzz properties, and nine stateful
invariants passed with no failures or skips. The executed flows include:

- exact four-way purchase conservation and buyback-reserve isolation from
  claims, Recovery rollover, and market launch;
- real canonical v4 launch, open sells, default-closed buys, repeated gate
  administration, and the fee-free privileged buyback while buys remain closed;
- cap and block delay, zero and 100% caller rewards, partial-fill restoration,
  current-Treasury rotation, unauthorized callback rejection, and a terminal
  block delay regression;
- Treasury receipt, distribution, self-burn, sale, and commitment-compatible
  POTATO movement through the Solady transfer restrictions;
- bilateral 0% and 100% fee edges with direct Treasury delivery and no Diamond
  fee accounting; and
- complete fresh deployment and verification of ten facets, 67 selectors,
  configured buyback state, the external-buy gate, hook ownership, and
  PoolManager administration.

## Audit and remediation

The committed pre-remediation candidate received an internal changed-scope
review using the audit workflow's general/DoS, precision/math, ERC-20/access,
AMM, and Diamond/proxy checklists. No Critical or High finding remained.

Two actionable boundary defects were remediated:

- `buybackBps` is appended after the pre-existing packed configuration fields,
  preserving their storage offsets if PR 12 facets are installed over PR 19;
  and
- an unrepresentable positive-delay addition now reverts, preventing repeated
  execution at the maximum block number.

The hook's privileged sender branch was also narrowed to the sole intended
shape: exact-input native-to-POTATO swaps. All other privileged swap shapes
revert before transfer authorization.

The reviewers confirmed no unresolved High, Medium, or Low implementation
finding after those corrections. ERC-20/access review found no defect in the
exact-transfer authorization order or current-Treasury output path. Precision
review confirmed four-way rounding, signed delta handling, partial-fill reserve
restoration, cap/reward edge cases, and aggregate ETH backing.

## Accepted FWA-compatible boundary

Caller reward is deliberately calculated from the selected gross slice before
the swap, matching the pinned FWA.fun implementation. A terminal-price partial
fill may therefore pay the configured reward when little or no native input is
consumed. Unspent swap input returns to the reserve, but the reward does not.
This is an explicit product decision bounded by governed cap, reward rate, and
block delay; it is not represented as fill-proportional compensation.

The buyback deliberately has no quote, TWAP, minimum output, deadline, or
caller-provided slippage field. Public execution and MEV exposure are accepted
properties of the approved FWA-style demand mechanism.

The token restriction governs underlying POTATO ERC-20 movement. Standard v4
ERC-6909 currency claims and third-party wrappers remain derivative assets and
do not invoke POTATO's transfer hook. The implementation does not claim
universal venue exclusivity for derivative exposure.

## Formatting and proof boundary

- `forge fmt --check` passed.
- `git diff --check` passed before the evidence update and is rerun before push.
- Focused `forge lint` over the changed buyback, type, and lifecycle files exited
  successfully; its visible bounded-cast and negative-path unchecked-return
  warnings remain review inputs rather than being globally suppressed.
- No `forge clean` or unscoped full build was used.

This evidence proves local compilation, repository-owned test execution, and
checklist-driven internal changed-scope review against the stated commits. It
does not prove deployed-chain state, production genesis parameters, canonical
chain dependency addresses, fork compatibility, remote CI, or an independent
third-party audit.
