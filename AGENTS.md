# AGENTS.md

## Project Identity and Boundaries

This repository is **Burntato**, a fully onchain Hot Potato game with
holder-time POTATO emissions, a forward Recovery Market, and a canonical
Uniswap v4 POTATO/ETH market.

- Use **Burntato**, **POTATO**, **Hot Potato**, and **Recovery Market** in
  contracts, interfaces, events, documentation, deployment artifacts, SDKs,
  and commit messages.
- Statics in `../../statics/statics-stack` and FWA.fun are behavioral reference
  material only. Do not use either project as the new protocol name.
- Do not modify Statics or FWA.fun as part of Burntato work unless the user
  explicitly expands the scope.
- Preserve the single-address integration model: gameplay, POTATO accounting,
  Recovery, Treasury accounting, claims, governance, and views live behind the
  upgradeable `BurntatoDiamond`.

## Local Specifications

The local `specs/` directory is intentionally gitignored and must not be
staged, committed, or published unless the user explicitly changes that
instruction.

When `specs/` is present locally, read `requirements.md`, `design.md`, and the
relevant PR slice in `tasks.md` before changing protocol behavior, and keep the
local specifications synchronized with authorized behavioral changes.

## Naming Constraint

Do not use `Task`, `Task (n)`, `Task 1`, or similar task-number language in
file names, function names, test names, or commit messages.

## Solidity Guidance

Select and load the relevant Solidity skill available in the environment before
writing or changing Solidity, then apply it to the change.

## Compiling and Testing

- Do not run `forge build --force`, `forge build --contracts`, or `forge clean`.
- Prefer focused verification with
  `forge test --match-path path/to/test/File.t.sol`.
- All code changes must include tests proving the behavior.

### Test Fidelity Guardrails

Keep the test pyramid balanced:

- Use unit harness tests for narrow branches, storage checks, and otherwise
  unreachable state-machine edges.
- Use live integration or launch-level tests for every value-moving lifecycle.
- Use invariant and fuzz suites to broaden state-machine coverage, not to
  replace live-flow proofs.
- Prefer real purchases, holder-time advancement, emission finalization,
  Recovery commitments, settlements, claims, Treasury accrual, pool launches,
  swaps, self-burns, and governance calls.

If a synthetic shortcut is necessary, keep it narrow and document the concrete
reason in the test. Appropriate reasons include:

- storage or library smoke coverage
- unreachable failure branches requiring deliberately corrupted accounting
- state transitions that are impractical to reach economically during setup

Synthetic harness coverage does not count as end-to-end confidence. Every
value-moving behavior must also have at least one real-flow or launch-level
regression.

## Commit Discipline

- Commit implementation in narrow, reviewable slices.
- Stage only files belonging to the current slice; preserve unrelated dirty or
  untracked work.
- Use Conventional Commits with a title of at most 72 characters.
- Do not mention tasks, task numbers, or marking tasks complete.
- Use present-tense bullet points in the body explaining what changed and why.

Format commit messages as:

```text
feat(scope): short summary

- Key change detail
- Another change
- Rationale or context
```

When handing work back in chat, include the proposed or used commit message in
a fenced text block using the same format.

## Compiler-Resilience Rule for Test Harnesses

When editing or adding external/public helper functions in large test harnesses,
especially harnesses inheriting many facets, prefer:

- `uint256` for external/public numeric parameters
- explicit bounds checks before narrowing
- internal casts to `uint16`, `uint8`, or other narrow types at assignment
  boundaries

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
