// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DeployBurntato} from "./DeployBurntato.s.sol";
import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract DeployBurntatoLocalFork is DeployBurntato {
    error InvalidLocalForkChain(uint256 actualChainId);
    error InvalidLocalForkRpc();
    error InvalidLocalForkBlock(uint256 expected, uint256 actual);
    error InvalidLocalForkBlockHash(bytes32 expected, bytes32 actual);
    error InvalidOperatorRewardShare();

    string internal constant OUTPUT_PATH = "artifacts/robinhood-local/deployment.json";

    function runLocalFork() external returns (BurntatoDeployment memory deployment) {
        CanonicalV4Dependencies memory dependencies = _localForkPreflight(true);
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        GenesisConfig memory config = _environmentConfig();
        config.deployer = deployer;
        config.operatorRewardShareBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envUint("BURNTATO_OPERATOR_REWARD_SHARE_BPS"));
        if (config.operatorRewardShareBps == 0) revert InvalidOperatorRewardShare();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();

        vm.startBroadcast(privateKey);
        deployment = deployWithDependencies(config, deployer, dependencies, operatorDependencies);
        vm.stopBroadcast();

        _writeDeployment(deployment, dependencies);
        _log(deployment);
    }

    function preflightLocalFork() external returns (CanonicalV4Dependencies memory dependencies) {
        return _localForkPreflight(true);
    }

    function preflightDeployedLocalFork() external returns (CanonicalV4Dependencies memory dependencies) {
        return _localForkPreflight(false);
    }

    function _localForkPreflight(bool requireExactBlock)
        internal
        virtual
        returns (CanonicalV4Dependencies memory dependencies)
    {
        if (block.chainid != RobinhoodDeploymentConfig.ROBINHOOD_MAINNET_CHAIN_ID) {
            revert InvalidLocalForkChain(block.chainid);
        }
        bytes memory nodeInfo = vm.rpc("anvil_nodeInfo", "[]");
        if (nodeInfo.length == 0) revert InvalidLocalForkRpc();

        dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        if (
            block.number < operatorDependencies.finalizedBlock
                || (requireExactBlock && block.number != operatorDependencies.finalizedBlock)
        ) {
            revert InvalidLocalForkBlock(operatorDependencies.finalizedBlock, block.number);
        }
        string memory pinnedBlock = vm.rpcJson("eth_getBlockByNumber", "[\"0x2d7b367\",false]");
        bytes32 actualBlockHash = vm.parseJsonBytes32(pinnedBlock, ".hash");
        if (actualBlockHash != operatorDependencies.finalizedBlockHash) {
            revert InvalidLocalForkBlockHash(operatorDependencies.finalizedBlockHash, actualBlockHash);
        }
        RobinhoodDeploymentConfig.validate(dependencies);
        StaticsOperatorDeploymentConfig.validate(operatorDependencies);
    }

    function _writeDeployment(BurntatoDeployment memory deployment, CanonicalV4Dependencies memory dependencies)
        internal
    {
        vm.createDir("artifacts/robinhood-local", true);
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        string memory object = "robinhoodLocal";
        vm.serializeUint(object, "chainId", dependencies.chainId);
        vm.serializeUint(object, "forkBlock", operatorDependencies.finalizedBlock);
        vm.serializeAddress(object, "diamond", deployment.diamond);
        vm.serializeAddress(object, "timelock", deployment.timelock);
        vm.serializeAddress(object, "hook", deployment.hook);
        vm.serializeAddress(object, "hookDeployer", deployment.hookDeployer);
        vm.serializeAddress(object, "operatorRewardsRouter", deployment.operatorRewardsRouter);
        vm.serializeUint(object, "operatorRewardShareBps", _operatorRewardShareBps(deployment));
        vm.serializeAddress(object, "operatorsNft", operatorDependencies.operatorsNft);
        vm.serializeAddress(object, "activationRegistry", operatorDependencies.activationRegistry);
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
        string memory json = vm.serializeAddress(object, "weth", deployment.weth9);
        vm.writeJson(json, OUTPUT_PATH);
    }

    function _operatorRewardShareBps(BurntatoDeployment memory deployment) private view returns (uint256) {
        return BurntatoSwapFeeHook(payable(deployment.hook)).operatorRewardShareBps();
    }
}
