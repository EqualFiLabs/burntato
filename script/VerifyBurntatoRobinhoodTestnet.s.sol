// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {BurntatoDeploymentVerifier} from "./BurntatoDeploymentVerifier.sol";
import {DeployBurntatoRobinhoodTestnet} from "./DeployBurntatoRobinhoodTestnet.s.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract VerifyBurntatoRobinhoodTestnet is Script {
    string private constant OUTPUT_PATH = "artifacts/robinhood-testnet/deployment.json";

    function run() external returns (bool verified) {
        string memory json = vm.readFile(OUTPUT_PATH);
        address deployer = vm.parseJsonAddress(json, ".deployer");
        GenesisConfig memory config = (new DeployBurntatoRobinhoodTestnet()).testnetConfig(deployer);
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        BurntatoDeployment memory deployment = _readDeployment(json);

        verified =
            (new BurntatoDeploymentVerifier()).verifyCanonical(config, deployment, dependencies, operatorDependencies);
        console2.log("Burntato Robinhood testnet deployment verified", verified);
    }

    function _readDeployment(string memory json) private pure returns (BurntatoDeployment memory deployment) {
        deployment.diamond = vm.parseJsonAddress(json, ".diamond");
        deployment.timelock = vm.parseJsonAddress(json, ".timelock");
        deployment.hook = vm.parseJsonAddress(json, ".hook");
        deployment.hookDeployer = vm.parseJsonAddress(json, ".hookDeployer");
        deployment.operatorRewardsRouter = vm.parseJsonAddress(json, ".operatorRewardsRouter");
        deployment.diamondCutFacet = vm.parseJsonAddress(json, ".diamondCutFacet");
        deployment.diamondLoupeFacet = vm.parseJsonAddress(json, ".diamondLoupeFacet");
        deployment.governanceFacet = vm.parseJsonAddress(json, ".governanceFacet");
        deployment.marketFacet = vm.parseJsonAddress(json, ".marketFacet");
        deployment.buybackFacet = vm.parseJsonAddress(json, ".buybackFacet");
        deployment.potatoTokenFacet = vm.parseJsonAddress(json, ".potatoTokenFacet");
        deployment.gameFacet = vm.parseJsonAddress(json, ".gameFacet");
        deployment.recoveryFacet = vm.parseJsonAddress(json, ".recoveryFacet");
        deployment.settlementFacet = vm.parseJsonAddress(json, ".settlementFacet");
        deployment.claimsFacet = vm.parseJsonAddress(json, ".claimsFacet");
        deployment.treasuryRewardsFacet = vm.parseJsonAddress(json, ".treasuryRewardsFacet");
        deployment.foundationInit = vm.parseJsonAddress(json, ".foundationInit");
        deployment.poolManager = vm.parseJsonAddress(json, ".poolManager");
        deployment.positionDescriptor = vm.parseJsonAddress(json, ".positionDescriptor");
        deployment.positionManager = vm.parseJsonAddress(json, ".positionManager");
        deployment.quoter = vm.parseJsonAddress(json, ".quoter");
        deployment.stateView = vm.parseJsonAddress(json, ".stateView");
        deployment.reservesLens = vm.parseJsonAddress(json, ".reservesLens");
        deployment.universalRouter = vm.parseJsonAddress(json, ".universalRouter");
        deployment.permit2 = vm.parseJsonAddress(json, ".permit2");
        deployment.weth9 = vm.parseJsonAddress(json, ".weth");
    }
}
