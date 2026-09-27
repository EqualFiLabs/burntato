# Burntato formal verification

This directory separates solver-backed properties from Foundry and live-chain
qualification. A green solver result applies only to the stated harness,
assumptions, compiler inputs, and tool version; it is not a protocol-wide proof
or a substitute for review.

## Solver-backed scope

The Halmos properties execute production libraries, the production Diamond,
`FoundationInit`, and the production facets. They establish:

- diminishing-timeout bounds and its fixed-reset branches;
- rejection of every pre-activation `buyPotato()` payment;
- configured-foundation visibility and current-authority-only, one-shot
  purchase activation; and
- a successful first purchase after activation that routes its complete value
  to the next-round Winner reserve without gating read surfaces.

The Halmos suite also executes the production Diamond and `BuybackFacet` to
establish that any caller's positive direct funding increases both the tracked
reserve and Diamond balance exactly, repeated funding is additive, zero-value
funding reverts without mutation, and a raw native transfer does not enter
reserve accounting.

The pause properties execute the production Diamond and every protected facet.
They establish that the guardian can pause but cannot unpause, unauthorized
callers cannot pause, authority can clear the pause, and authority cannot be
renounced while a guardian remains. While paused, purchases, emission
materialization, Recovery commitments, settlement, all claim paths, central
protocol minting, and buyback execution revert with the exact shared pause
error and without changing protected accounting. Direct Winner, Recovery, and
buyback reserve funding remains available while paused.

The Diamond properties establish current-authority-only cuts, authority
succession, permanent rejection of add, replace, remove, and init-only cuts
after finalization, and atomic selector-graph rollback when an initializer
fails or the one-shot foundation initializer is repeated.

The token properties establish canonical-hook-only transient authorization,
exact PoolManager allowance consumption, overspend rollback, non-reuse after
consumption, single-use protocol movement authorization, and protocol-only
minting. The buyback execution properties establish exact reserve and caller
reward accounting after a successful summarized PoolManager execution and
atomic rollback for partial fill, zero output, external revert, or malformed
return data.

The lifecycle properties exercise concrete production state-machine witnesses
for one-shot Winner claims, a complete two-round Recovery commitment, burn,
treasury allocation, and claim, active-round configuration snapshots, and
Treasury reward allocation and cancellation conservation. These witnesses
prove those paths for the stated concrete setup. They are not universal
quantification over every multi-round sequence.

The Certora harnesses are thin wrappers over production `LibMath`,
`GovernanceFacet`, `PotatoTokenFacet`, and `BuybackFacet`. CVL independently
checks production-linked purchase allocation, buyback quoting, Recovery claim,
reward schedule, emission, timeout, and BPS arithmetic. It also checks the
purchase-activation transition, unauthorized callers, repeat calls, and
authority transfer before activation. The buyback funding harness checks exact
reserve addition for arbitrary callers, zero-value rollback, cooldown
isolation, and enforcement of the shared reentrancy guard. The pause harness
checks guardian and authority permissions, safe authority renunciation,
protocol mint containment, exact pause-error behavior for buybacks, a reachable
unpaused buyback manager boundary, and paused direct-funding availability.

The activation, pause, and buyback funding harnesses have clearly marked
state-construction methods. They are verification-only and are never part of a
deployment. Every transition under test is executed by its production facet.
The pause harness installs one selector directly to make the `onlyDiamond`
funding precondition reachable. That local construction does not prove the
complete selector graph; the actual-Diamond Halmos properties cover graph
authority, rollback, and finalization separately.

## Deliberate boundaries

The following properties are not modeled as universal solver proofs here:

- Uniswap v4 PoolManager, PositionManager, Permit2, and Universal Router
  behavior;
- canonical Robinhood addresses, runtime bytecode, or live ownership;
- external receiver behavior, forced ETH, and transaction ordering across
  unrelated contracts;
- every possible multi-round state-machine path;
- the operator rewards router's complete dynamic registration and ownership
  state space; and
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

The first command compiles every `check_` property and executes the concrete
lifecycle witness wrappers. The second command is the proof run. The checked command uses
pessimistic assertion handling and bounded solver timeouts. The Halmos suite is
intentionally limited to rules that close without timeout; full conservation,
rounding, and monotonicity arithmetic is assigned to Certora. Review every
rule's status and statistics.

## Certora

Install `solc8.26`, configure Certora according to its official CLI
documentation, and run:

```bash
formal/scripts/run-certora.sh pause
formal/scripts/run-certora.sh activation
formal/scripts/run-certora.sh all
```

Every configuration enables rule-sanity checks and waits for final cloud results.
Never describe a submitted or still-running job as verified.

## Reproducibility

The Certora arithmetic harness uses the production `uint256` domain. Activation
and several Halmos funding and execution properties use `uint96` inputs. The
Halmos pause-mint property keeps the mint amount symbolic within `uint96` and
uses one fixed nonzero recipient because Solady's hashed balance slot is not
concrete for a fully symbolic address in Halmos. The Certora funding properties
bound both starting reserve and positive contribution below `2^128` to make
addition non-overflowing. These bounds are explicit proof assumptions, not
Solidity type changes.

External PoolManager behavior in the buyback execution proof is summarized by
a deterministic manager boundary with success and failure modes. Uniswap v4
integration behavior remains a Foundry integration and pinned-fork claim, not a
solver claim. The launch-curve property uses production math in Foundry because
symbolically expanding all 56 positions and Uniswap square-root-price math is
not a useful solver model.

The intended toolchain is Solidity 0.8.26 with the repository's production
optimizer, `via_ir`, Cancun EVM, and metadata-free bytecode settings; Foundry
1.7.1; Halmos 0.3.3; Java 21; and Certora CLI 8.18. Tool upgrades or production
source changes require a fresh run.
