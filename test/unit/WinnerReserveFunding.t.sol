// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GameFacet} from "../../src/facets/GameFacet.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract WinnerReserveFundingTest is DiamondTestSetup {
    address internal funder = makeAddr("winner-reserve-funder");

    IGame internal game;

    function setUp() public {
        _deployCoreWithoutPurchaseInitialization();
        game = IGame(address(diamond));
    }

    function test_DirectFundingAcrossFutureRoundsIsAdditiveAndExactlyBacked() public {
        vm.deal(funder, 3 ether);

        vm.startPrank(funder);
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGame.WinnerReserveFunded(funder, 1, 1 ether, 1 ether);
        game.fundWinnerReserve{value: 1 ether}(1);
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGame.WinnerReserveFunded(funder, 10, 2 ether, 2 ether);
        game.fundWinnerReserve{value: 2 ether}(10);
        vm.stopPrank();

        assertEq(game.winnerReserveEth(), 3 ether);
        (uint256 roundOneWinner, uint256 roundOneRecovery) = game.roundReserves(1);
        (uint256 roundTenWinner, uint256 roundTenRecovery) = game.roundReserves(10);
        assertEq(roundOneWinner, 1 ether);
        assertEq(roundOneRecovery, 0);
        assertEq(roundTenWinner, 2 ether);
        assertEq(roundTenRecovery, 0);
        assertEq(address(diamond).balance, 3 ether);
        assertEq(game.currentRoundId(), 0);
    }

    function test_ZeroFundingRevertsWithoutMutation() public {
        vm.prank(funder);
        vm.expectRevert(Errors.ZeroAmount.selector);
        game.fundWinnerReserve{value: 0}(1);

        assertEq(game.winnerReserveEth(), 0);
        assertEq(address(diamond).balance, 0);
    }

    function test_RawNativeTransferDoesNotEnterWinnerReserveAccounting() public {
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        (bool success,) = address(diamond).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(diamond).balance, 1 ether);
        assertEq(game.winnerReserveEth(), 0);
    }

    function test_FundingRemainsAvailableWhilePaused() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        game.fundWinnerReserve{value: 1 ether}(1);

        assertEq(game.winnerReserveEth(), 1 ether);
    }

    function test_CurrentTargetRevertsWithoutMutation() public {
        vm.prank(authority);
        IGovernance(address(diamond)).initializePurchases();
        vm.deal(funder, 1.01 ether);
        vm.prank(funder);
        game.buyPotato{value: 0.01 ether}();

        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFutureRound.selector, 1, 1));
        game.fundWinnerReserve{value: 1 ether}(1);

        assertEq(game.winnerReserveEth(), 0.01 ether);
        assertEq(address(diamond).balance, 0.01 ether);
    }

    function test_CombinedFundingSupportsEitherOrBothReserves() public {
        vm.deal(funder, 6 ether);

        vm.startPrank(funder);
        game.fundRoundReserves{value: 3 ether}(7, 1 ether, 2 ether);
        game.fundRoundReserves{value: 1 ether}(7, 1 ether, 0);
        game.fundRoundReserves{value: 2 ether}(8, 0, 2 ether);
        vm.stopPrank();

        (uint256 roundSevenWinner, uint256 roundSevenRecovery) = game.roundReserves(7);
        (uint256 roundEightWinner, uint256 roundEightRecovery) = game.roundReserves(8);
        assertEq(roundSevenWinner, 2 ether);
        assertEq(roundSevenRecovery, 2 ether);
        assertEq(roundEightWinner, 0);
        assertEq(roundEightRecovery, 2 ether);
        assertEq(game.winnerReserveEth(), 2 ether);
        assertEq(IRecovery(address(diamond)).recoveryReserveEth(), 4 ether);
        assertEq(address(diamond).balance, 6 ether);
    }

    function test_CombinedFundingRejectsIncorrectPaymentWithoutMutation() public {
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(Errors.IncorrectPayment.selector, 0.9 ether, 1 ether));
        game.fundRoundReserves{value: 1 ether}(7, 0.4 ether, 0.5 ether);

        assertEq(game.winnerReserveEth(), 0);
        assertEq(IRecovery(address(diamond)).recoveryReserveEth(), 0);
        assertEq(address(diamond).balance, 0);
    }

    function test_FacetImplementationCannotAcceptReserveFunding() public {
        GameFacet implementation = new GameFacet();
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        vm.expectRevert(Errors.InvalidAddress.selector);
        implementation.fundWinnerReserve{value: 1 ether}(1);

        vm.prank(funder);
        vm.expectRevert(Errors.InvalidAddress.selector);
        implementation.fundRoundReserves{value: 1 ether}(1, 0.5 ether, 0.5 ether);

        assertEq(address(implementation).balance, 0);
    }
}
