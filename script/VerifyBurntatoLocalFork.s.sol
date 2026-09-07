// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {BurntatoDeploymentVerifier} from "./BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {DeployBurntatoLocalFork} from "./DeployBurntatoLocalFork.s.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract VerifyBurntatoLocalFork is Script {
    string internal constant OUTPUT_PATH = "artifacts/robinhood-local/deployment.json";

    function run() external returns (bool verified) {
        CanonicalV4Dependencies memory dependencies = (new DeployBurntatoLocalFork()).preflightDeployedLocalFork();
        DeployBurntato configLoader = new DeployBurntato();
        GenesisConfig memory config = configLoader.environmentConfig();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        BurntatoDeployment memory deployment = _readDeployment(dependencies);
        verified =
            (new BurntatoDeploymentVerifier()).verifyCanonical(config, deployment, dependencies, operatorDependencies);
        console2.log("Burntato local fork deployment verified", verified);
    }

    function _readDeployment(CanonicalV4Dependencies memory dependencies)
        private
        view
        returns (BurntatoDeployment memory deployment)
    {
        string memory json = vm.readFile(OUTPUT_PATH);
        deployment.diamond = vm.parseJsonAddress(json, ".diamond");
        deployment.admin = vm.parseJsonAddress(json, ".admin");
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
        _readCodeHashes(json, deployment);
        deployment.poolManager = dependencies.poolManager;
        deployment.positionDescriptor = dependencies.positionDescriptor;
        deployment.positionManager = dependencies.positionManager;
        deployment.quoter = dependencies.quoter;
        deployment.stateView = dependencies.stateView;
        deployment.reservesLens = dependencies.reservesLens;
        deployment.universalRouter = dependencies.universalRouter;
        deployment.permit2 = dependencies.permit2;
        deployment.weth9 = dependencies.weth;
    }

    function _readCodeHashes(string memory json, BurntatoDeployment memory deployment) private pure {
        deployment.codeHashes.diamond = vm.parseJsonBytes32(json, ".diamondCodeHash");
        deployment.codeHashes.diamondCutFacet = vm.parseJsonBytes32(json, ".diamondCutFacetCodeHash");
        deployment.codeHashes.diamondLoupeFacet = vm.parseJsonBytes32(json, ".diamondLoupeFacetCodeHash");
        deployment.codeHashes.governanceFacet = vm.parseJsonBytes32(json, ".governanceFacetCodeHash");
        deployment.codeHashes.marketFacet = vm.parseJsonBytes32(json, ".marketFacetCodeHash");
        deployment.codeHashes.buybackFacet = vm.parseJsonBytes32(json, ".buybackFacetCodeHash");
        deployment.codeHashes.potatoTokenFacet = vm.parseJsonBytes32(json, ".potatoTokenFacetCodeHash");
        deployment.codeHashes.gameFacet = vm.parseJsonBytes32(json, ".gameFacetCodeHash");
        deployment.codeHashes.recoveryFacet = vm.parseJsonBytes32(json, ".recoveryFacetCodeHash");
        deployment.codeHashes.settlementFacet = vm.parseJsonBytes32(json, ".settlementFacetCodeHash");
        deployment.codeHashes.claimsFacet = vm.parseJsonBytes32(json, ".claimsFacetCodeHash");
        deployment.codeHashes.treasuryRewardsFacet = vm.parseJsonBytes32(json, ".treasuryRewardsFacetCodeHash");
        deployment.codeHashes.foundationInit = vm.parseJsonBytes32(json, ".foundationInitCodeHash");
        deployment.codeHashes.hookDeployer = vm.parseJsonBytes32(json, ".hookDeployerCodeHash");
        deployment.codeHashes.hook = vm.parseJsonBytes32(json, ".hookCodeHash");
        deployment.codeHashes.operatorRewardsRouter = vm.parseJsonBytes32(json, ".operatorRewardsRouterCodeHash");
    }
}
