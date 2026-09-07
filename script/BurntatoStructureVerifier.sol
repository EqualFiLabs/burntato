// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {BurntatoDeployment} from "./DeploymentTypes.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";
import {BurntatoSourceCodeHashes} from "./libraries/BurntatoSourceCodeHashes.sol";

contract BurntatoStructureVerifier {
    error VerificationFailed(bytes32 check);

    function verify(BurntatoDeployment memory deployment) external view returns (bool) {
        _verifyCode(deployment);
        _verifySelectors(deployment);
        return true;
    }

    function _verifyCode(BurntatoDeployment memory deployment) private view {
        _verifyCompiledCode(
            deployment.diamond, deployment.codeHashes.diamond, BurntatoSourceCodeHashes.DIAMOND, "DIAMOND_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.diamondCutFacet,
            deployment.codeHashes.diamondCutFacet,
            BurntatoSourceCodeHashes.DIAMOND_CUT_FACET,
            "CUT_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.diamondLoupeFacet,
            deployment.codeHashes.diamondLoupeFacet,
            BurntatoSourceCodeHashes.DIAMOND_LOUPE_FACET,
            "LOUPE_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.governanceFacet,
            deployment.codeHashes.governanceFacet,
            BurntatoSourceCodeHashes.GOVERNANCE_FACET,
            "GOVERNANCE_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.marketFacet,
            deployment.codeHashes.marketFacet,
            BurntatoSourceCodeHashes.MARKET_FACET,
            "MARKET_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.buybackFacet,
            deployment.codeHashes.buybackFacet,
            BurntatoSourceCodeHashes.BUYBACK_FACET,
            "BUYBACK_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.potatoTokenFacet,
            deployment.codeHashes.potatoTokenFacet,
            BurntatoSourceCodeHashes.POTATO_TOKEN_FACET,
            "TOKEN_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.gameFacet,
            deployment.codeHashes.gameFacet,
            BurntatoSourceCodeHashes.GAME_FACET,
            "GAME_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.recoveryFacet,
            deployment.codeHashes.recoveryFacet,
            BurntatoSourceCodeHashes.RECOVERY_FACET,
            "RECOVERY_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.settlementFacet,
            deployment.codeHashes.settlementFacet,
            BurntatoSourceCodeHashes.SETTLEMENT_FACET,
            "SETTLEMENT_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.claimsFacet,
            deployment.codeHashes.claimsFacet,
            BurntatoSourceCodeHashes.CLAIMS_FACET,
            "CLAIMS_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.treasuryRewardsFacet,
            deployment.codeHashes.treasuryRewardsFacet,
            BurntatoSourceCodeHashes.TREASURY_REWARDS_FACET,
            "REWARDS_FACET_CODE_HASH"
        );
        _verifyCompiledCode(
            deployment.foundationInit,
            deployment.codeHashes.foundationInit,
            BurntatoSourceCodeHashes.FOUNDATION_INIT,
            "FOUNDATION_INIT_CODE_HASH"
        );
        _verifyManifestCode(deployment.hookDeployer, deployment.codeHashes.hookDeployer, "HOOK_DEPLOYER_CODE_HASH");
        _verifyManifestCode(deployment.hook, deployment.codeHashes.hook, "HOOK_CODE_HASH");
        _check(deployment.poolManager.code.length != 0, "POOL_MANAGER_CODE");
        _check(deployment.positionManager.code.length != 0, "POSITION_MANAGER_CODE");
        _check(deployment.permit2.code.length != 0, "PERMIT2_CODE");
        if (deployment.operatorRewardsRouter != address(0)) {
            _verifyManifestCode(
                deployment.operatorRewardsRouter,
                deployment.codeHashes.operatorRewardsRouter,
                "OPERATOR_ROUTER_CODE_HASH"
            );
        } else {
            _check(deployment.codeHashes.operatorRewardsRouter == bytes32(0), "OPERATOR_ROUTER_HASH_DISABLED");
        }
    }

    function _verifySelectors(BurntatoDeployment memory deployment) private view {
        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        _check(loupe.facetAddresses().length == 11, "FACET_COUNT");
        _verifyGroup(loupe, deployment.diamondCutFacet, BurntatoSelectors.diamondCut());
        _verifyGroup(loupe, deployment.diamondLoupeFacet, BurntatoSelectors.loupe());
        _verifyGroup(loupe, deployment.governanceFacet, BurntatoSelectors.governance());
        _verifyGroup(loupe, deployment.marketFacet, BurntatoSelectors.market());
        _verifyGroup(loupe, deployment.buybackFacet, BurntatoSelectors.buyback());
        _verifyGroup(loupe, deployment.potatoTokenFacet, BurntatoSelectors.token());
        _verifyGroup(loupe, deployment.gameFacet, BurntatoSelectors.game());
        _verifyGroup(loupe, deployment.recoveryFacet, BurntatoSelectors.recovery());
        _verifyGroup(loupe, deployment.settlementFacet, BurntatoSelectors.settlement());
        _verifyGroup(loupe, deployment.claimsFacet, BurntatoSelectors.claims());
        _verifyGroup(loupe, deployment.treasuryRewardsFacet, BurntatoSelectors.treasuryRewards());
    }

    function _verifyCompiledCode(address target, bytes32 manifestHash, bytes32 compiledHash, bytes32 check)
        private
        view
    {
        _check(manifestHash == compiledHash, check);
        _check(target.codehash == manifestHash, check);
    }

    function _verifyManifestCode(address target, bytes32 manifestHash, bytes32 check) private view {
        _check(manifestHash != bytes32(0), check);
        _check(target.codehash == manifestHash, check);
    }

    function _verifyGroup(IDiamondLoupe loupe, address expectedFacet, bytes4[] memory selectors) private view {
        _check(expectedFacet != address(0) && expectedFacet.code.length != 0, "FACET_CODE");
        for (uint256 i; i < selectors.length; ++i) {
            _check(loupe.facetAddress(selectors[i]) == expectedFacet, "SELECTOR_ROUTING");
        }
        _check(loupe.facetFunctionSelectors(expectedFacet).length == selectors.length, "FACET_SELECTOR_COUNT");
    }

    function _check(bool condition, bytes32 check) private pure {
        if (!condition) revert VerificationFailed(check);
    }
}
