// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {BurntatoDiamond} from "../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {GovernanceFacet} from "../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../src/facets/PotatoTokenFacet.sol";
import {BuybackFacet} from "../src/facets/BuybackFacet.sol";
import {GameFacet} from "../src/facets/GameFacet.sol";
import {RecoveryFacet} from "../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../src/facets/SettlementFacet.sol";
import {ClaimsFacet} from "../src/facets/ClaimsFacet.sol";
import {TreasuryRewardsFacet} from "../src/facets/TreasuryRewardsFacet.sol";
import {BurntatoOperatorRewardsRouter} from "../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {FoundationInit} from "../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";
import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {ITreasuryRewards} from "../src/interfaces/ITreasuryRewards.sol";
import {FacetCut, FacetCutAction} from "../src/shared/Types.sol";
import {LibConfig} from "../src/libraries/LibConfig.sol";
import {
    BurntatoDeployment,
    GenesisConfig,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";
import {StaticsMarketDeploymentConfig} from "./libraries/StaticsMarketDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

/// @notice Fresh zero-supply wrapper deployment. Funding and activation are separate actions.
contract DeployBurntato is Script {
    error InvalidGenesisConfiguration();
    error UnexpectedDeployer(address expected, address actual);

    function run() public virtual returns (BurntatoDeployment memory deployment) {
        GenesisConfig memory config = _environmentConfig();
        StaticsMarketDependencies memory market = StaticsMarketDeploymentConfig.load();
        StaticsOperatorDependencies memory operators = _operatorDependencies();
        _validateMarket(market);
        _validateOperators(operators);
        config.statics = market.statics;
        _validateConfig(config, config.deployer);
        require(config.deployer.balance >= config.initialWinnerReserve, "initial Winner reserve not funded");
        uint256 key = vm.envUint("PRIVATE_KEY");
        if (key == 0 || vm.addr(key) != config.deployer) revert UnexpectedDeployer(config.deployer, vm.addr(key));
        vm.startBroadcast(key);
        deployment = deployWithDependencies(config, config.deployer, market, operators);
        vm.stopBroadcast();
        _writeDeployment(deployment, config, market, operators, _outputDirectory());
        _log(deployment);
    }

    /// @dev Production entrypoints additionally enforce the committed manifests before signing.
    function deployWithDependencies(
        GenesisConfig memory config,
        address bootstrapAuthority,
        StaticsMarketDependencies memory market,
        StaticsOperatorDependencies memory operators
    ) public returns (BurntatoDeployment memory d) {
        _validateConfig(config, bootstrapAuthority);
        if (config.statics != market.statics) revert InvalidGenesisConfiguration();
        StaticsMarketDeploymentConfig.validateRuntime(market);
        if (config.protocol.operatorPurchaseBps != 0) {
            _validateOperators(operators);
        }
        d.admin = config.finalAdmin;
        d.statics = market.statics;
        d.weth9 = market.weth;
        d.poolManager = market.poolManager;
        d.diamondCutFacet = address(new DiamondCutFacet());
        d.diamond =
            address(new BurntatoDiamond{value: config.initialWinnerReserve}(bootstrapAuthority, d.diamondCutFacet));
        d.diamondLoupeFacet = address(new DiamondLoupeFacet());
        d.governanceFacet = address(new GovernanceFacet());
        d.potatoTokenFacet = address(new PotatoTokenFacet());
        d.buybackFacet = address(new BuybackFacet());
        d.gameFacet = address(new GameFacet());
        d.recoveryFacet = address(new RecoveryFacet());
        d.settlementFacet = address(new SettlementFacet());
        d.claimsFacet = address(new ClaimsFacet());
        d.treasuryRewardsFacet = address(new TreasuryRewardsFacet());
        d.foundationInit = address(new FoundationInit());
        if (config.protocol.operatorPurchaseBps != 0) {
            d.operatorRewardsRouter = address(
                new BurntatoOperatorRewardsRouter(d.diamond, operators.operatorsNft, operators.activationRegistry)
            );
        }
        FacetCut[] memory cuts = new FacetCut[](9);
        cuts[0] = FacetCut(d.diamondLoupeFacet, FacetCutAction.Add, BurntatoSelectors.loupe());
        cuts[1] = FacetCut(d.governanceFacet, FacetCutAction.Add, BurntatoSelectors.governance());
        cuts[2] = FacetCut(d.potatoTokenFacet, FacetCutAction.Add, BurntatoSelectors.token());
        cuts[3] = FacetCut(d.buybackFacet, FacetCutAction.Add, BurntatoSelectors.buyback());
        cuts[4] = FacetCut(d.gameFacet, FacetCutAction.Add, BurntatoSelectors.game());
        cuts[5] = FacetCut(d.recoveryFacet, FacetCutAction.Add, BurntatoSelectors.recovery());
        cuts[6] = FacetCut(d.settlementFacet, FacetCutAction.Add, BurntatoSelectors.settlement());
        cuts[7] = FacetCut(d.claimsFacet, FacetCutAction.Add, BurntatoSelectors.claims());
        cuts[8] = FacetCut(d.treasuryRewardsFacet, FacetCutAction.Add, BurntatoSelectors.treasuryRewards());
        IDiamondCut(d.diamond)
            .diamondCut(
                cuts,
                d.foundationInit,
                abi.encodeCall(
                    FoundationInit.initialize,
                    (
                        config.protocol,
                        config.treasuryRecipient,
                        d.operatorRewardsRouter,
                        config.statics,
                        config.initialWinnerReserve
                    )
                )
            );
        IGovernance(d.diamond).setGuardian(config.guardian);
        IPotatoToken(d.diamond).setDistributor(config.treasuryRecipient, true);
        IPotatoToken(d.diamond).setPublicWrapCap(config.publicWrapCap);
        IBuyback(d.diamond).setBuybackConfig(config.buyback);
        IBuyback(d.diamond).setBuybackMarket(market.poolManager, market.weth, market.key);
        ITreasuryRewards(d.diamond).setRewardAllocator(config.rewardAllocator);
        IGovernance(d.diamond).setAuthority(config.finalAdmin);
    }

    function _operatorDependencies() internal view virtual returns (StaticsOperatorDependencies memory) {
        return StaticsOperatorDeploymentConfig.load();
    }

    function _validateMarket(StaticsMarketDependencies memory market) internal virtual {
        StaticsMarketDeploymentConfig.validate(market);
    }

    function _validateOperators(StaticsOperatorDependencies memory operators) internal virtual {
        StaticsOperatorDeploymentConfig.validate(operators);
    }

    function localDefaults() external pure returns (GenesisConfig memory) {
        return BurntatoDeploymentConfig.localDefaults();
    }

    function environmentConfig() external view returns (GenesisConfig memory) {
        return _environmentConfig();
    }

    function _environmentConfig() internal view virtual returns (GenesisConfig memory c) {
        c = BurntatoDeploymentConfig.launchDefaults();
        c.deployer = vm.envAddress("BURNTATO_DEPLOYER");
        c.finalAdmin = vm.envAddress("BURNTATO_FINAL_ADMIN");
        c.guardian = vm.envAddress("BURNTATO_GUARDIAN");
        c.treasuryRecipient = vm.envAddress("BURNTATO_TREASURY");
        c.rewardAllocator = vm.envAddress("BURNTATO_REWARD_ALLOCATOR");
    }

    function _validateConfig(GenesisConfig memory c, address bootstrapAuthority) internal pure {
        LibConfig.validate(c.protocol);
        if (
            bootstrapAuthority == address(0) || bootstrapAuthority != c.deployer || c.finalAdmin == address(0)
                || c.treasuryRecipient == address(0) || c.rewardAllocator == address(0)
                || c.buyback.callerRewardBps > 100 || c.statics == address(0)
        ) revert InvalidGenesisConfiguration();
    }

    function _deploymentMode() internal view virtual returns (string memory) {
        return "production";
    }

    function _outputDirectory() internal view virtual returns (string memory) {
        if (block.chainid == 4663) return "artifacts/robinhood-mainnet";
        if (block.chainid == 46630) return "artifacts/robinhood-testnet";
        revert InvalidGenesisConfiguration();
    }

    function _writeDeployment(
        BurntatoDeployment memory d,
        GenesisConfig memory c,
        StaticsMarketDependencies memory market,
        StaticsOperatorDependencies memory operators,
        string memory directory
    ) internal {
        string memory object = "backedBurntato";
        vm.createDir(directory, true);
        vm.serializeUint(object, "schemaVersion", 4);
        vm.serializeString(object, "deploymentMode", _deploymentMode());
        vm.serializeUint(object, "deploymentBlock", block.number);
        vm.serializeUint(object, "marketManifestBlock", market.forkBlock);
        vm.serializeBytes32(object, "marketManifestBlockHash", market.forkBlockHash);
        vm.serializeUint(object, "staticsFinalizedBlock", operators.finalizedBlock);
        vm.serializeBytes32(object, "staticsFinalizedBlockHash", operators.finalizedBlockHash);
        vm.serializeAddress(object, "operatorsNft", operators.operatorsNft);
        vm.serializeAddress(object, "activationRegistry", operators.activationRegistry);
        _serializeEconomics(object, c);
        vm.serializeUint(object, "chainId", block.chainid);
        vm.serializeString(object, "sourceCommit", vm.envString("BURNTATO_SOURCE_COMMIT"));
        vm.serializeBytes(object, "deployment", abi.encode(d));
        vm.serializeBytes(object, "genesisConfig", abi.encode(c));
        vm.serializeBytes(object, "marketDependencies", abi.encode(market));
        vm.serializeBytes(object, "operatorDependencies", abi.encode(operators));
        vm.serializeBytes32(object, "poolId", market.poolId);
        vm.serializeAddress(object, "deployer", c.deployer);
        vm.serializeAddress(object, "guardian", c.guardian);
        vm.serializeAddress(object, "treasuryRecipient", c.treasuryRecipient);
        vm.serializeAddress(object, "rewardAllocator", c.rewardAllocator);
        vm.serializeAddress(object, "diamond", d.diamond);
        vm.serializeBytes32(object, "diamondRuntimeCodeHash", d.diamond.codehash);
        vm.serializeAddress(object, "diamondCutFacet", d.diamondCutFacet);
        vm.serializeBytes32(object, "diamondCutFacetRuntimeCodeHash", d.diamondCutFacet.codehash);
        vm.serializeAddress(object, "diamondLoupeFacet", d.diamondLoupeFacet);
        vm.serializeBytes32(object, "diamondLoupeFacetRuntimeCodeHash", d.diamondLoupeFacet.codehash);
        vm.serializeAddress(object, "governanceFacet", d.governanceFacet);
        vm.serializeBytes32(object, "governanceFacetRuntimeCodeHash", d.governanceFacet.codehash);
        vm.serializeAddress(object, "buybackFacet", d.buybackFacet);
        vm.serializeBytes32(object, "buybackFacetRuntimeCodeHash", d.buybackFacet.codehash);
        vm.serializeAddress(object, "potatoTokenFacet", d.potatoTokenFacet);
        vm.serializeBytes32(object, "potatoTokenFacetRuntimeCodeHash", d.potatoTokenFacet.codehash);
        vm.serializeAddress(object, "gameFacet", d.gameFacet);
        vm.serializeBytes32(object, "gameFacetRuntimeCodeHash", d.gameFacet.codehash);
        vm.serializeAddress(object, "recoveryFacet", d.recoveryFacet);
        vm.serializeBytes32(object, "recoveryFacetRuntimeCodeHash", d.recoveryFacet.codehash);
        vm.serializeAddress(object, "settlementFacet", d.settlementFacet);
        vm.serializeBytes32(object, "settlementFacetRuntimeCodeHash", d.settlementFacet.codehash);
        vm.serializeAddress(object, "claimsFacet", d.claimsFacet);
        vm.serializeBytes32(object, "claimsFacetRuntimeCodeHash", d.claimsFacet.codehash);
        vm.serializeAddress(object, "treasuryRewardsFacet", d.treasuryRewardsFacet);
        vm.serializeBytes32(object, "treasuryRewardsFacetRuntimeCodeHash", d.treasuryRewardsFacet.codehash);
        vm.serializeAddress(object, "foundationInit", d.foundationInit);
        vm.serializeBytes32(object, "foundationInitRuntimeCodeHash", d.foundationInit.codehash);
        vm.serializeAddress(object, "admin", d.admin);
        vm.serializeBytes32(object, "adminRuntimeCodeHash", d.admin.codehash);
        vm.serializeAddress(object, "statics", d.statics);
        vm.serializeBytes32(object, "staticsRuntimeCodeHash", d.statics.codehash);
        vm.serializeAddress(object, "poolManager", d.poolManager);
        vm.serializeBytes32(object, "poolManagerRuntimeCodeHash", d.poolManager.codehash);
        vm.serializeAddress(object, "weth9", d.weth9);
        vm.serializeBytes32(object, "weth9RuntimeCodeHash", d.weth9.codehash);
        vm.serializeAddress(object, "operatorRewardsRouter", d.operatorRewardsRouter);
        vm.serializeBytes32(object, "operatorRewardsRouterRuntimeCodeHash", d.operatorRewardsRouter.codehash);
        string memory json = vm.serializeBytes32(object, "configHash", keccak256(abi.encode(c, market, operators)));
        vm.writeJson(json, string.concat(directory, "/deployment.json"));
    }

    function _serializeEconomics(string memory object, GenesisConfig memory c) private {
        vm.serializeUint(object, "startingPrice", c.protocol.startingPrice);
        vm.serializeUint(object, "priceIncreaseBps", c.protocol.priceIncreaseBps);
        vm.serializeUint(object, "roundTimeout", c.protocol.roundTimeout);
        vm.serializeUint(object, "roundTimeoutDecay", c.protocol.roundTimeoutDecay);
        vm.serializeUint(object, "minimumRoundTimeout", c.protocol.minimumRoundTimeout);
        vm.serializeUint(object, "roundEmissionBudget", c.protocol.roundEmissionBudget);
        vm.serializeUint(object, "emissionStepBps", c.protocol.emissionStepBps);
        vm.serializeUint(object, "emissionVestingDuration", c.protocol.emissionVestingDuration);
        vm.serializeUint(object, "winnerBps", c.protocol.winnerBps);
        vm.serializeUint(object, "nextRoundWinnerBps", c.protocol.nextRoundWinnerBps);
        vm.serializeUint(object, "recoveryBps", c.protocol.recoveryBps);
        vm.serializeUint(object, "treasuryBps", c.protocol.treasuryBps);
        vm.serializeUint(object, "buybackBps", c.protocol.buybackBps);
        vm.serializeUint(object, "operatorPurchaseBps", c.protocol.operatorPurchaseBps);
        vm.serializeUint(object, "initialWinnerReserve", c.initialWinnerReserve);
        vm.serializeUint(object, "buybackMaxSpend", c.buyback.maxSpend);
        vm.serializeUint(object, "buybackCallerRewardBps", c.buyback.callerRewardBps);
        vm.serializeUint(object, "buybackDelayBlocks", c.buyback.delayBlocks);
        vm.serializeUint(object, "publicWrapCap", c.publicWrapCap);
    }

    function _log(BurntatoDeployment memory d) internal pure {
        console2.log("BurntatoDiamond", d.diamond);
        console2.log("STATICS backing", d.statics);
        console2.log("OperatorRewardsRouter", d.operatorRewardsRouter);
    }
}
