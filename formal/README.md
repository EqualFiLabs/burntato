# Burntato formal verification

Formal results apply only to the exact committed candidate, compiler inputs, harnesses, assumptions and prover versions recorded with their artifacts. Foundry, fork execution, CI and independent agent review are separate evidence categories.

Run Halmos and Certora only on the dedicated remote verification host, following the operator's private execution runbook. Never invoke or probe either prover on the local development host. Use durable candidate-specific storage, verify the exact candidate commit and submodules, and preserve jobs through disconnects. Capture compiler settings, runtime bytecode hashes, tool versions, all terminal per-rule results, assumptions and bounds. Timeouts, unknown, infrastructure failures and vacuous rules are not passes.

## Harness scope

Halmos executes production libraries, Diamond, initialization and facets. Suites cover arithmetic, activation, direct buyback funding, pause authorization/containment, Diamond authority/finalization/selector removal, wrapper backing/capacity/redemption, buyback settlement/atomic failure, and claims/snapshot/schedule transitions.

The wrapper suite uses a concrete 18-decimal test underlying with unrestricted fixture minting. Every POTATO issuance under test uses actual backing transfer through the production wrapper. Symbolic wrap amounts are positive and at most the public cap where success is asserted; rejection rules cover larger uint96 amounts. Reserve funding accepts positive uint96 quantities independent of the public cap. Token reentrancy/tax behavior is separately covered by Foundry.

The buyback suite uses a modeled PoolManager for full, partial, zero-output, revert and malformed-return outcomes. Production unlock callback, real test WETH deposit/transfer, received backing measurement, reserve credit, tip and cooldown accounting execute unsummarized. Reserve and cap inputs are uint96, tip is at most 100 BPS, and the modeled positive output is one base unit. This proves conservation and rollback under these market assumptions. Real v4 pools in both currency orders and the pinned real mainnet market provide separate execution evidence.

Lifecycle properties use a verification-only facet for snapshots and deadlines. Claim checks execute real purchases, commitments and settlement before claiming and checking replay state. Backed allocation fixtures use real public wrapping, bounded by capacity. These fixed lifecycle checks and their concrete Foundry witnesses are not universal proofs of all sequences. The formal deadline setter models time because Halmos 0.3.3 does not implement Foundry time-warp. Read-only `getRound(1..3)` calls prime runtime Keccak preimages during setup: Halmos 0.3.3 otherwise changes storage-key normalization when a compiler-folded mapping location is later hashed at runtime. This introduces no state mutation or input assumption. Original failed diagnostics are retained with the remote evidence; only the corrected committed harness results count as proof evidence.

Certora independently checks production arithmetic, purchase activation, direct ETH reserve funding and pause authorization. Its pause harness constructs an idle reentrancy guard (status 1) before public-entry checks, and distinguishes the exact public-wrap pause error and a deliberately reverting modeled PoolManager boundary. It does not claim an unpaused successful buyback or external-token model; those execute in the Halmos suite and integration tests. No unbacked mint or configurable Recovery-split rule remains.

External dependencies and governance remain trusted according to the approved design. Public-cap reopening is deliberately independent of token provenance. Buybacks require full input and positive output without an oracle/minimum-price policy. Proofs do not establish market prices or future external-contract governance.

## Remote execution

After loading the remote shell environment, verify Foundry, Solidity 0.8.26, Halmos 0.3.3, Certora 8.18.0 and Java versions against the current execution runbook. Both compilers target Cancun without via IR and with optimizer 200. Foundry retains the standard IPFS metadata bytecode hash; Certora uses its compiler metadata defaults and instrumented harness bytecode. Record their bytecode hashes separately rather than claiming identical prover and deployment bytecode. Results obtained with the previous IR configuration do not qualify this compiler configuration and must be rerun. Keep candidate-specific logs/results and the source bundle in recoverable project storage.

Typical commands, executed on the dedicated remote verification host only:

```bash
FOUNDRY_PROFILE=formal forge build -j 2
FOUNDRY_PROFILE=formal halmos --contract BurntatoTokenAuthorizationProperties
certoraRun formal/certora/conf/math.conf
```

Select the required suites and durable result paths explicitly. Load the raw remote Certora credential as data into `CERTORAKEY`; never source, print or commit it. Retain each cloud job's terminal rule and sanity status rather than treating submission or client exit as proof completion. Current candidate evidence is recorded in `docs/RELEASE_EVIDENCE.md` only after execution is verified.
