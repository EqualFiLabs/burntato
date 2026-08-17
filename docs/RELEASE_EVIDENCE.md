# Release qualification evidence

Date: August 17, 2026

Qualified code candidate: `6755c22` (`fix(market): enforce POTATO operation results`)

Environment: Foundry 1.5.1-stable, Solidity 0.8.26, Cancun EVM, local Linux host, Anvil chain ID 31337

This evidence qualifies the nine-PR implementation candidate before the requested independent full-system audit. The audit and any remediation are intentionally not represented here as complete.

## Test execution

Foundry's cache selected only currently active artifact roots for a plain `forge test`, so release qualification used explicit test paths. Non-v4 roots were compiled with `--no-cache`; v4 roots were rebuilt after source changes and then executed from the resulting focused artifacts. Every repository test file was selected and reported.

| Scope | Command | Result |
| --- | --- | --- |
| Diamond foundation | `forge test --no-cache --match-path test/unit/DiamondFoundation.t.sol -j 1 -vv` | 5 passed |
| Governance and immutability | `forge test --match-path test/unit/GovernanceImmutability.t.sol -j 1 -vv` | 5 passed |
| POTATO and game | `forge test --no-cache --match-path test/unit/PotatoGameLifecycle.t.sol -j 1 -vv` | 7 passed |
| Recovery settlement | `forge test --no-cache --match-path test/integration/RecoverySettlementLifecycle.t.sol -j 1 -vv` | 5 passed |
| Integrated lifecycle | `forge test --no-cache --match-path test/integration/IntegratedLifecycle.t.sol -j 1 -vv` | 10 passed |
| Canonical market | `forge test --match-path test/integration/CanonicalMarketLifecycle.t.sol -j 1 -vv` | 6 passed after static-analysis remediation |
| Deterministic deployment | `forge test --match-path test/deployment/DeterministicDeployment.t.sol -j 1 -vv` | 4 passed after static-analysis remediation |
| Economic fuzz | `forge test --no-cache --match-path test/fuzz/EconomicFuzz.t.sol -j 1 -vv` | 4 properties × 1,000 runs |
| Recovery fuzz | `forge test --no-cache --match-path test/fuzz/RecoveryDistributionFuzz.t.sol -j 1 -vv` | 1 property × 1,000 runs |
| Protocol invariants | `FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=50 forge test --no-cache --match-path test/invariant/ProtocolInvariant.t.sol -j 1 -vv` | 5 invariants, 64,000 calls |
| Governance invariants | `FOUNDRY_INVARIANT_RUNS=256 FOUNDRY_INVARIANT_DEPTH=50 forge test --no-cache --match-path test/invariant/GovernanceInvariant.t.sol -j 1 -vv` | 2 invariants, 25,600 calls |
| Canonical market invariants | `FOUNDRY_INVARIANT_RUNS=64 FOUNDRY_INVARIANT_DEPTH=32 forge test --match-path test/invariant/CanonicalMarketInvariant.t.sol -j 1 -vv` | 2 invariants, 4,096 real-v4 calls after remediation |

Aggregate executed coverage was 56 test/property/invariant methods, 5,000 fuzz cases, and 93,696 stateful invariant calls. The tests exercise real purchases, time advancement, emission materialization, forward commitments, settlements, claims, pauses, finalization, pool launch, buys, sells, bilateral fees, restricted transfers, and locked LP ownership. Synthetic handler setup remains limited to the documented invariant harnesses.

## Formatting, linting, and storage

- `forge fmt --check` passed.
- `forge lint src script test --severity high med low -j 1` exited successfully. The actionable unchecked POTATO return warnings were remediated in `6755c22`.
- Forge continues to report non-failing narrow-cast warnings in bounded Diamond array positions, v4 signed deltas, and test generators. They are retained for the full audit rather than hidden with blanket suppressions.
- `forge inspect <facet> storage-layout --json` reported zero ordinary storage entries for every Diamond facet. `BurntatoSwapFeeHook` reported its one intended standalone `deploymentBlock` entry. Diamond state otherwise resides in explicit namespaced libraries.
- The deployment verifier confirmed 9 installed facets and 57 expected selectors with exact group routing.

## Static analysis

Command:

```bash
FOUNDRY_EVM_VERSION=cancun aderyn . \
  --src src \
  --path-excludes lib,test,script \
  --skip-build \
  --skip-update-check \
  --output /tmp/burntato-aderyn-pr9-remediated.md
```

