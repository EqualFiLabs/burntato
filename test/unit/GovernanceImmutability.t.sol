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

contract GovernanceImmutabilityTest is Test {
    uint256 internal constant DELAY = 1 days;
    bytes32 internal constant PROTOCOL_CONFIG_KEY = keccak256("burntato.parameter.protocol-config");

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

        bytes4[] memory selectors = _governanceSelectors();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(governanceFacet), FacetCutAction.Add, selectors);
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

    function test_GuardianCanOnlySetPauseState() public {
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

    function test_AuthorityHandoffIsLockedToInitialTimelock() public {
        assertTrue(IGovernance(address(diamond)).authorityLocked());

        TimelockController replacement = new TimelockController(DELAY, new address[](0), new address[](0), address(0));
        vm.prank(address(timelock));
        vm.expectRevert(Errors.AuthorityLocked.selector);
        IGovernance(address(diamond)).setAuthority(address(replacement));
    }

    function test_AuthorityHandoffRejectsEOAAndShortDelay() public {
        BurntatoDiamond candidate = _deployBootstrapGovernance();

        vm.prank(bootstrap);
        vm.expectRevert(abi.encodeWithSelector(Errors.NoCode.selector, proposer));
        IGovernance(address(candidate)).setAuthority(proposer);

        TimelockController shortDelay =
            new TimelockController(DELAY - 1, new address[](0), new address[](0), address(0));
        vm.prank(bootstrap);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTimelock.selector, address(shortDelay)));
        IGovernance(address(candidate)).setAuthority(address(shortDelay));
    }

    function test_ParameterFreezeIsIrreversible() public {
        _scheduleAndExecute(abi.encodeCall(IGovernance.freezeParameter, (PROTOCOL_CONFIG_KEY)));
        assertTrue(IGovernance(address(diamond)).parameterFrozen(PROTOCOL_CONFIG_KEY));

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(Errors.ParameterFrozen.selector, PROTOCOL_CONFIG_KEY));
        IGovernance(address(diamond)).setProtocolConfig(0.02 ether, 2_000);
    }

    function test_SelectorFreezeBlocksReplacement() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGovernance.authority.selector;
        _scheduleAndExecute(abi.encodeCall(IGovernance.freezeSelectors, (selectors)));

        ReplacementAuthorityFacet replacement = new ReplacementAuthorityFacet();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);
        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorFrozen.selector, IGovernance.authority.selector));
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_FinalizationRemovesGuardianAndDisablesCuts() public {
        _scheduleAndExecute(abi.encodeCall(IGovernance.finalizeProtocol, ()));
        assertTrue(IGovernance(address(diamond)).protocolFinalized());
        assertEq(IGovernance(address(diamond)).guardian(), address(0));

        vm.prank(guardian);
        vm.expectRevert(Errors.AlreadyFinalized.selector);
        IGovernance(address(diamond)).setPauseState(true, true);

        FacetCut[] memory cuts = new FacetCut[](0);
        vm.prank(address(timelock));
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
        selectors = new bytes4[](17);
        selectors[0] = IGovernance.authority.selector;
        selectors[1] = IGovernance.authorityLocked.selector;
        selectors[2] = IGovernance.guardian.selector;
        selectors[3] = IGovernance.purchasesPaused.selector;
        selectors[4] = IGovernance.commitmentsPaused.selector;
        selectors[5] = IGovernance.protocolFinalized.selector;
        selectors[6] = IGovernance.protocolConfig.selector;
        selectors[7] = IGovernance.parameterFrozen.selector;
        selectors[8] = IGovernance.selectorFrozen.selector;
        selectors[9] = IGovernance.setAuthority.selector;
        selectors[10] = IGovernance.setGuardian.selector;
        selectors[11] = IGovernance.setPauseState.selector;
        selectors[12] = IGovernance.setProtocolConfig.selector;
        selectors[13] = IGovernance.setTreasuryRecipient.selector;
        selectors[14] = IGovernance.freezeParameter.selector;
        selectors[15] = IGovernance.freezeSelectors.selector;
        selectors[16] = IGovernance.finalizeProtocol.selector;
    }
}
