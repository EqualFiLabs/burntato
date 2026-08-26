// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DeployBurntato} from "./DeployBurntato.s.sol";
import {BurntatoDeployment, CanonicalV4Dependencies, GenesisConfig} from "./DeploymentTypes.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";

contract DeployBurntatoLocalFork is DeployBurntato {
    error InvalidLocalForkChain(uint256 actualChainId);
    error InvalidLocalForkRpc();
    error InvalidLocalForkBlock(uint256 expected, uint256 actual);
    error InvalidLocalForkBlockHash(bytes32 expected, bytes32 actual);

    string internal constant OUTPUT_PATH = "artifacts/robinhood-local/deployment.json";

    function runLocalFork() external returns (BurntatoDeployment memory deployment) {
        CanonicalV4Dependencies memory dependencies = _localForkPreflight();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        GenesisConfig memory config = _environmentConfig();
        config.deployer = deployer;

        vm.startBroadcast(privateKey);
        deployment = deployWithDependencies(config, deployer, dependencies);
        vm.stopBroadcast();

        _writeDeployment(deployment, dependencies);
        _log(deployment);
    }

    function preflightLocalFork() external returns (CanonicalV4Dependencies memory dependencies) {
        return _localForkPreflight();
    }

    function _localForkPreflight() internal virtual returns (CanonicalV4Dependencies memory dependencies) {
        if (block.chainid != RobinhoodDeploymentConfig.ROBINHOOD_MAINNET_CHAIN_ID) {
            revert InvalidLocalForkChain(block.chainid);
        }
        bytes memory nodeInfo = vm.rpc("anvil_nodeInfo", "[]");
        if (nodeInfo.length == 0) revert InvalidLocalForkRpc();

        dependencies = RobinhoodDeploymentConfig.load();
        string memory nodeInfoJson = string(nodeInfo);
        uint256 forkBlock = vm.parseJsonUint(nodeInfoJson, ".forkConfig.forkBlockNumber");
        if (forkBlock != dependencies.forkBlock) {
            revert InvalidLocalForkBlock(dependencies.forkBlock, forkBlock);
        }
        bytes memory pinnedBlock = vm.rpc("eth_getBlockByNumber", "[\"0x2b23aa7\",false]");
        bytes32 actualBlockHash = vm.parseJsonBytes32(string(pinnedBlock), ".hash");
        if (actualBlockHash != dependencies.forkBlockHash) {
            revert InvalidLocalForkBlockHash(dependencies.forkBlockHash, actualBlockHash);
        }
        RobinhoodDeploymentConfig.validate(dependencies);
    }

    function _writeDeployment(BurntatoDeployment memory deployment, CanonicalV4Dependencies memory dependencies)
        internal
    {
        string memory object = "robinhoodLocal";
        vm.serializeUint(object, "chainId", dependencies.chainId);
        vm.serializeUint(object, "forkBlock", dependencies.forkBlock);
        vm.serializeAddress(object, "diamond", deployment.diamond);
        vm.serializeAddress(object, "timelock", deployment.timelock);
        vm.serializeAddress(object, "hook", deployment.hook);
        vm.serializeAddress(object, "hookDeployer", deployment.hookDeployer);
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
}
