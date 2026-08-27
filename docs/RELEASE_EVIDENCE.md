# Release qualification evidence

## Single-sided genesis market candidate

Date: August 17, 2026

Source candidate: `05aa73d` on `feat/single-sided-launch`, based on merged
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
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 45 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' -j 1` | 6 properties, 6,001 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 9 properties, 115,200 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 13 passed |

The deployment verifier confirms the genesis supply, Diamond balance,
reservation-backed readiness, upper-bound initial price, disabled public-buy
gate, and configured 100 million POTATO default. Audit remediation rejects the
terminal v4 tick whose `MAX_SQRT_PRICE` cannot initialize, and targeted market
and deployment suites pass with that regression.

## Treasury-funded reward schedule candidate

Date: August 17, 2026

Source candidate: `6b371e4` on `feat/treasury-reward-schedules`, stacked on the
single-sided launch branch at `05aa73d`. Core schedule accounting is commit
`bf6848b`.

The configured reward allocator, initially the Treasury recipient, can move
existing POTATO into exact future-round schedules without approval or minting.
O(1) start/end deltas compose overlapping schedules. Activated rounds apply a
separate Treasury budget through the snapshotted holder-time curve; earned
amount transfers escrowed POTATO while base reward remains the only mint.
Settlement releases unearned funds and cancellation releases only unactivated
schedule value into claimable Treasury inventory.

Qualification selected each owned test category explicitly:

| Scope | Command | Result |
| --- | --- | --- |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 31 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 51 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' -j 1` | 7 properties, 7,001 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 9 properties, 115,200 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 13 passed |

Focused schedule flows prove full and partial holds, base-unit remainder,
overlap, future-only cancellation, single materialization, settlement release,
Recovery commitment eligibility, no Treasury-reward minting, post-finalization
allocator administration, insufficient-balance rejection, and aggregate
reservation isolation. Focused lint, formatting, and diff checks passed.

This remains local Foundry evidence. It does not prove a fork, testnet,
deployed-network state, remote CI, or independent third-party review.

## Final stacked audit

The combined `e42ffea..0035de7` implementation received checklist-driven
reviews for general Solidity behavior, precision and math, ERC-20 behavior,
Uniswap v4 and AMM integration, Diamond storage and upgrades, access control,
assembly and low-level operations, and denial of service. Reviewers reran
focused real-flow suites and the 1,000-run Treasury schedule conservation
property. No GitHub issues were created.

One Low-severity availability defect was verified: runtime configuration,
deployment validation, and deployment verification accepted
`tickUpper == TickMath.MAX_TICK`, although the corresponding
`MAX_SQRT_PRICE` is an exclusive PoolManager initialization bound. Commit
`05aa73d` rejects that unusable terminal tick across all three validation
surfaces and adds runtime and deterministic-deployment regressions. The
remediated stack passed 26 canonical-market tests, 13 deployment tests, six
Treasury-reward lifecycle tests, and 1,000 Treasury schedule fuzz runs.

No unresolved Critical, High, Medium, or Low finding remains in the reviewed
scope. The audit assumes a fresh deployment, the pinned Uniswap v4 and Solady
dependencies, and the documented governance trust model. It is not a fork,
testnet, live-network, remote-CI, or independent third-party audit.

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

## Diminishing round timer candidate

Date: August 18, 2026

Source candidate: `fc9d01d` on `feat/diminishing-round-timer`, based on merged
`main` commit `4d9b7e6`. Production behavior and public documentation were
audited at `ed0b385`; the only later delta strengthens the timer fuzz oracle.

The first successful purchase in every round receives the snapshotted initial
timeout. Each later successful purchase reduces its reset by the snapshotted
decay until the minimum is reached. Local defaults produce 60, 55, 50, through
5-minute resets, with the twelfth and every later purchase remaining at five
minutes. Each deadline is anchored to its own purchase timestamp. Atomic,
self, and contract purchases count toward urgency while holder-time emission
continues to depend only on measurable elapsed time.

The authority can govern initial timeout, decay, and floor for future
unsnapshotted rounds. Zero decay or a floor equal to the initial timeout
restores fixed resets. Runtime, deployment, environment, and verifier surfaces
share the same nonzero/bounds domain.

Qualification selected every owned test category explicitly and did not use
`forge clean`, a forced build, a fork, or a deployed network:

| Scope | Command | Result |
| --- | --- | --- |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 39 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 51 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' --fuzz-runs 1000 -j 1` | 8 properties, 8,001 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 10 properties, 128,000 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 15 passed |

Focused timer flows prove the exact default sequence, timestamp anchoring,
same-timestamp zero-emission cycling, reverted-purchase rollback, self and
contract participation, non-even floor clamping, zero-decay and equal-floor
fixed resets, and new-round restart. Fuzzing independently calculates the exact
duration throughout the accepted `uint64` domain. The stateful protocol suite
retains ETH, POTATO supply, Recovery, buyback reserve, access-control, emission,
and exact dynamic-deadline invariants.

