# Release qualification evidence

## STATICS-backed wrapper candidate (issue #59)

Date: October 21, 2026

Implementation branch: `feat/statics-backed-wrapper`, based on
`28fb8336ca0186a493ac6b095bb9bca0198b79e1`. The qualified source candidate is
`acf8d3dd50a1fd96ec15b8480dc1379921d1c2fe`. The final documentation-only amendment
records qualification results without changing source, dependencies, compiler
settings or proof inputs.

The subsequent local maintenance changes are not covered by that qualification.
This includes the subsequent launch defaults: a zero public wrap cap,
0.003 ETH starting price, and 20,000 POTATO budget with a 5% reward step.
Their focused tests and review are separate; remote formal proofs and complete
CI must be renewed against the changed source before treating it as qualified.

The qualified source candidate starts with zero supply and purchases inactive.
Public wrapping deposits STATICS 1:1 under a 2,000,000 POTATO capacity; permissionless backed reserve
contributions do not consume that capacity. Base rewards transfer from the one
accounted Diamond reserve, with the full snapshotted budget required at the
first Grab. Settlement redeems all Recovery commitments into equal STATICS for
the current Treasury and does not require the next round to be funded. Atomic
buybacks acquire STATICS through the existing WETH pool and wrap it into the
reserve. The later-Grab allocation is 25/5/30/15/10/15.

The restoration retains those protocol decisions, restores local-fork economic
overrides and deployment safeguards, and compiles without via IR. Public-network
profiles retain fixed deployment economics and existing onchain administration.

### Local compilation and focused checks

Foundry: 1.8.2-nightly (`bdd1162b2c24814d2424ffad4f8c587827f1a6ab`).
Compiler: Solidity 0.8.26, Cancun, optimizer 200, `via_ir = false`, IPFS metadata
bytecode hash. The default build and formal Foundry harness build compile with
these settings. Compiling formal harnesses is not a proof run.

| Scope | Result |
| --- | --- |
| Deployment, local configuration, standalone lifecycle and testnet handoff | 21 focused tests passed |
| Local economic configuration | All 18 overrides exercised serially in one environment-isolated test; public defaults, narrowing, split, timeout and tip boundaries checked |
| Buyback bootstrap/resume helpers | 8 tests passed, including exact existing funding, reserve conflicts and inactive-purchase requirements |
| Buyback unit and real-pool integration | 27 tests passed, including event amounts, full-input execution, backing/reserve credit and rollback across both currency orders |
| Deployment shell workflows | 31 isolated tests passed; stubs replace RPC/signing tools while actual wrapper dispatch, files, JSON, guards and receipt checks execute |
| Standalone Anvil deployment | Actual local broadcast and fresh source/runtime verification passed on chain 31337 |

The standalone lifecycle test uses real local WETH and PoolManager settlement,
credits backed reserve POTATO, tops up the reserve and starts gameplay. It is a
fixture-market test, not evidence about the external STATICS market.

Logs and disposable public artifacts remain in ignored `artifacts/` storage.
No private RPC or signing material is included in this document or the commit.

### Pinned mainnet-fork deployment

The local-fork smoke starts Anvil from Robinhood Mainnet block **47,690,599**,
hash `0x4ca3ce6b00d4603804be596b721c738caf54c2a08515f84a8ca020f33613837b`.
It deploys with a 0.02 ETH starting price and 1,000 POTATO reward budget, checks
the derived 0.021 ETH initial Winner reserve, and verifies the recorded economic
fields, exact source runtimes and pinned market/Operator dependencies.
Zero-second interval mining retains automining for submitted transactions.

Both strict pinned tests in `test/fork/BackedStaticsFork.t.sol` passed on the
qualified source candidate, with zero skips. They exercise fresh initialization
against real dependencies and source-verified Operator routing, then real-market
buyback-funded rewards, public redemption, Recovery-to-Treasury and ETH claims.
This is fork execution; no live transaction was sent.

### Remote formal verification and CI

All remote proof suites passed on the qualified source candidate:

| Prover | Scope | Terminal result |
| --- | --- | --- |
| Halmos 0.3.3 | Arithmetic, activation, funding, buyback execution, pause, Diamond, wrapper and lifecycle | 45 properties passed; 0 failed |
| Certora CLI 8.18.0 | Arithmetic | 12 rules passed |
| Certora CLI 8.18.0 | Activation | 5 rules passed |
| Certora CLI 8.18.0 | Direct buyback funding | 3 rules passed |
| Certora CLI 8.18.0 | Pause and authority | 11 rules passed |

All 31 Certora rules include non-vacuity witnesses. Halmos uses 5-second branch
and 120-second assertion solver timeouts, two solver threads and default loop
unrolling of two. Remote tools were Foundry 1.7.1, Solidity
0.8.26+commit.8a97fa7a and Java 21.0.12.1; both prover builds disable via IR and
use optimizer 200/Cancun. Foundry retains IPFS metadata hashing.

The durable evidence includes the source bundle, verified recursive dependency
commits, compiler inputs, per-rule terminal results, logs, and separate production
and Certora instrumented bytecode hashes. All 13 production runtimes have
identical executable bytes, source hashes and compiler settings between local
and remote builds. Full runtime hashes differ because the two Foundry versions
serialize import remappings differently in IPFS metadata; both hashes and the
metadata comparison are retained. These are not claimed to be byte-for-byte
identical deployment artifacts. Certora's instrumented harness hashes are also
recorded separately.

Certora job results: [math](https://prover.certora.com/output/8471858/005761270bfc4304a7252f79aff43fb7), [activation](https://prover.certora.com/output/8471858/591728b6acb54efea470f8cfc0bec6c7), [buyback-funding](https://prover.certora.com/output/8471858/bf453e76a59a437ab5babe035fbd2814), [pause](https://prover.certora.com/output/8471858/28c3039176da4b27b3521eab62b0d1ae).

Assumptions and bounds remain in `formal/README.md`, the Solidity harnesses and
CVL rules: bounded wrapper inputs and concrete backing, modeled buyback outcomes,
small concrete lifecycle fixtures, explicit storage-normalization assumptions,
and idle-guard assumptions for pause checks. These are scoped properties, not a
universal proof of the external market or every possible sequence.

The complete unit, integration, fuzz, invariant, deployment and shell categories
belong to CI. Their final-head results are reported by the
[PR checks](https://github.com/EqualFiLabs/burntato/pull/60/checks); local execution
and formal proofs are separate from those results.

### Review and remaining evidence boundaries

Independent local agent review identified missing key-address verification,
overwrite guards, direct-activation readiness checks and first-round funding
qualification. Those findings were corrected and regression checks passed.
The actual fork smoke also caught zero-interval mining disabling automining;
the entrypoint now explicitly restores automining for that setting.

Independent reviews of the committed source candidate covered protocol
accounting and deployment/configuration/documentation. No remaining confirmed
findings were reported. This is agent review, not third-party audit assurance. Review,
local tests, fork execution, remote formal results and CI are separate evidence.
No migration, app/indexer work or live deployment is included. Governance and
external dependency trust remain. Public-cap reopening intentionally does not
track token provenance; buybacks require complete input and positive output
without adding an oracle or minimum-price policy.
