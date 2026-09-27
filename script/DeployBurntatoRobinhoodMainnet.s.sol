// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibString} from "solady/src/utils/LibString.sol";

import {DeployBurntato} from "./DeployBurntato.s.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {BurntatoLaunchCurves} from "../src/libraries/BurntatoLaunchCurves.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract DeployBurntatoRobinhoodMainnet is DeployBurntato {
    uint256 public constant CHAIN_ID = 4_663;
    string public constant OUTPUT_PATH = "artifacts/robinhood-mainnet/deployment.json";

    error InvalidMainnetChain(uint256 actualChainId);
    error InvalidMainnetAnvilRpc();
    error InvalidMainnetRole(bytes32 role, address account);
    error UnexpectedDeployer(address expected, address actual);
    error InsufficientDeployerBalance(uint256 required, uint256 actual);

    function run() external override returns (BurntatoDeployment memory deployment) {
        (
            GenesisConfig memory config,
            CanonicalV4Dependencies memory dependencies,
            StaticsOperatorDependencies memory operatorDependencies
        ) = _preflight();

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        if (deployer != config.deployer) revert UnexpectedDeployer(config.deployer, deployer);

        vm.startBroadcast(privateKey);
        deployment = deployWithDependencies(config, deployer, dependencies, operatorDependencies);
        vm.stopBroadcast();

        _writeDeployment(deployment, config, dependencies, operatorDependencies);
        _log(deployment);
    }

    function preflight()
        external
        returns (
            GenesisConfig memory config,
            CanonicalV4Dependencies memory dependencies,
            StaticsOperatorDependencies memory operatorDependencies
        )
    {
        return _preflight();
    }

    function mainnetConfig(
        address deployer,
        address finalAdmin,
        address guardian,
        address treasuryRecipient,
        address rewardAllocator
    ) public pure returns (GenesisConfig memory config) {
        _requireRole("DEPLOYER", deployer);
        _requireRole("FINAL_ADMIN", finalAdmin);
        _requireRole("TREASURY", treasuryRecipient);
        _requireRole("REWARD_ALLOCATOR", rewardAllocator);

        config = BurntatoDeploymentConfig.launchDefaults();
        config.deployer = deployer;
        config.finalAdmin = finalAdmin;
        config.guardian = guardian;
        config.treasuryRecipient = treasuryRecipient;
        config.rewardAllocator = rewardAllocator;
        config.initialWinnerReserve = BurntatoDeploymentConfig.defaultInitialWinnerReserve(config.protocol);
    }

    function _preflight()
        private
        returns (
            GenesisConfig memory config,
            CanonicalV4Dependencies memory dependencies,
            StaticsOperatorDependencies memory operatorDependencies
        )
    {
        if (block.chainid != CHAIN_ID) {
            revert InvalidMainnetChain(block.chainid);
        }

        dependencies = RobinhoodDeploymentConfig.load();
        operatorDependencies = StaticsOperatorDeploymentConfig.load();
        if (vm.envOr("BURNTATO_ANVIL_REHEARSAL", false)) {
            bytes memory automine = vm.rpc("anvil_getAutomine", "[]");
            if (automine.length == 0) revert InvalidMainnetAnvilRpc();
            uint256 currentBlock = _rpcBlockNumber();
            RobinhoodDeploymentConfig.validateAnvilFork(
                dependencies, currentBlock, _rpcBlockHash(dependencies.forkBlock)
            );
            StaticsOperatorDeploymentConfig.validateAnvilFork(
                operatorDependencies, currentBlock, _rpcBlockHash(operatorDependencies.finalizedBlock)
            );
        } else {
            RobinhoodDeploymentConfig.validate(dependencies);
            StaticsOperatorDeploymentConfig.validate(operatorDependencies);
        }

        config = mainnetConfig(
            vm.envAddress("BURNTATO_DEPLOYER"),
            vm.envAddress("BURNTATO_FINAL_ADMIN"),
            vm.envAddress("BURNTATO_GUARDIAN"),
            vm.envAddress("BURNTATO_TREASURY"),
            vm.envAddress("BURNTATO_REWARD_ALLOCATOR")
        );
        if (config.deployer.balance < config.initialWinnerReserve) {
            revert InsufficientDeployerBalance(config.initialWinnerReserve, config.deployer.balance);
        }
    }

    function _rpcBlockHash(uint256 blockNumber) private returns (bytes32) {
        string memory blockJson = vm.rpcJson(
            "eth_getBlockByNumber", string.concat("[\"", LibString.toMinimalHexString(blockNumber), "\",false]")
        );
        return vm.parseJsonBytes32(blockJson, ".hash");
    }

    function _rpcBlockNumber() private returns (uint256) {
        bytes memory encoded = vm.rpc("eth_blockNumber", "[]");
        uint256 blockNumber;
        for (uint256 index; index < encoded.length; ++index) {
            blockNumber = (blockNumber << 8) | uint8(encoded[index]);
        }
        return blockNumber;
    }

    function _writeDeployment(
        BurntatoDeployment memory deployment,
        GenesisConfig memory config,
        CanonicalV4Dependencies memory dependencies,
        StaticsOperatorDependencies memory operatorDependencies
    ) private {
        vm.createDir("artifacts/robinhood-mainnet", true);
        string memory object = "robinhoodMainnet";
        vm.serializeUint(object, "schemaVersion", 1);
        vm.serializeUint(object, "chainId", dependencies.chainId);
        vm.serializeUint(object, "canonicalManifestBlock", dependencies.forkBlock);
        vm.serializeBytes32(object, "canonicalManifestBlockHash", dependencies.forkBlockHash);
        vm.serializeUint(object, "staticsFinalizedBlock", operatorDependencies.finalizedBlock);
        vm.serializeBytes32(object, "staticsFinalizedBlockHash", operatorDependencies.finalizedBlockHash);
        vm.serializeString(object, "sourceCommit", vm.envString("BURNTATO_SOURCE_COMMIT"));
        vm.serializeAddress(object, "deployer", config.deployer);
        vm.serializeAddress(object, "diamond", deployment.diamond);
        vm.serializeAddress(object, "admin", deployment.admin);
        vm.serializeAddress(object, "guardian", config.guardian);
        vm.serializeAddress(object, "treasuryRecipient", config.treasuryRecipient);
        vm.serializeAddress(object, "rewardAllocator", config.rewardAllocator);
        vm.serializeAddress(object, "hook", deployment.hook);
        vm.serializeAddress(object, "hookDeployer", deployment.hookDeployer);
        vm.serializeAddress(object, "operatorRewardsRouter", deployment.operatorRewardsRouter);
        vm.serializeAddress(object, "operatorsNft", operatorDependencies.operatorsNft);
        vm.serializeAddress(object, "activationRegistry", operatorDependencies.activationRegistry);
        vm.serializeUint(object, "startingPrice", config.protocol.startingPrice);
        vm.serializeUint(object, "priceIncreaseBps", config.protocol.priceIncreaseBps);
        vm.serializeUint(object, "roundTimeout", config.protocol.roundTimeout);
        vm.serializeUint(object, "roundTimeoutDecay", config.protocol.roundTimeoutDecay);
        vm.serializeUint(object, "minimumRoundTimeout", config.protocol.minimumRoundTimeout);
        vm.serializeUint(object, "roundEmissionBudget", config.protocol.roundEmissionBudget);
        vm.serializeUint(object, "emissionStepBps", config.protocol.emissionStepBps);
        vm.serializeUint(object, "emissionVestingDuration", config.protocol.emissionVestingDuration);
        vm.serializeUint(object, "winnerBps", config.protocol.winnerBps);
        vm.serializeUint(object, "nextRoundWinnerBps", config.protocol.nextRoundWinnerBps);
        vm.serializeUint(object, "recoveryBps", config.protocol.recoveryBps);
        vm.serializeUint(object, "treasuryBps", config.protocol.treasuryBps);
        vm.serializeUint(object, "buybackBps", config.protocol.buybackBps);
        vm.serializeUint(object, "operatorPurchaseBps", config.protocol.operatorPurchaseBps);
        vm.serializeUint(object, "recoveryBurnBps", config.protocol.recoveryBurnBps);
        vm.serializeUint(object, "recoveryTreasuryBps", config.protocol.recoveryTreasuryBps);
        vm.serializeUint(object, "initialWinnerReserve", config.initialWinnerReserve);
        vm.serializeUint(object, "buybackMaxSpend", config.buyback.maxSpend);
        vm.serializeUint(object, "buybackCallerRewardBps", config.buyback.callerRewardBps);
        vm.serializeUint(object, "buybackDelayBlocks", config.buyback.delayBlocks);
        vm.serializeUint(object, "hookFeeBps", config.hookFeeBps);
        vm.serializeUint(object, "operatorRewardShareBps", config.operatorRewardShareBps);
        vm.serializeInt(object, "initialTick", config.initialTick);
        vm.serializeInt(object, "tickSpacing", config.tickSpacing);
        vm.serializeInt(object, "tickLower", config.tickLower);
        vm.serializeInt(object, "tickUpper", config.tickUpper);
        vm.serializeUint(object, "potatoSeed", config.potatoSeed);
        vm.serializeUint(object, "marketPositionCount", BurntatoLaunchCurves.positionCount());
        vm.serializeBytes32(object, "marketCurveHash", IMarket(deployment.diamond).marketCurveHash());
        vm.serializeAddress(object, "diamondCutFacet", deployment.diamondCutFacet);
        vm.serializeAddress(object, "diamondLoupeFacet", deployment.diamondLoupeFacet);
        vm.serializeAddress(object, "governanceFacet", deployment.governanceFacet);
        vm.serializeAddress(object, "marketFacet", deployment.marketFacet);
        vm.serializeAddress(object, "buybackFacet", deployment.buybackFacet);
        vm.serializeAddress(object, "potatoTokenFacet", deployment.potatoTokenFacet);
        vm.serializeAddress(object, "gameFacet", deployment.gameFacet);
        vm.serializeAddress(object, "recoveryFacet", deployment.recoveryFacet);
        vm.serializeAddress(object, "settlementFacet", deployment.settlementFacet);
        vm.serializeAddress(object, "claimsFacet", deployment.claimsFacet);
        vm.serializeAddress(object, "treasuryRewardsFacet", deployment.treasuryRewardsFacet);
        vm.serializeAddress(object, "foundationInit", deployment.foundationInit);
        vm.serializeAddress(object, "poolManager", deployment.poolManager);
        vm.serializeAddress(object, "positionDescriptor", deployment.positionDescriptor);
        vm.serializeAddress(object, "positionManager", deployment.positionManager);
        vm.serializeAddress(object, "quoter", deployment.quoter);
        vm.serializeAddress(object, "stateView", deployment.stateView);
        vm.serializeAddress(object, "reservesLens", deployment.reservesLens);
        vm.serializeAddress(object, "universalRouter", deployment.universalRouter);
        vm.serializeAddress(object, "permit2", deployment.permit2);
        vm.serializeAddress(object, "weth", deployment.weth9);
        _serializeRuntimeHashes(object, deployment, dependencies, operatorDependencies);
        string memory json = vm.serializeBytes32(object, "wethRuntimeCodeHash", dependencies.wethCodeHash);
        vm.writeJson(json, OUTPUT_PATH);
    }

    function _serializeRuntimeHashes(
        string memory object,
        BurntatoDeployment memory deployment,
        CanonicalV4Dependencies memory dependencies,
        StaticsOperatorDependencies memory operatorDependencies
    ) private {
        vm.serializeBytes32(object, "diamondRuntimeCodeHash", deployment.diamond.codehash);
        vm.serializeBytes32(object, "diamondCutFacetRuntimeCodeHash", deployment.diamondCutFacet.codehash);
        vm.serializeBytes32(object, "diamondLoupeFacetRuntimeCodeHash", deployment.diamondLoupeFacet.codehash);
        vm.serializeBytes32(object, "governanceFacetRuntimeCodeHash", deployment.governanceFacet.codehash);
        vm.serializeBytes32(object, "marketFacetRuntimeCodeHash", deployment.marketFacet.codehash);
        vm.serializeBytes32(object, "buybackFacetRuntimeCodeHash", deployment.buybackFacet.codehash);
        vm.serializeBytes32(object, "potatoTokenFacetRuntimeCodeHash", deployment.potatoTokenFacet.codehash);
        vm.serializeBytes32(object, "gameFacetRuntimeCodeHash", deployment.gameFacet.codehash);
        vm.serializeBytes32(object, "recoveryFacetRuntimeCodeHash", deployment.recoveryFacet.codehash);
        vm.serializeBytes32(object, "settlementFacetRuntimeCodeHash", deployment.settlementFacet.codehash);
        vm.serializeBytes32(object, "claimsFacetRuntimeCodeHash", deployment.claimsFacet.codehash);
        vm.serializeBytes32(object, "treasuryRewardsFacetRuntimeCodeHash", deployment.treasuryRewardsFacet.codehash);
        vm.serializeBytes32(object, "foundationInitRuntimeCodeHash", deployment.foundationInit.codehash);
        vm.serializeBytes32(object, "hookDeployerRuntimeCodeHash", deployment.hookDeployer.codehash);
        vm.serializeBytes32(object, "hookRuntimeCodeHash", deployment.hook.codehash);
        vm.serializeBytes32(object, "operatorRewardsRouterRuntimeCodeHash", deployment.operatorRewardsRouter.codehash);
        vm.serializeBytes32(object, "operatorsNftRuntimeCodeHash", operatorDependencies.operatorsNftCodeHash);
        vm.serializeBytes32(
            object, "activationRegistryRuntimeCodeHash", operatorDependencies.activationRegistryCodeHash
        );
        vm.serializeBytes32(object, "poolManagerRuntimeCodeHash", dependencies.poolManagerCodeHash);
        vm.serializeBytes32(object, "positionDescriptorRuntimeCodeHash", dependencies.positionDescriptorCodeHash);
        vm.serializeBytes32(object, "positionManagerRuntimeCodeHash", dependencies.positionManagerCodeHash);
        vm.serializeBytes32(object, "quoterRuntimeCodeHash", dependencies.quoterCodeHash);
        vm.serializeBytes32(object, "stateViewRuntimeCodeHash", dependencies.stateViewCodeHash);
        vm.serializeBytes32(object, "reservesLensRuntimeCodeHash", dependencies.reservesLensCodeHash);
        vm.serializeBytes32(object, "universalRouterRuntimeCodeHash", dependencies.universalRouterCodeHash);
        vm.serializeBytes32(object, "permit2RuntimeCodeHash", dependencies.permit2CodeHash);
    }

    function _requireRole(bytes32 role, address account) private pure {
        if (account == address(0)) revert InvalidMainnetRole(role, account);
    }
}