The committed candidate received checklist-driven reviews for general Solidity
and DoS behavior, precision/math, Diamond storage and selectors, deployment,
and access control. No verified Critical, High, Medium, Low, or Informational
finding remained, and no GitHub issue was opened. The test-only post-audit delta
was rechecked against the precision scope.

The review assumes a fresh deployment. Expanding embedded configuration structs
and changing the tuple-based configuration selector is not an in-place upgrade
or migration path for a pre-change deployed Diamond. This is local Foundry and
internal changed-scope audit evidence; it is not fork, testnet, live-network,
remote-CI, or independent third-party proof.

## Robinhood mainnet fork qualification

Date: August 26, 2026

Candidate before operational documentation: `a42ce1f8ae103952f3bfce76a7ecedf4ddd1c1b8`.
The committed trust root pins chain 4663 block `45234855` with hash
`0xd65b81057261cc49ef60573d9f500ec9563257d673e10f1ff8d3d7c6ce33670d`.
Official Uniswap deployment documentation identified the eight v4 contracts;
Robinhood documentation identified canonical WETH. The pinned fork validated
all nine runtime hashes and every exposed manager/Permit2/descriptor/WETH
binding.

| Scope | Command or method | Result |
| --- | --- | --- |
| Optional gate | `env -u ROBINHOOD_MAINNET -u REQUIRE_ROBINHOOD_FORK forge test --match-path test/fork/RobinhoodBurntatoFork.t.sol -j 1 -vv` | One setup skip, successful exit |
| Strict missing-RPC gate | `env -u ROBINHOOD_MAINNET REQUIRE_ROBINHOOD_FORK=true forge test --match-path test/fork/RobinhoodBurntatoFork.t.sol -j 1 -vv` | Failed with `Robinhood fork required` |
| Strict pinned fork | `ROBINHOOD_FORK_BLOCK=45234855 REQUIRE_ROBINHOOD_FORK=true forge test --match-path test/fork/RobinhoodBurntatoFork.t.sol -j 1 -vv` with the private archive RPC | 2 passed |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 39 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 52 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' --fuzz-runs 1000 -j 1` | 8 properties, 8,000 runs |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 10 properties, 128,000 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` with the private archive RPC | 18 passed |
| Persistent fork | `scripts/start-robinhood-fork.sh`, guarded `DeployBurntatoLocalFork`, and `VerifyBurntatoLocalFork` | Broadcast succeeded; verifier returned true |
| Frontend artifact | `jq -e '.chainId == 4663 and .forkBlock == 45234855 and (.diamond | length == 42) and (.hook | length == 42)' artifacts/robinhood-local/deployment.json` | `true` |
| EIP-1153 boundary | Hook-impersonated authorization transaction followed by a separate `transientPoolManagerAllowance()` call | Returned `0` |

The fork lifecycle deployed a fresh Burntato without mutating canonical
infrastructure; verified Diamond selectors, governance, hook permissions and
ownership; exercised diminishing game rounds, unequal Recovery commitments and
exact remainder payout in both orders, Treasury reward scheduling/cancellation,
single-sided PositionManager launch, closed-gate buyback, a canonical
Permit2-backed sell, timelock buy enablement, a Universal Router buy, and a
second signed sell. Quoter-derived nonzero minimums, direct bilateral Treasury
fees, router-indexed hook events, consumed Permit2 allowances, and zero POTATO
transient allowance were observed.

This is reproducible pinned-fork and local-Anvil evidence, not a Robinhood
public-network deployment. Archive-RPC qualification remains an explicitly
executed local release gate and is intentionally excluded from CI. Pull-request
CI runs only the secret-free local categories.

The committed candidate `df43213` received parallel checklist review across

Recovery precision, general deployment safety, Diamond/proxy storage, AMM and
router integration, Permit2 signatures/ERC-20 restrictions, Robinhood
chain/assembly assumptions, governance/access control, and operational DoS.
Confirmed release-scope findings were remediated before final qualification:

- canonical dependency structs are now byte-for-byte bound to the committed
  manifest before code/binding validation;
- the broadcast entrypoint requires the exact pinned block, while the
  post-broadcast verifier separately proves the pinned block hash through Anvil
  RPC after deployment transactions advance the node;
- artifact persistence creates its narrowly permitted parent directory;
- verification reloads the same documented `BURNTATO_*` overrides as deploy;
- local deployment tests skip RPC-dependent cases so the local CI job remains
  self-contained;
- the fork suite asserts live liquidity, exact buyback event accounting, sell
  input/fee/price direction, router-indexed `Trade` events, and residual state;
- Permit2 sells use the Router allow-revert permit command so a copied permit
  submitted first does not block the subsequent exact-allowance swap; and
- pull-request CI runs only secret-free local categories and never receives the
  archive RPC.

The existing permissionless buyback's lack of quote/TWAP/minimum output remains
an explicitly accepted FWA-compatible product boundary already documented
above. Mutable GitHub Action major tags remain the repository-standard workflow
choice; read-only repository permissions limit their access, but this is not
equivalent to full-SHA action pinning.
