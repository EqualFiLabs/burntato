// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {BurntatoOperatorRewardsRouter} from "../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {BurntatoDeployment} from "./DeploymentTypes.sol";
import {BurntatoHookDeployer} from "./helpers/BurntatoHookDeployer.sol";
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
        _verifyHookDeployerCode(deployment);
        _verifyHookCode(deployment);
        _check(deployment.poolManager.code.length != 0, "POOL_MANAGER_CODE");
        _check(deployment.positionManager.code.length != 0, "POSITION_MANAGER_CODE");
        _check(deployment.permit2.code.length != 0, "PERMIT2_CODE");
        if (deployment.operatorRewardsRouter != address(0)) {
            _verifyOperatorRouterCode(deployment);
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

    function _verifyHookDeployerCode(BurntatoDeployment memory deployment) private view {
        bytes32 check = "HOOK_DEPLOYER_CODE_HASH";
        bytes memory runtime = _manifestRuntime(deployment.hookDeployer, deployment.codeHashes.hookDeployer, check);
        bytes32 authorizedDeployer =
            bytes32(uint256(uint160(BurntatoHookDeployer(deployment.hookDeployer).authorizedDeployer())));
        _normalizeImmutable(runtime, 223, authorizedDeployer, check);
        _normalizeImmutable(runtime, 454, authorizedDeployer, check);
        _check(keccak256(runtime) == BurntatoSourceCodeHashes.HOOK_DEPLOYER_NORMALIZED, check);
    }

    function _verifyHookCode(BurntatoDeployment memory deployment) private view {
        bytes32 check = "HOOK_CODE_HASH";
        bytes memory runtime = _manifestRuntime(deployment.hook, deployment.codeHashes.hook, check);
        BurntatoSwapFeeHook hook = BurntatoSwapFeeHook(payable(deployment.hook));
        bytes32 poolManager = bytes32(uint256(uint160(address(hook.poolManager()))));
        bytes32 token = bytes32(uint256(uint160(hook.token())));
        bytes32 tickSpacing = bytes32(uint256(uint24(hook.tickSpacing())));

        _normalizeImmutable(runtime, 664, poolManager, check);
        _normalizeImmutable(runtime, 788, poolManager, check);
        _normalizeImmutable(runtime, 1873, poolManager, check);
        _normalizeImmutable(runtime, 2545, poolManager, check);
        _normalizeImmutable(runtime, 2671, poolManager, check);
        _normalizeImmutable(runtime, 3412, poolManager, check);
        _normalizeImmutable(runtime, 3714, poolManager, check);
        _normalizeImmutable(runtime, 3794, poolManager, check);
        _normalizeImmutable(runtime, 3963, poolManager, check);
        _normalizeImmutable(runtime, 4198, poolManager, check);
        _normalizeImmutable(runtime, 4385, poolManager, check);
        _normalizeImmutable(runtime, 6732, poolManager, check);
        _normalizeImmutable(runtime, 7132, poolManager, check);

        _normalizeImmutable(runtime, 453, token, check);
        _normalizeImmutable(runtime, 905, token, check);
        _normalizeImmutable(runtime, 1789, token, check);
        _normalizeImmutable(runtime, 2743, token, check);
        _normalizeImmutable(runtime, 3173, token, check);
        _normalizeImmutable(runtime, 3999, token, check);
        _normalizeImmutable(runtime, 5773, token, check);
        _normalizeImmutable(runtime, 6626, token, check);
        _normalizeImmutable(runtime, 7042, token, check);

        _normalizeImmutable(runtime, 1665, tickSpacing, check);
        _normalizeImmutable(runtime, 1944, tickSpacing, check);
        _normalizeImmutable(runtime, 6489, tickSpacing, check);
        _check(keccak256(runtime) == BurntatoSourceCodeHashes.HOOK_NORMALIZED, check);
    }

    function _verifyOperatorRouterCode(BurntatoDeployment memory deployment) private view {
        bytes32 check = "OPERATOR_ROUTER_CODE_HASH";
        bytes memory runtime =
            _manifestRuntime(deployment.operatorRewardsRouter, deployment.codeHashes.operatorRewardsRouter, check);
        BurntatoOperatorRewardsRouter router = BurntatoOperatorRewardsRouter(payable(deployment.operatorRewardsRouter));
        bytes32 burntato = bytes32(uint256(uint160(router.burntato())));
        bytes32 operators = bytes32(uint256(uint160(address(router.operators()))));
        bytes32 activationRegistry = bytes32(uint256(uint160(address(router.activationRegistry()))));

        _normalizeImmutable(runtime, 2126, burntato, check);
        _normalizeImmutable(runtime, 2429, burntato, check);

        _normalizeImmutable(runtime, 503, operators, check);
        _normalizeImmutable(runtime, 1304, operators, check);
        _normalizeImmutable(runtime, 1637, operators, check);
        _normalizeImmutable(runtime, 3103, operators, check);
        _normalizeImmutable(runtime, 3677, operators, check);

        _normalizeImmutable(runtime, 646, activationRegistry, check);
        _normalizeImmutable(runtime, 1012, activationRegistry, check);
        _normalizeImmutable(runtime, 1816, activationRegistry, check);
        _normalizeImmutable(runtime, 3190, activationRegistry, check);
        _normalizeImmutable(runtime, 4431, activationRegistry, check);
        _check(keccak256(runtime) == BurntatoSourceCodeHashes.OPERATOR_ROUTER_NORMALIZED, check);
    }

    function _manifestRuntime(address target, bytes32 manifestHash, bytes32 check)
        private
        view
        returns (bytes memory runtime)
    {
        _check(target.code.length != 0 && manifestHash != bytes32(0), check);
        _check(target.codehash == manifestHash, check);
        runtime = target.code;
    }

    function _normalizeImmutable(bytes memory runtime, uint256 offset, bytes32 expected, bytes32 check) private pure {
        _check(offset + 32 <= runtime.length, check);
        bytes32 actual;
        assembly ("memory-safe") {
            actual := mload(add(add(runtime, 0x20), offset))
            mstore(add(add(runtime, 0x20), offset), 0)
        }
        _check(actual == expected, check);
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
