// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

contract FormalFacetV1 {
    function formalValue() external pure returns (uint256) {
        return 1;
    }
}

contract FormalFacetV2 {
    function formalValue() external pure returns (uint256) {
        return 2;
    }
}

contract RevertingFormalInitializer {
    function initialize() external pure {
        revert Errors.InvalidProtocolConfig();
    }
}

contract BurntatoDiamondProperties is Test {
    address private constant TREASURY = address(0xBEEF);

    BurntatoDiamond private diamond;
    IDiamondCut private cutter;
    IDiamondLoupe private loupe;
    IGovernance private governance;
    FormalFacetV1 private facetV1;
    FormalFacetV2 private facetV2;
    FoundationInit private foundation;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));
        cutter = IDiamondCut(address(diamond));

        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        GovernanceFacet governanceFacet = new GovernanceFacet();
        facetV1 = new FormalFacetV1();
        facetV2 = new FormalFacetV2();
        foundation = new FoundationInit();

        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = FacetCut(address(loupeFacet), FacetCutAction.Add, BurntatoSelectors.loupe());
        cuts[1] = FacetCut(address(governanceFacet), FacetCutAction.Add, BurntatoSelectors.governance());
        cuts[2] = FacetCut(address(facetV1), FacetCutAction.Add, _single(FormalFacetV1.formalValue.selector));
        cutter.diamondCut(
            cuts,
            address(foundation),
            abi.encodeCall(FoundationInit.initialize, (_config(), TREASURY, address(0), 1 ether, 0))
        );

        loupe = IDiamondLoupe(address(diamond));
        governance = IGovernance(address(diamond));
    }

    function check_unauthorizedCutCannotChangeRouting(address caller) public {
        vm.assume(caller != address(0) && caller != address(this));
        address beforeFacet = loupe.facetAddress(FormalFacetV1.formalValue.selector);
        FacetCut[] memory cuts = _replaceCut();

        vm.prank(caller);
        (bool success, bytes memory reason) =
            address(cutter).call(abi.encodeCall(IDiamondCut.diamondCut, (cuts, address(0), bytes(""))));

        assertFalse(success);
        assertEq(_selector(reason), Errors.NotAuthority.selector);
        assertEq(loupe.facetAddress(FormalFacetV1.formalValue.selector), beforeFacet);
        assertEq(FormalFacetV1(address(diamond)).formalValue(), 1);
    }

    function check_authorityTransferRevokesFormerAndEnablesSuccessor(address successor) public {
        vm.assume(successor != address(0) && successor != address(this) && successor != address(diamond));
        governance.setAuthority(successor);
        FacetCut[] memory cuts = _replaceCut();

        (bool formerSucceeded, bytes memory formerReason) =
            address(cutter).call(abi.encodeCall(IDiamondCut.diamondCut, (cuts, address(0), bytes(""))));
        assertFalse(formerSucceeded);
        assertEq(_selector(formerReason), Errors.NotAuthority.selector);
        assertEq(FormalFacetV1(address(diamond)).formalValue(), 1);

        vm.prank(successor);
        cutter.diamondCut(cuts, address(0), "");
        assertEq(governance.authority(), successor);
        assertEq(loupe.facetAddress(FormalFacetV1.formalValue.selector), address(facetV2));
        assertEq(FormalFacetV2(address(diamond)).formalValue(), 2);
    }

    function check_finalizationRejectsAdd() public {
        governance.finalizeProtocol();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(facetV2), FacetCutAction.Add, _single(bytes4(keccak256("newValue()"))));
        _assertFinalizedCutRejected(cuts, address(0), "");
    }

    function check_finalizationRejectsReplace() public {
        governance.finalizeProtocol();
        _assertFinalizedCutRejected(_replaceCut(), address(0), "");
        assertEq(FormalFacetV1(address(diamond)).formalValue(), 1);
    }

    function check_finalizationRejectsRemove() public {
        governance.finalizeProtocol();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(0), FacetCutAction.Remove, _single(FormalFacetV1.formalValue.selector));
        _assertFinalizedCutRejected(cuts, address(0), "");
        assertEq(FormalFacetV1(address(diamond)).formalValue(), 1);
    }

    function check_finalizationRejectsInitOnlyCut() public {
        governance.finalizeProtocol();
        FacetCut[] memory noCuts = new FacetCut[](0);
        RevertingFormalInitializer initializer = new RevertingFormalInitializer();
        _assertFinalizedCutRejected(
            noCuts, address(initializer), abi.encodeCall(RevertingFormalInitializer.initialize, ())
        );
    }

    function check_failedInitializerRollsBackSelectorGraph() public {
        bytes4 newSelector = bytes4(keccak256("newValue()"));
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(facetV2), FacetCutAction.Add, _single(newSelector));
        RevertingFormalInitializer initializer = new RevertingFormalInitializer();

        (bool success, bytes memory reason) = address(cutter).call(
            abi.encodeCall(
                IDiamondCut.diamondCut,
                (cuts, address(initializer), abi.encodeCall(RevertingFormalInitializer.initialize, ()))
            )
        );

        assertFalse(success);
        assertEq(_selector(reason), Errors.InitializationFailed.selector);
        assertEq(loupe.facetAddress(newSelector), address(0));
        assertEq(loupe.facetAddress(FormalFacetV1.formalValue.selector), address(facetV1));
        assertEq(FormalFacetV1(address(diamond)).formalValue(), 1);
    }

    function check_repeatFoundationInitRollsBackBundledCut() public {
        bytes4 newSelector = bytes4(keccak256("newValue()"));
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(facetV2), FacetCutAction.Add, _single(newSelector));

        (bool success, bytes memory reason) = address(cutter).call(
            abi.encodeCall(
                IDiamondCut.diamondCut,
                (
                    cuts,
                    address(foundation),
                    abi.encodeCall(FoundationInit.initialize, (_config(), TREASURY, address(0), 1 ether, 0))
                )
            )
        );

        assertFalse(success);
        assertEq(_selector(reason), Errors.InitializationFailed.selector);
        assertEq(loupe.facetAddress(newSelector), address(0));
        assertTrue(governance.foundationConfigured());
    }

    function _assertFinalizedCutRejected(FacetCut[] memory cuts, address init, bytes memory data) private {
        (bool success, bytes memory reason) =
            address(cutter).call(abi.encodeCall(IDiamondCut.diamondCut, (cuts, init, data)));
        assertFalse(success);
        assertEq(_selector(reason), Errors.CutsDisabled.selector);
        assertTrue(governance.protocolFinalized());
    }

    function _replaceCut() private view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut(
            address(facetV2), FacetCutAction.Replace, _single(FormalFacetV1.formalValue.selector)
        );
    }

    function _single(bytes4 selector) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = selector;
    }

    function _config() private pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: 1,
            priceIncreaseBps: 0,
            roundTimeout: 1,
            roundEmissionBudget: 0,
            emissionStepBps: 0,
            emissionVestingDuration: 1,
            winnerBps: 10_000,
            nextRoundWinnerBps: 0,
            recoveryBps: 0,
            treasuryBps: 0,
            buybackBps: 0,
            operatorPurchaseBps: 0,
            recoveryBurnBps: 10_000,
            recoveryTreasuryBps: 0,
            roundTimeoutDecay: 0,
            minimumRoundTimeout: 1
        });
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
