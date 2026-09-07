// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DeployBurntato} from "./DeployBurntato.s.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract DeployBurntatoRobinhoodTestnet is DeployBurntato {
    uint256 public constant CHAIN_ID = 46_630;
    string public constant OUTPUT_PATH = "artifacts/robinhood-testnet/deployment.json";

    error InvalidTestnetChain(uint256 actualChainId);

    function run() external override returns (BurntatoDeployment memory deployment) {
        if (block.chainid != CHAIN_ID) revert InvalidTestnetChain(block.chainid);
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        GenesisConfig memory config = testnetConfig(deployer);
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();

        vm.startBroadcast(privateKey);
        deployment = deployWithDependencies(config, deployer, dependencies, operatorDependencies);
        vm.stopBroadcast();

        _writeDeployment(deployment, config, dependencies, operatorDependencies);
        _log(deployment);
    }

    function testnetConfig(address deployer) public pure returns (GenesisConfig memory config) {
        config = BurntatoDeploymentConfig.localDefaults();
        config.deployer = deployer;
        config.finalAdmin = deployer;
        config.guardian = deployer;
        config.treasuryRecipient = deployer;
        config.rewardAllocator = deployer;
        config.protocol.winnerBps = 2_500;
        config.protocol.recoveryBps = 3_000;
        config.protocol.treasuryBps = 2_000;
        config.protocol.buybackBps = 1_000;
        config.protocol.operatorPurchaseBps = 1_500;
        config.hookFeeBps = 100;
        config.operatorRewardShareBps = 4_000;
    }

    function _writeDeployment(
        BurntatoDeployment memory deployment,
        GenesisConfig memory config,
        CanonicalV4Dependencies memory dependencies,
        StaticsOperatorDependencies memory operatorDependencies
    ) private {
        vm.createDir("artifacts/robinhood-testnet", true);
        string memory object = "robinhoodTestnet";
        vm.serializeUint(object, "schemaVersion", 1);
        vm.serializeUint(object, "chainId", dependencies.chainId);
        vm.serializeUint(object, "deploymentBlock", block.number);
        vm.serializeAddress(object, "deployer", config.deployer);
        vm.serializeAddress(object, "diamond", deployment.diamond);
        vm.serializeAddress(object, "admin", deployment.admin);
        vm.serializeAddress(object, "hook", deployment.hook);
        vm.serializeAddress(object, "hookDeployer", deployment.hookDeployer);
        vm.serializeAddress(object, "operatorRewardsRouter", deployment.operatorRewardsRouter);
        vm.serializeAddress(object, "operatorsNft", operatorDependencies.operatorsNft);
        vm.serializeAddress(object, "activationRegistry", operatorDependencies.activationRegistry);
        vm.serializeUint(object, "winnerBps", config.protocol.winnerBps);
        vm.serializeUint(object, "recoveryBps", config.protocol.recoveryBps);
        vm.serializeUint(object, "treasuryBps", config.protocol.treasuryBps);
        vm.serializeUint(object, "buybackBps", config.protocol.buybackBps);
        vm.serializeUint(object, "operatorPurchaseBps", config.protocol.operatorPurchaseBps);
        vm.serializeUint(object, "hookFeeBps", config.hookFeeBps);
        vm.serializeUint(object, "operatorRewardShareBps", config.operatorRewardShareBps);
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
        _serializeCodeHashes(object, deployment);
        vm.serializeAddress(object, "poolManager", deployment.poolManager);
        vm.serializeAddress(object, "positionDescriptor", deployment.positionDescriptor);
        vm.serializeAddress(object, "positionManager", deployment.positionManager);
        vm.serializeAddress(object, "quoter", deployment.quoter);
        vm.serializeAddress(object, "stateView", deployment.stateView);
        vm.serializeAddress(object, "reservesLens", deployment.reservesLens);
        vm.serializeAddress(object, "universalRouter", deployment.universalRouter);
        vm.serializeAddress(object, "permit2", deployment.permit2);
        string memory json = vm.serializeAddress(object, "weth", deployment.weth9);
        vm.writeJson(json, OUTPUT_PATH);
    }

    function _serializeCodeHashes(string memory object, BurntatoDeployment memory deployment) private {
        vm.serializeBytes32(object, "diamondCodeHash", deployment.codeHashes.diamond);
        vm.serializeBytes32(object, "diamondCutFacetCodeHash", deployment.codeHashes.diamondCutFacet);
        vm.serializeBytes32(object, "diamondLoupeFacetCodeHash", deployment.codeHashes.diamondLoupeFacet);
        vm.serializeBytes32(object, "governanceFacetCodeHash", deployment.codeHashes.governanceFacet);
        vm.serializeBytes32(object, "marketFacetCodeHash", deployment.codeHashes.marketFacet);
        vm.serializeBytes32(object, "buybackFacetCodeHash", deployment.codeHashes.buybackFacet);
        vm.serializeBytes32(object, "potatoTokenFacetCodeHash", deployment.codeHashes.potatoTokenFacet);
        vm.serializeBytes32(object, "gameFacetCodeHash", deployment.codeHashes.gameFacet);
        vm.serializeBytes32(object, "recoveryFacetCodeHash", deployment.codeHashes.recoveryFacet);
        vm.serializeBytes32(object, "settlementFacetCodeHash", deployment.codeHashes.settlementFacet);
        vm.serializeBytes32(object, "claimsFacetCodeHash", deployment.codeHashes.claimsFacet);
        vm.serializeBytes32(object, "treasuryRewardsFacetCodeHash", deployment.codeHashes.treasuryRewardsFacet);
        vm.serializeBytes32(object, "foundationInitCodeHash", deployment.codeHashes.foundationInit);
        vm.serializeBytes32(object, "hookDeployerCodeHash", deployment.codeHashes.hookDeployer);
        vm.serializeBytes32(object, "hookCodeHash", deployment.codeHashes.hook);
        vm.serializeBytes32(object, "operatorRewardsRouterCodeHash", deployment.codeHashes.operatorRewardsRouter);
    }
}
