// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {BurntatoDeploymentVerifier} from "./BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {DeployBurntatoLocalFork} from "./DeployBurntatoLocalFork.s.sol";
import {BurntatoDeployment, CanonicalV4Dependencies, GenesisConfig} from "./DeploymentTypes.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";

contract VerifyBurntatoLocalFork is Script {
    string internal constant OUTPUT_PATH = "artifacts/robinhood-local/deployment.json";

    function run() external returns (bool verified) {
        CanonicalV4Dependencies memory dependencies = (new DeployBurntatoLocalFork()).preflightLocalFork();
        DeployBurntato configLoader = new DeployBurntato();
        GenesisConfig memory config = configLoader.localDefaults();
        BurntatoDeployment memory deployment = _readDeployment(dependencies);
        _loadFacets(deployment);

        verified = (new BurntatoDeploymentVerifier()).verifyCanonical(config, deployment, dependencies);
        console2.log("Burntato local fork deployment verified", verified);
    }

    function _readDeployment(CanonicalV4Dependencies memory dependencies)
        private
        view
        returns (BurntatoDeployment memory deployment)
    {
        string memory json = vm.readFile(OUTPUT_PATH);
        deployment.diamond = vm.parseJsonAddress(json, ".diamond");
        deployment.timelock = vm.parseJsonAddress(json, ".timelock");
        deployment.hook = vm.parseJsonAddress(json, ".hook");
        deployment.hookDeployer = vm.parseJsonAddress(json, ".hookDeployer");
        deployment.foundationInit = vm.parseJsonAddress(json, ".foundationInit");
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

    function _loadFacets(BurntatoDeployment memory deployment) private view {
        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        deployment.diamondCutFacet = loupe.facetAddress(BurntatoSelectors.diamondCut()[0]);
        deployment.diamondLoupeFacet = loupe.facetAddress(BurntatoSelectors.loupe()[0]);
        deployment.governanceFacet = loupe.facetAddress(BurntatoSelectors.governance()[0]);
        deployment.marketFacet = loupe.facetAddress(BurntatoSelectors.market()[0]);
        deployment.buybackFacet = loupe.facetAddress(BurntatoSelectors.buyback()[0]);
        deployment.potatoTokenFacet = loupe.facetAddress(BurntatoSelectors.token()[0]);
        deployment.gameFacet = loupe.facetAddress(BurntatoSelectors.game()[0]);
        deployment.recoveryFacet = loupe.facetAddress(BurntatoSelectors.recovery()[0]);
        deployment.settlementFacet = loupe.facetAddress(BurntatoSelectors.settlement()[0]);
        deployment.claimsFacet = loupe.facetAddress(BurntatoSelectors.claims()[0]);
        deployment.treasuryRewardsFacet = loupe.facetAddress(BurntatoSelectors.treasuryRewards()[0]);
    }
}
