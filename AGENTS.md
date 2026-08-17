# AGENTS.md

## Project Identity and Boundaries

This repository is **Burntato**, a fully onchain Hot Potato game with
holder-time POTATO emissions, a forward Recovery Market, and a canonical
Uniswap v4 POTATO/ETH market.

- Use **Burntato**, **POTATO**, **Hot Potato**, and **Recovery Market**
  consistently in contracts, interfaces, events, tests, documentation,
  deployment artifacts, and commit messages.
- Preserve the single-address integration model. Gameplay, POTATO accounting,
  Recovery, Treasury accounting, claims, governance, and views live behind the
  upgradeable `BurntatoDiamond`.
- The Uniswap v4 hook is a separate contract bound to the Burntato Diamond and
  the exact canonical PoolKey. It is not an independent administrative or
  custody domain.
- Statics in `../../statics/statics-stack` and FWA.fun are reference
  implementations only. Do not modify either repository as part of Burntato
  work unless the user explicitly expands the scope.
- Reuse proven FWA.fun mechanics from TokenWorks `fwa-relaunch` commit
  `1085bf6ee255d6d4d13c374a66110bb25229dc76` where the Burntato design cites
  them, but do not import FWA's mutable authority or fee-recipient model.
- Preserve unrelated local, ignored, modified, and untracked files.

## Local Specifications

The local `specs/` directory is intentionally gitignored and must not be
staged, committed, or published unless the user explicitly changes that
instruction.

When `specs/` is present locally:

- read `requirements.md`, `design.md`, and the relevant PR slice in `tasks.md`
  before changing protocol behavior;
- treat the requirements and design as the normative mechanism description;
- keep local specifications synchronized with authorized behavioral changes;
- do not invent unresolved genesis values such as the initial POTATO price,
  seed amounts, tick range, or tick spacing; and
- prefer live contracts, interfaces, tests, and deployment artifacts over
  stale planning language once implementation exists.

## Non-Negotiable Protocol Boundaries

Unless the user explicitly changes the specification, preserve these rules:

- A round lasts one hour and Hot Potato purchases split ETH 25% Winner, 50%
  Recovery, and 25% Treasury.
- Each round starts with a fresh 100,000 POTATO emission budget. Emission
  advances through finalized holder time, not purchase count.
- A holder's snapshotted opportunity vests linearly for at most 120 seconds;
  only earned POTATO reduces the remaining round budget.
- Recovery commitments are forward-only and close before the target round
  begins. Settlement burns 90% of committed POTATO and credits 10% to
  Treasury, with the exact remainder assigned according to the specification.
- Zero-commitment Recovery value rolls forward; unused round emission does not.
- Ordinary wallet-to-wallet POTATO transfers revert. Protocol movement and
  canonical PoolManager settlement require exact transaction-scoped
  authorization. Voluntary self-burning remains permitted.
- The canonical pool launches only from unencumbered Treasury ETH and POTATO,
  its initial LP is permanently locked, and its native LP fee is zero.
- The canonical hook charges a 1% bilateral fee. Buy-side POTATO fees are
  converted to ETH, sell-side fees are taken in ETH, and all realized fee ETH
  belongs to Treasury. Fees are not auto-compounded.
- Participation, purchases, settlement, and eligible materialization remain
  permissionless. Do not add EOA restrictions, cooldowns, per-block purchase
  limits, minimum emissions, commit-reveal purchasing, or privileged anti-MEV
  machinery.
- All privileged protocol mutation flows through the timelock. Guardian
  authority remains narrowly limited, and progressive immutability must never
  be reversible.

## Naming Constraint

Outside the planning documents, do not use `Task`, `Task (n)`, `Task 1`, or
similar task-number language in file names, contract or function names, test
names, or commit messages.

## Solidity Guidance

- Before writing or changing Solidity, load the applicable Solidity security,
  testing, Diamond, and Uniswap v4 guidance available in the environment.
