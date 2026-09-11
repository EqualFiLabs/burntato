// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract RecoveryReserveFundingTest is DiamondTestSetup {
    address internal funder = makeAddr("recovery-reserve-funder");

    IRecovery internal recovery;

    function setUp() public {
        _deployCoreWithoutPurchaseInitialization();
        recovery = IRecovery(address(diamond));
    }

    function test_DirectFundingBeforeFirstRoundIsAdditiveAndExactlyBacked() public {
        vm.deal(funder, 3 ether);

        vm.startPrank(funder);
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRecovery.RecoveryReserveFunded(funder, 1, 1 ether, 1 ether);
        recovery.fundRecoveryReserve{value: 1 ether}(1);
        recovery.fundRecoveryReserve{value: 2 ether}(1);
        vm.stopPrank();

        assertEq(recovery.recoveryReserveEth(), 3 ether);
        assertEq(address(diamond).balance, 3 ether);
    }

    function test_ZeroFundingRevertsWithoutMutation() public {
        vm.prank(funder);
        vm.expectRevert(Errors.ZeroAmount.selector);
        recovery.fundRecoveryReserve{value: 0}(1);

        assertEq(recovery.recoveryReserveEth(), 0);
        assertEq(address(diamond).balance, 0);
    }

    function test_StaleTargetRevertsWithoutMutation() public {
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnexpectedTargetRound.selector, 2, 1));
        recovery.fundRecoveryReserve{value: 1 ether}(2);

        assertEq(recovery.recoveryReserveEth(), 0);
        assertEq(address(diamond).balance, 0);
    }

    function test_RawNativeTransferDoesNotEnterRecoveryReserveAccounting() public {
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (bool success,) = address(diamond).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(diamond).balance, 1 ether);
        assertEq(recovery.recoveryReserveEth(), 0);
    }

    function test_FundingRemainsAvailableWhilePaused() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        recovery.fundRecoveryReserve{value: 1 ether}(1);

        assertEq(recovery.recoveryReserveEth(), 1 ether);
    }

    function test_FacetImplementationCannotAcceptReserveFunding() public {
        RecoveryFacet implementation = new RecoveryFacet();
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        vm.expectRevert(Errors.InvalidAddress.selector);
        implementation.fundRecoveryReserve{value: 1 ether}(1);

        assertEq(address(implementation).balance, 0);
    }
}
