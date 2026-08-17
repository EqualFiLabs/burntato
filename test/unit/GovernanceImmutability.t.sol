// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";

contract ReplacementAuthorityFacet {
    function authority() external pure returns (address) {
        return address(1);
    }
}

contract GovernanceAdministrationTest is Test {
    uint256 internal constant DELAY = 1 days;

    address internal bootstrap = makeAddr("bootstrap");
    address internal proposer = makeAddr("proposer");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");

    BurntatoDiamond internal diamond;
    DiamondCutFacet internal cutFacet;
    GovernanceFacet internal governanceFacet;
    TimelockController internal timelock;

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(DELAY, proposers, executors, address(0));

        cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(bootstrap, address(cutFacet));
        governanceFacet = new GovernanceFacet();
        FoundationInit initializer = new FoundationInit();

        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(governanceFacet), FacetCutAction.Add, _governanceSelectors());
        vm.prank(bootstrap);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts, address(initializer), abi.encodeCall(FoundationInit.initialize, (0.01 ether, 1_000, treasury))
            );

        vm.startPrank(bootstrap);
        IGovernance(address(diamond)).setGuardian(guardian);
        IGovernance(address(diamond)).setAuthority(address(timelock));
        vm.stopPrank();
    }

    function test_TimelockIsSoleConfigurationAuthority() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(this)));
        IGovernance(address(diamond)).setProtocolConfig(0.02 ether, 2_000);

        _scheduleAndExecute(abi.encodeCall(IGovernance.setProtocolConfig, (0.02 ether, 2_000)));
        assertEq(IGovernance(address(diamond)).authority(), address(timelock));
    }

    function test_GuardianCanPauseButCannotAdminister() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPauseState(true, true);
        assertTrue(IGovernance(address(diamond)).purchasesPaused());
        assertTrue(IGovernance(address(diamond)).commitmentsPaused());

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, guardian));
        IGovernance(address(diamond)).setTreasuryRecipient(guardian);
    }

    function test_GuardianCannotUnpauseButTimelockCan() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPauseState(true, true);

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnpauseRequiresAuthority.selector, guardian));
        IGovernance(address(diamond)).setPauseState(false, false);

        _scheduleAndExecute(abi.encodeCall(IGovernance.setPauseState, (false, false)));
        assertFalse(IGovernance(address(diamond)).purchasesPaused());
        assertFalse(IGovernance(address(diamond)).commitmentsPaused());
    }

    function test_AuthorityCanTransferRepeatedlyToAnyAddress() public {
        BurntatoDiamond candidate = _deployBootstrapGovernance();

        vm.prank(bootstrap);
        IGovernance(address(candidate)).setAuthority(proposer);
        assertEq(IGovernance(address(candidate)).authority(), proposer);

        vm.prank(proposer);
        IGovernance(address(candidate)).setAuthority(guardian);
        assertEq(IGovernance(address(candidate)).authority(), guardian);
    }

    function test_AuthorityCanExplicitlyRelinquishToZero() public {
        vm.prank(address(timelock));
        IGovernance(address(diamond)).setAuthority(address(0));
        assertEq(IGovernance(address(diamond)).authority(), address(0));

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(timelock)));
        IGovernance(address(diamond)).setGuardian(address(0));
    }

    function test_SelectorReplacementWorksUntilFinalization() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGovernance.authority.selector;
        ReplacementAuthorityFacet replacement = new ReplacementAuthorityFacet();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);

        vm.prank(address(timelock));
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        assertEq(IGovernance(address(diamond)).authority(), address(1));
    }

    function test_FinalizationOnlyDisablesDiamondCuts() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPauseState(true, true);

        _scheduleAndExecute(abi.encodeCall(IGovernance.finalizeProtocol, ()));
        IGovernance governance = IGovernance(address(diamond));
        assertTrue(governance.protocolFinalized());
        assertEq(governance.guardian(), guardian);
        assertTrue(governance.purchasesPaused());
        assertTrue(governance.commitmentsPaused());

        address nextGuardian = makeAddr("nextGuardian");
        address nextTreasury = makeAddr("nextTreasury");
        vm.startPrank(address(timelock));
        governance.setProtocolConfig(0.02 ether, 2_000);
        governance.setTreasuryRecipient(nextTreasury);
        governance.setGuardian(nextGuardian);
        governance.setPauseState(false, false);
        governance.setAuthority(proposer);
        vm.stopPrank();

        assertEq(governance.guardian(), nextGuardian);
        assertEq(governance.authority(), proposer);
        assertFalse(governance.purchasesPaused());
        assertFalse(governance.commitmentsPaused());

        FacetCut[] memory cuts = new FacetCut[](0);
        vm.prank(proposer);
        vm.expectRevert(Errors.CutsDisabled.selector);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _scheduleAndExecute(bytes memory data) internal {
        bytes32 salt = keccak256(data);
        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(diamond), 0, data, bytes32(0), salt);
    }

    function _deployBootstrapGovernance() internal returns (BurntatoDiamond candidate) {
        DiamondCutFacet candidateCut = new DiamondCutFacet();
        candidate = new BurntatoDiamond(bootstrap, address(candidateCut));
        GovernanceFacet candidateGovernance = new GovernanceFacet();
        FoundationInit initializer = new FoundationInit();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(candidateGovernance), FacetCutAction.Add, _governanceSelectors());
        vm.prank(bootstrap);
        IDiamondCut(address(candidate))
            .diamondCut(
                cuts, address(initializer), abi.encodeCall(FoundationInit.initialize, (0.01 ether, 1_000, treasury))
            );
    }

    function _governanceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = IGovernance.authority.selector;
        selectors[1] = IGovernance.guardian.selector;
        selectors[2] = IGovernance.purchasesPaused.selector;
        selectors[3] = IGovernance.commitmentsPaused.selector;
        selectors[4] = IGovernance.protocolFinalized.selector;
        selectors[5] = IGovernance.protocolConfig.selector;
        selectors[6] = IGovernance.setAuthority.selector;
        selectors[7] = IGovernance.setGuardian.selector;
        selectors[8] = IGovernance.setPauseState.selector;
        selectors[9] = IGovernance.setProtocolConfig.selector;
        selectors[10] = IGovernance.setTreasuryRecipient.selector;
        selectors[11] = IGovernance.finalizeProtocol.selector;
    }
}
