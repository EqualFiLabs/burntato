// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {AnvilForkValidation} from "./libraries/AnvilForkValidation.sol";
import {Script, console2} from "forge-std/Script.sol";
import {
    BurntatoDeployment,
    GenesisConfig,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDiamond} from "../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {FoundationInit} from "../src/initializers/FoundationInit.sol";
import {BurntatoOperatorRewardsRouter} from "../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";
import {IGame} from "../src/interfaces/IGame.sol";
import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IClaims} from "../src/interfaces/IClaims.sol";
import {ITreasuryRewards} from "../src/interfaces/ITreasuryRewards.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";
import {StaticsMarketDeploymentConfig} from "./libraries/StaticsMarketDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {GovernanceFacet} from "../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../src/facets/PotatoTokenFacet.sol";
import {BuybackFacet} from "../src/facets/BuybackFacet.sol";
import {GameFacet} from "../src/facets/GameFacet.sol";
import {RecoveryFacet} from "../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../src/facets/SettlementFacet.sol";
import {ClaimsFacet} from "../src/facets/ClaimsFacet.sol";
import {TreasuryRewardsFacet} from "../src/facets/TreasuryRewardsFacet.sol";

/// @notice Read-only source/runtime and configuration verification for fresh schema-4 deployments.
contract VerifyBurntato is Script {
    function run() external returns (bool) {
        return runAtPhase(vm.envOr("BURNTATO_DEPLOYMENT_PHASE", uint256(0)));
    }

    function runAtPhase(uint256 phase) public returns (bool) {
        string memory json = vm.readFile(vm.envString("BURNTATO_DEPLOYMENT_ARTIFACT"));
        require(vm.parseJsonUint(json, ".schemaVersion") == 4, "historical artifact unsupported");
        BurntatoDeployment memory d = abi.decode(vm.parseJsonBytes(json, ".deployment"), (BurntatoDeployment));
        GenesisConfig memory c = abi.decode(vm.parseJsonBytes(json, ".genesisConfig"), (GenesisConfig));
        StaticsMarketDependencies memory m =
            abi.decode(vm.parseJsonBytes(json, ".marketDependencies"), (StaticsMarketDependencies));
        StaticsOperatorDependencies memory o =
            abi.decode(vm.parseJsonBytes(json, ".operatorDependencies"), (StaticsOperatorDependencies));
        require(vm.parseJsonUint(json, ".chainId") == block.chainid, "artifact chain");
        require(vm.parseJsonBytes32(json, ".configHash") == keccak256(abi.encode(c, m, o)), "artifact config hash");
        verifyReadableConfig(json, d, c);
        _verifyDependencies(vm.parseJsonString(json, ".deploymentMode"), c, m, o);
        verify(d, c, m, o, phase);
        console2.log("Verified source runtimes, selectors, backing and launch configuration", d.diamond);
        return true;
    }

    function verifyReadableConfig(string memory json, BurntatoDeployment memory d, GenesisConfig memory c) public pure {
        require(vm.parseJsonAddress(json, ".diamond") == d.diamond, "artifact Diamond");
        require(vm.parseJsonAddress(json, ".admin") == d.admin && d.admin == c.finalAdmin, "artifact admin");
        require(vm.parseJsonAddress(json, ".deployer") == c.deployer, "artifact deployer");
        require(vm.parseJsonAddress(json, ".guardian") == c.guardian, "artifact guardian");
        require(vm.parseJsonAddress(json, ".treasuryRecipient") == c.treasuryRecipient, "artifact Treasury");
        require(vm.parseJsonAddress(json, ".rewardAllocator") == c.rewardAllocator, "artifact allocator");
        require(vm.parseJsonUint(json, ".startingPrice") == c.protocol.startingPrice, "artifact startingPrice");
        require(vm.parseJsonUint(json, ".priceIncreaseBps") == c.protocol.priceIncreaseBps, "artifact priceIncreaseBps");
        require(vm.parseJsonUint(json, ".roundTimeout") == c.protocol.roundTimeout, "artifact roundTimeout");
        require(
            vm.parseJsonUint(json, ".roundTimeoutDecay") == c.protocol.roundTimeoutDecay, "artifact roundTimeoutDecay"
        );
        require(
            vm.parseJsonUint(json, ".minimumRoundTimeout") == c.protocol.minimumRoundTimeout,
            "artifact minimumRoundTimeout"
        );
        require(
            vm.parseJsonUint(json, ".roundEmissionBudget") == c.protocol.roundEmissionBudget,
            "artifact roundEmissionBudget"
        );
        require(vm.parseJsonUint(json, ".emissionStepBps") == c.protocol.emissionStepBps, "artifact emissionStepBps");
        require(
            vm.parseJsonUint(json, ".emissionVestingDuration") == c.protocol.emissionVestingDuration,
            "artifact emissionVestingDuration"
        );
        require(vm.parseJsonUint(json, ".winnerBps") == c.protocol.winnerBps, "artifact winnerBps");
        require(
            vm.parseJsonUint(json, ".nextRoundWinnerBps") == c.protocol.nextRoundWinnerBps,
            "artifact nextRoundWinnerBps"
        );
        require(vm.parseJsonUint(json, ".recoveryBps") == c.protocol.recoveryBps, "artifact recoveryBps");
        require(vm.parseJsonUint(json, ".treasuryBps") == c.protocol.treasuryBps, "artifact treasuryBps");
        require(vm.parseJsonUint(json, ".buybackBps") == c.protocol.buybackBps, "artifact buybackBps");
        require(
            vm.parseJsonUint(json, ".operatorPurchaseBps") == c.protocol.operatorPurchaseBps,
            "artifact operatorPurchaseBps"
        );
        require(
            vm.parseJsonUint(json, ".initialWinnerReserve") == c.initialWinnerReserve, "artifact initialWinnerReserve"
        );
        require(vm.parseJsonUint(json, ".buybackMaxSpend") == c.buyback.maxSpend, "artifact buybackMaxSpend");
        require(
            vm.parseJsonUint(json, ".buybackCallerRewardBps") == c.buyback.callerRewardBps,
            "artifact buybackCallerRewardBps"
        );
        require(vm.parseJsonUint(json, ".buybackDelayBlocks") == c.buyback.delayBlocks, "artifact buybackDelayBlocks");
        require(vm.parseJsonUint(json, ".publicWrapCap") == c.publicWrapCap, "artifact publicWrapCap");
    }

    function _verifyDependencies(
        string memory mode,
        GenesisConfig memory c,
        StaticsMarketDependencies memory m,
        StaticsOperatorDependencies memory o
    ) private {
        bytes32 kind = keccak256(bytes(mode));
        if (kind == keccak256("production")) {
            StaticsMarketDeploymentConfig.validate(m);
            if (c.protocol.operatorPurchaseBps != 0) StaticsOperatorDeploymentConfig.validate(o);
            return;
        }
        if (kind == keccak256("local")) {
            require(
                block.chainid == 31337 && vm.rpc("anvil_getAutomine", "[]").length != 0, "standalone Anvil required"
            );
            require(c.protocol.operatorPurchaseBps == 0, "standalone Operators unsupported");
            StaticsMarketDeploymentConfig.validateRuntime(m);
            return;
        }
        require(
            kind == keccak256("local-fork") || kind == keccak256("local-replica")
                || kind == keccak256("mainnet-rehearsal"),
            "invalid deployment mode"
        );
        AnvilForkValidation.requireMainnet();
        StaticsMarketDeploymentConfig.validateAnvilFork(
            m, AnvilForkValidation.height(), AnvilForkValidation.blockHash(m.forkBlock)
        );
        if (c.protocol.operatorPurchaseBps == 0) return;
        if (kind == keccak256("local-replica")) {
            require(
                o.operatorsNft.codehash == o.operatorsNftCodeHash
                    && o.activationRegistry.codehash == o.activationRegistryCodeHash,
                "replica runtime drift"
            );
            StaticsOperatorDeploymentConfig.validateLocalReplica(o);
        } else {
            StaticsOperatorDeploymentConfig.validateAnvilFork(
                o, AnvilForkValidation.height(), AnvilForkValidation.blockHash(o.finalizedBlock)
            );
        }
    }

    function verify(
        BurntatoDeployment memory d,
        GenesisConfig memory c,
        StaticsMarketDependencies memory m,
        StaticsOperatorDependencies memory o,
        uint256 phase
    ) public view {
        require(d.diamond.codehash == keccak256(type(BurntatoDiamond).runtimeCode), "Diamond runtime");
        require(d.foundationInit.codehash == keccak256(type(FoundationInit).runtimeCode), "initializer runtime");
        require(d.diamondCutFacet.codehash == keccak256(type(DiamondCutFacet).runtimeCode), "cut runtime");
        require(
            IDiamondLoupe(d.diamond).facetAddress(IDiamondCut.diamondCut.selector) == d.diamondCutFacet, "cut selector"
        );
        require(IDiamondLoupe(d.diamond).facetAddresses().length == 10, "unexpected facets");
        _facet(
            d.diamond, d.diamondLoupeFacet, BurntatoSelectors.loupe(), keccak256(type(DiamondLoupeFacet).runtimeCode)
        );
        _facet(
            d.diamond, d.governanceFacet, BurntatoSelectors.governance(), keccak256(type(GovernanceFacet).runtimeCode)
        );
        _facet(d.diamond, d.potatoTokenFacet, BurntatoSelectors.token(), keccak256(type(PotatoTokenFacet).runtimeCode));
        _facet(d.diamond, d.buybackFacet, BurntatoSelectors.buyback(), keccak256(type(BuybackFacet).runtimeCode));
        _facet(d.diamond, d.gameFacet, BurntatoSelectors.game(), keccak256(type(GameFacet).runtimeCode));
        _facet(d.diamond, d.recoveryFacet, BurntatoSelectors.recovery(), keccak256(type(RecoveryFacet).runtimeCode));
        _facet(
            d.diamond, d.settlementFacet, BurntatoSelectors.settlement(), keccak256(type(SettlementFacet).runtimeCode)
        );
        _facet(d.diamond, d.claimsFacet, BurntatoSelectors.claims(), keccak256(type(ClaimsFacet).runtimeCode));
        _facet(
            d.diamond,
            d.treasuryRewardsFacet,
            BurntatoSelectors.treasuryRewards(),
            keccak256(type(TreasuryRewardsFacet).runtimeCode)
        );
        require(phase <= 3, "invalid deployment phase");
        IGovernance g = IGovernance(d.diamond);
        require(g.foundationConfigured() && !g.protocolFinalized() && !g.paused(), "governance state");
        require(g.authority() == c.finalAdmin && g.guardian() == c.guardian, "authority roles");
        if (phase != 3) require(g.purchasesInitialized() == (phase == 2), "activation state");
        require(keccak256(abi.encode(g.protocolConfig())) == keccak256(abi.encode(c.protocol)), "protocol config");
        require(IClaims(d.diamond).treasuryRecipient() == c.treasuryRecipient, "Treasury");
        require(ITreasuryRewards(d.diamond).rewardAllocator() == c.rewardAllocator, "allocator");
        IPotatoToken t = IPotatoToken(d.diamond);
        require(t.underlying() == m.statics && c.statics == m.statics && d.statics == m.statics, "underlying");
        require(t.publicWrapCap() == c.publicWrapCap, "public cap");
        require(t.backingBalance() >= t.totalSupply(), "backing deficit");
        require(t.balanceOf(d.diamond) >= t.rewardReserve(), "reserve inventory");
        require(t.isDistributor(c.treasuryRecipient), "Treasury distributor");
        require(
            keccak256(bytes(t.name())) == keccak256("Burntato Potato")
                && keccak256(bytes(t.symbol())) == keccak256("POTATO") && t.decimals() == 18,
            "metadata"
        );
        (address manager, address weth, PoolKey memory key) = IBuyback(d.diamond).buybackMarket();
        require(
            manager == m.poolManager && weth == m.weth && d.poolManager == manager && d.weth9 == weth,
            "market dependencies"
        );
        require(keccak256(abi.encode(key)) == keccak256(abi.encode(m.key)), "market PoolKey");
        require(
            keccak256(abi.encode(IBuyback(d.diamond).buybackConfig())) == keccak256(abi.encode(c.buyback)),
            "buyback config"
        );
        require(IGame(d.diamond).purchaseOperatorRewardsRouter() == d.operatorRewardsRouter, "operator router");
        if (c.protocol.operatorPurchaseBps != 0) {
            verifyOperatorRouter(d.operatorRewardsRouter, d.diamond, o.operatorsNft, o.activationRegistry);
        }
        if (phase == 0) {
            require(t.totalSupply() == 0 && t.rewardReserve() == 0 && t.publicWrapOutstanding() == 0, "fresh supply");
            require(
                IGame(d.diamond).currentRoundId() == 0 && IGame(d.diamond).winnerReserveEth() == c.initialWinnerReserve,
                "fresh game"
            );
        }
        if (phase == 2 && IGame(d.diamond).currentRoundId() == 0) {
            (,,, bool funded) = t.nextRoundFundingStatus();
            require(funded, "unfunded first round");
        }
        if (phase == 1) {
            (,,, bool funded) = t.nextRoundFundingStatus();
            require(funded && IGame(d.diamond).currentRoundId() == 0, "unfunded first round");
        }
        require(
            IDiamondLoupe(d.diamond).facetAddress(bytes4(keccak256("burn(uint256)"))) == address(0), "obsolete burn"
        );
        require(
            IDiamondLoupe(d.diamond).facetAddress(bytes4(keccak256("launchMarket()"))) == address(0), "obsolete market"
        );
    }

    struct ImmutableReference {
        uint256 length;
        uint256 start;
    }

    /// @notice Compare the source runtime after substituting its three constructor immutables.
    function verifyOperatorRouter(address routerAddress, address diamond, address operators, address registry)
        public
        view
    {
        bytes memory expected = vm.getDeployedCode("BurntatoOperatorRewardsRouter.sol:BurntatoOperatorRewardsRouter");
        string memory artifact = vm.readFile(vm.getArtifactPathByDeployedCode(expected));
        string memory base = ".deployedBytecode.immutableReferences";
        string[] memory ids = vm.parseJsonKeys(artifact, base);
        require(ids.length == 3, "unexpected router immutables");
        // Solidity AST IDs increase in declaration order: burntato, operators, activationRegistry.
        for (uint256 i; i < ids.length; ++i) {
            for (uint256 j = i + 1; j < ids.length; ++j) {
                if (vm.parseUint(ids[j]) < vm.parseUint(ids[i])) (ids[i], ids[j]) = (ids[j], ids[i]);
            }
        }
        address[3] memory values = [diamond, operators, registry];
        for (uint256 i; i < ids.length; ++i) {
            ImmutableReference[] memory refs =
                abi.decode(vm.parseJson(artifact, string.concat(base, ".", ids[i])), (ImmutableReference[]));
            require(refs.length != 0, "missing router immutable");
            for (uint256 j; j < refs.length; ++j) {
                uint256 offset = refs[j].start;
                require(refs[j].length == 32 && offset + 32 <= expected.length, "invalid immutable reference");
                uint256 value = uint160(values[i]);
                assembly ("memory-safe") {
                    mstore(add(add(expected, 0x20), offset), value)
                }
            }
        }
        require(routerAddress.codehash == keccak256(expected), "operator router source runtime");
        BurntatoOperatorRewardsRouter router = BurntatoOperatorRewardsRouter(payable(routerAddress));
        require(
            router.burntato() == diamond && address(router.operators()) == operators
                && address(router.activationRegistry()) == registry,
            "operator bindings"
        );
    }

    function _facet(address diamond, address facet, bytes4[] memory selectors, bytes32 sourceHash) private view {
        require(facet.codehash == sourceHash, "facet source runtime");
        bytes4[] memory actual = IDiamondLoupe(diamond).facetFunctionSelectors(facet);
        require(actual.length == selectors.length, "unexpected selector count");
        for (uint256 i; i < selectors.length; ++i) {
            require(IDiamondLoupe(diamond).facetAddress(selectors[i]) == facet, "selector binding");
        }
    }
}