The EVM override works around this installed Aderyn version failing to parse an `osaka` setting inside a pinned dependency. Aderyn analyzed 24 Burntato source files, 1,098 nSLOC, and 63 detectors.

The initial report contained 5 high detector categories. The unchecked-return category was confirmed and fixed for Diamond approval and hook settlement transfer. The rerun contains 4 high detector categories and 5 low categories:

| Detector | Classification |
| --- | --- |
| Unprotected initializer | Not applicable: `FoundationInit` has a namespaced one-shot guard and is delegatecalled only through authorized `diamondCut`; the hook callback is internal and PoolManager-gated. |
| Yul `return` | Intentional EIP-2535 fallback behavior returning delegatecall data to the external caller. |
| Native send not protected | Not applicable: Recovery verifies the caller's committed position; Treasury claims are permissionless but always pay the fixed Treasury recipient. Both use the shared reentrancy guard. |
| Contract locks ETH | Not applicable to facets executed by delegatecall; Diamond ETH exits through claims and market launch. Hook fee ETH is forwarded to canonical Treasury accounting during settlement. Forced ETH outside protocol accounting is intentionally not sweepable. |
| Unsafe ERC-20 operation | Exact Burntato POTATO and Permit2 integration, not arbitrary third-party tokens. POTATO boolean returns are now checked. |
| Public hook permission method | Required by the inherited v4 hook interface. |
| Event indexing suggestions | Informational indexing/gas tradeoff; canonical account, round, pool, and sender fields are already indexed. |
| Large literal style | Informational; basis-point and POTATO constants intentionally use readable underscore notation. |
| Unused custom errors | Analyzer limitation across qualified library error references; the reported errors are used by protocol libraries and tests. |

The static report is a release input, not a substitute for the requested audit. Disposable analyzer reports remain outside version control.

## Clean local deployment

Commands:

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337

forge script script/DeployBurntato.s.sol:DeployBurntato \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --unlocked \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  -vv
```

The final candidate completed 23 local onchain deployment/configuration transactions successfully. Independent verification returned `true` using `VerifyBurntato`.

| Component | Local address |
| --- | --- |
| BurntatoDiamond | `0xa513E6E4b8f2a923D98304ec87F64353C4D5C853` |
| TimelockController | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| PoolManager | `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512` |
| LocalPermit2 | `0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0` |
| LocalWETH9 | `0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9` |
| PositionDescriptor | `0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9` |
| PositionManager | `0x5FC8d32690cc91D4c39d9d3abcBD16989F875707` |
| CREATE2 hook deployer | `0x68B1D87F95878fE05B998F19b66F4baba5De1aed` |
| BurntatoSwapFeeHook | `0x108A985C30E6933F4b54AD8588913C5A7321A444` |

The hook's masked permission bits are `0x2444`: before-initialize, after-add-liquidity, after-swap, and after-swap-return-delta. The configured PoolKey uses native ETH as currency0, the Diamond as POTATO currency1, zero LP fee, spacing 60, and the exact hook above. The pool remains intentionally uninitialized until Treasury reserves exist.

The deployment test separately earned launch inventory through real gameplay and Recovery settlement, launched the pool, and confirmed PositionManager token ID 1 belongs to `0x000000000000000000000000000000000000dEaD`.

## Authority and initial state

The verifier confirmed:

- Diamond authority and PoolManager ownership are the TimelockController;
- the timelock self-holds admin, the intended account holds proposer/canceller, execution is open, and the deployer holds no role;
- guardian and Treasury recipient match separate configured accounts;
- purchases and commitments are unpaused and global finalization is false;
- POTATO has 18 decimals, zero initial supply, and no public mint path;
- the initial round identifier is zero until the first purchase;
- market configuration is complete but not yet funded or launched; and
- no launch reserve is claimable before it exists.

## Dependency and proof boundaries

Pinned revisions:

- Uniswap v4 core `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc`;
- Uniswap v4 periphery `60cd93803ac2b7fa65fd6cd351fd5fd4cc8c9db5`;
- FWA.fun precedent `1085bf6ee255d6d4d13c374a66110bb25229dc76`.

This evidence proves local compilation, execution, static analysis, and fresh Anvil deployment. It does not prove a fork, testnet, mainnet, third-party Permit2 deployment, production genesis choice, remote CI result, or independent external audit. Local price and seed values are development defaults; production market parameters remain undecided.
