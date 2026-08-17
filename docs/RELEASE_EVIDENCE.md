# PR 11 release qualification evidence

Date: August 17, 2026

Pre-audit source candidate: `ca4e61e` on `fix/11-configurable-protocol`, stacked
on PR 10 commit `379ea5f`. Confirmed audit findings were remediated in
`fbb49b1`.

Environment: Foundry 1.5.1-stable, Solidity 0.8.26, Cancun EVM, local Linux
host. No fork, testnet, remote CI, or production network was used.

## Candidate behavior

This candidate replaces terminal/frozen governance with retained
administration, snapshots complete governed economics at round boundaries,
uses Solady's FWA-style restricted ERC-20 pattern, sends canonical market fees
directly to the hook's governed Treasury recipient, and leaves the hook and
PoolManager owned by the configured timelock. `finalizeProtocol()` disables
only future Diamond cuts.

The ignored local specification package was updated but is intentionally not a
versioned PR artifact.

## Tests

Qualification selected every owned test path explicitly and used the repository
profiles: 1,000 fuzz runs and 256 invariant runs at depth 50.

| Scope | Command | Result |
| --- | --- | --- |
| Unit | `forge test --match-path 'test/unit/*.t.sol' -j 1` | 25 passed |
| Integration | `forge test --match-path 'test/integration/*.t.sol' -j 1` | 32 passed |
| Fuzz | `forge test --match-path 'test/fuzz/*.t.sol' -j 1` | 5 properties, 5,000 cases |
| Invariant | `forge test --match-path 'test/invariant/*.t.sol' -j 1` | 8 properties, 102,400 calls |
| Deployment | `forge test --match-path 'test/deployment/*.t.sol' -j 1` | 12 passed |

In aggregate, 69 deterministic tests, five fuzz properties, and eight stateful
invariants passed with no failures or skips. The executed flows include:

- default and nondefault round economics, zero-budget activation, full and
  partial holder-time emission, same-timestamp cycling, geometric dust, and no
  double minting;
- forward Recovery commitment, configurable consumption, rollovers, settlement,
  claims, and exact ETH/POTATO conservation;
- Solady Permit, transfer rejection, voluntary self-burn, exact protocol
  movements, and transient canonical PoolManager authorization;
- real v4 launch, locked initial LP, buy and sell swaps, direct bilateral fee
  delivery, 0% and 100% fee edges, fee rotation after Diamond finalization,
  foreign-key rejection, and no Diamond hook revenue accounting;
- repeated and zero authority transfer, guardian pause-only behavior, authority
  unpause, configuration after finalization, and permanent Diamond-cut closure;
  and
- zero-delay and overlapping-proposer deployment, full genesis verification,
  timelock-owned hook/PoolManager, and a real PoolManager administration call.

## Formatting, linting, selectors, and storage

- `forge fmt --check` passed.
- `git diff --check` passed.
- `forge lint src script test --severity high med low -j 1` compiled and exited
  successfully. It reports visible bounded-cast warnings and unchecked-return
  warnings in negative-path tests; these remain audit inputs rather than being
  hidden by global suppressions.
- `BurntatoSelectors` installs nine facets and 59 selectors. The deterministic
  verifier checks exact facet group sizes and selector-to-facet routing.
- `forge inspect <facet> storage-layout --json` reported zero ordinary storage
  entries for all nine Diamond facets. Protocol state uses explicit namespaced
  storage.
- The standalone hook has three intended packed slot-zero fields:
  `feeAddress`, `feeBps`, and `deploymentBlock`. Its owner uses Solady's
  namespaced ownership slot; token, PoolManager, and tick spacing are immutable.

## Dependency and security boundaries

Pinned revisions include:

- Solady `166f85b9576f311446b0f9b3082565bbe0c17af5`;
- Uniswap v4 core `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc`;
- Uniswap v4 periphery `60cd93803ac2b7fa65fd6cd351fd5fd4cc8c9db5`;
  and
- FWA.fun precedent `1085bf6ee255d6d4d13c374a66110bb25229dc76`.

The token restriction governs underlying POTATO ERC-20 movement. Standard v4
ERC-6909 currency claims and third-party wrappers are derivative assets and do
not invoke POTATO's transfer hook. This candidate documents that boundary; it
does not claim universal venue exclusivity for derivative exposure.

Retained authority, hook ownership, and PoolManager ownership are intentional
governance powers. Their safety depends on the configured timelock roles and
delay. The protocol itself permits a zero delay and permits explicit ownership
or authority relinquishment.

## Audit and remediation

The committed `ca4e61e` candidate received the full repository audit workflow
across the general, precision/math, ERC-20, AMM, proxy/Diamond, governance,
assembly, and access-control checklists. The review confirmed no Critical,
High, or Medium findings. Four Low findings were confirmed and remediated in
`fbb49b1`:

- public zero-address transfers could credit the zero-address balance without
  reducing Solady ERC-20 supply; public transfers now reject zero endpoints and
  `burn(amount)` remains the explicit destruction path;
- an unbounded snapshotted round timeout could overflow deadline addition and
  deadlock that round; configuration, deployment, and verification now enforce
  the `uint64` deadline domain;
- hook fee revenue could be directed to protocol system sinks; zero, the hook,
  POTATO Diamond, and PoolManager are now invalid fee recipients; and
- the permissionless CREATE2 hook helper exposed the mined salt to public
  deployment griefing; only the helper creator may execute deployment.

The remediation also widens signed v4 deltas before negation and returns through
the free-memory pointer in the Diamond fallback. Applicable regression tests
and the complete qualification matrix above passed after remediation.

A final Aderyn pass analyzed 24 source files, 1,140 non-comment source lines,
and 63 detectors. Its reported candidates were manually classified as intended
Solady/BaseHook overrides, one-shot initialization, terminal Diamond fallback,
permissionless fixed-recipient claims, delegatecall/native-value behavior,
explicit retained administration, or style/static-analysis observations. No
additional confirmed finding resulted.

Accepted informational boundaries are sub-wei pro-rata Recovery floor residue,
per-swap fee-floor nonadditivity below one base unit per swap, OpenZeppelin
timelock operations having no built-in expiry, verification proving required
state rather than exclusive role membership or runtime identity, and the
documented ERC-6909/wrapper derivative boundary.

## Proof boundary

This evidence proves local compilation, repository-owned test execution,
checklist-driven internal review, and static-analysis classification against the
stated commits. It does not prove deployed-chain state, production genesis
parameters, canonical chain dependency addresses, fork compatibility, remote
CI, or an independent third-party audit.
