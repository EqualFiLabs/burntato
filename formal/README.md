# Burntato formal verification

This directory separates solver-backed properties from Foundry and live-chain
qualification. A green solver result applies only to the stated harness,
assumptions, compiler inputs, and tool version; it is not a protocol-wide proof
or a substitute for review.

## Solver-backed scope

The Halmos properties execute production `LibMath`, the production Diamond,
`FoundationInit`, `GovernanceFacet`, and `GameFacet`. They establish:

- diminishing-timeout bounds and its fixed-reset branches;
- rejection of every pre-activation `buyPotato()` payment;
- configured-foundation visibility and current-authority-only, one-shot
  purchase activation; and
- a successful first purchase after activation without gating read surfaces.

The Halmos suite also executes the production Diamond and `BuybackFacet` to
establish that any caller's positive direct funding increases both the tracked
reserve and Diamond balance exactly, repeated funding is additive, zero-value
funding reverts without mutation, and a raw native transfer does not enter
reserve accounting.

The Certora harnesses are thin wrappers over production `LibMath`,
`GovernanceFacet`, and `BuybackFacet`. CVL independently checks the arithmetic
properties and the activation transition, including foundation initialization,
unauthorized callers, repeat calls, and authority transfer before activation.
The buyback funding harness checks exact reserve addition for arbitrary callers,
zero-value rollback, cooldown isolation, and enforcement of the shared
reentrancy guard.

The activation and buyback funding harnesses have clearly marked
state-construction methods. They are verification-only and are never part of a
deployment. Every transition under test is executed by its production facet.

## Deliberate boundaries

The following properties are not modeled as universal solver proofs here:

- Uniswap v4 PoolManager, PositionManager, Permit2, and Universal Router
  behavior;
- canonical Robinhood addresses, runtime bytecode, or live ownership;
- external receiver behavior, forced ETH, and transaction ordering across
  unrelated contracts;
- the complete Diamond selector graph and all multi-round state-machine paths;
  and
- gas availability, liveness, governance key safety, or economic desirability.

Those surfaces remain covered by Foundry unit, fuzz, invariant, integration,
deployment-mutation, and block-pinned fork tests. A timeout, unknown, vacuity
warning, skipped rule, or optimistic approximation is not a pass.

## Halmos

The repository profile compiles symbolic tests into an isolated output
directory:

```bash
FOUNDRY_PROFILE=formal forge test --match-path 'formal/halmos/*.t.sol' -vv
formal/scripts/run-halmos.sh
```

The first command is a compilation check; Foundry does not execute `check_`
functions. The second command is the proof run. The checked command uses
pessimistic assertion handling and bounded solver timeouts. The Halmos suite is
intentionally limited to rules that close without timeout; full conservation,
rounding, and monotonicity arithmetic is assigned to Certora. Review every
rule's status and statistics.

## Certora

Install `solc8.26`, configure Certora according to its official CLI
documentation, and run:

```bash
formal/scripts/run-certora.sh all
```

Both configurations enable rule-sanity checks and wait for final cloud results.
Never describe a submitted or still-running job as verified.

## Reproducibility

The arithmetic harness bounds monetary values to `uint128`, BPS inputs to
`uint16`, and timing/count inputs to `uint64`. Activation and Halmos buyback
funding use `uint96` payment inputs. Certora bounds both the starting reserve
and positive contribution below `2^128`. These bounds are explicit proof
assumptions, not Solidity type changes.

The intended toolchain is Solidity 0.8.26 with the repository's production
optimizer, `via_ir`, Cancun EVM, and metadata-free bytecode settings; Foundry
1.7.1; Halmos 0.3.3; Java 21; and Certora CLI 8.18. Tool upgrades or production
source changes require a fresh run.