- Use collision-resistant namespaced storage for every Diamond domain. Facets
  must not introduce ordinary state variables that can collide under
  `delegatecall`.
- Treat selectors, initialization ordering, transient storage namespaces,
  exact asset accounting, and external-call ordering as security boundaries.
- Prefer Solady only after tests prove its ERC-20 storage and hook behavior are
  safe behind the Diamond's `delegatecall` model. Otherwise implement the
  specified equivalent behavior directly.
- Use multiplication before division and explicitly test base-unit rounding.
- Do not expose administrative minting, arbitrary third-party burning,
  reusable transfer bypasses, mutable fee destinations, or recoverable locked
  liquidity.

## Compiling and Testing

- Do not run `forge build --force`, `forge build --contracts`, or `forge clean`.
- Prefer focused verification with
  `forge test --match-path path/to/test/File.t.sol` while implementing.
- Every code change must include tests proving the behavior or regression.
- Run the applicable predecessor regression suites for the current PR slice.
- Before release qualification, run the complete unit, integration, fuzz, and
  stateful invariant suites plus formatting, linting, and static analysis.
- Record exact commands, environment, results, seeds or run counts where
  applicable, and proof limits. Do not describe an unexecuted fork, testnet, or
  live path as verified.

### Test Fidelity Guardrails

Keep the test pyramid balanced:

- Use unit harness tests for narrow branches, storage checks, and otherwise
  unreachable state-machine edges.
- Use real integration or launch-level tests for every value-moving lifecycle.
- Use invariant and fuzz suites to broaden state-machine coverage, not to
  replace real-flow proofs.
- Prefer real purchases, holder-time advancement, emission finalization,
  Recovery commitments, settlements, claims, Treasury accrual, pool launch,
  swaps, self-burns, governance calls, freezes, and finalization.
- Exercise zero-time cycling, rounding dust, malicious recipients, reentrancy,
  repeat initialization, invalid PoolKeys, direct PoolManager movement,
  alternative-venue attempts, and forced ETH transfers.

If a synthetic shortcut is necessary, keep it narrow and document the concrete
reason in the test. Appropriate reasons include:

- storage or library smoke coverage;
- unreachable failure branches requiring deliberately corrupted accounting;
  and
- state transitions that are impractical to reach economically during setup.

Synthetic harness coverage does not count as end-to-end confidence. Every
value-moving behavior must also have at least one real-flow or launch-level
regression.

## Commit Discipline

- Implement and commit in the PR slices defined in local `specs/tasks.md` when
  that file is available.
- Commit implementation in narrow, reviewable slices.
- Stage only explicit files belonging to the current slice. Never use the
  ignored `specs/` directory as commit content.
- Use Conventional Commits with a title of at most 72 characters.
- Do not mention tasks, task numbers, or marking tasks complete.
- Use present-tense bullet points in the body explaining what changed and why.
- Do not push, open a PR, merge, or rewrite published history unless the user
  authorizes that external action.

Format commit messages as:

```text
feat(scope): short summary

- Key change detail
- Another change
- Rationale or context
```

When handing committed work back in chat, include the used commit message in a
fenced text block using the same format.

## Compiler-Resilience Rule for Test Harnesses

When editing or adding external/public helper functions in large test
harnesses, especially harnesses inheriting many facets, prefer:

- `uint256` for external/public numeric parameters;
- explicit bounds checks before narrowing; and
- internal casts to `uint16`, `uint8`, or other narrow types at assignment
  boundaries.

Example:

```solidity
function setStepBps(uint256 stepBps) external {
    if (stepBps > type(uint16).max) revert();
    config.emissionStepBps = uint16(stepBps);
}
```

Apply this proactively when broad harnesses or narrow ABI parameters cause
stack-depth or Yul compiler failures. Do not change production ABI widths when
compatibility matters; decompose the function or reduce local stack pressure
instead.
