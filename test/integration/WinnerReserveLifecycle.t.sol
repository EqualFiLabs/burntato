// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {Round} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract WinnerReserveLifecycleTest is DiamondTestSetup {
    address internal alice = makeAddr("winner-reserve-alice");
    address internal bob = makeAddr("winner-reserve-bob");
    address internal funder = makeAddr("winner-reserve-funder");

    IClaims internal claims;
    IGame internal game;
    ISettlement internal settlement;

    function setUp() public {
        _deployCore();
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        settlement = ISettlement(address(diamond));
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(funder, 3 ether);
    }

    function test_ReserveFundsFirstWinnerAndPriorPurchasesFundNextRound() public {
        vm.prank(funder);
        game.fundWinnerReserve{value: 0.0105 ether}(1);

        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();

        Round memory roundOne = game.getRound(1);
        assertEq(roundOne.winnerPool, 0.0105 ether);
        assertEq(game.winnerReserveEth(), 0.01 ether);
        (uint256 winnerReserve, uint256 recoveryReserve, uint256 winnerSponsored, uint256 recoverySponsored) =
            game.roundFunding(2);
        assertEq(winnerReserve, 0.01 ether);
        assertEq(recoveryReserve, 0);
        assertEq(winnerSponsored, 0);
        assertEq(recoverySponsored, 0);

        vm.prank(funder);
        game.fundWinnerReserve{value: 0.001 ether}(2);
        assertEq(game.winnerReserveEth(), 0.011 ether);
        (winnerReserve, recoveryReserve, winnerSponsored, recoverySponsored) = game.roundFunding(2);
        assertEq(winnerReserve, 0.011 ether);
        assertEq(recoveryReserve, 0);
        assertEq(winnerSponsored, 0.001 ether);
        assertEq(recoverySponsored, 0);

        vm.warp(roundOne.deadline);
        settlement.settleRound();

        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.winnerPool, 0.011 ether);
        assertEq(game.winnerReserveEth(), 0);
        (winnerReserve, recoveryReserve, winnerSponsored, recoverySponsored) = game.roundFunding(2);
        assertEq(winnerReserve, 0);
        assertEq(recoveryReserve, 0);
        assertEq(winnerSponsored, 0);
        assertEq(recoverySponsored, 0);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        claims.claimWinner(1, alice);
        assertEq(alice.balance - aliceBefore, 0.0105 ether);

        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();

        roundTwo = game.getRound(2);
        assertEq(roundTwo.winnerPool, 0.011 ether);
        assertEq(game.winnerReserveEth(), 0.01 ether);
    }

    function test_SettlementMakesCurrentRoundIneligibleForFunding() public {
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        Round memory roundOne = game.getRound(1);
        vm.warp(roundOne.deadline);
        settlement.settleRound();

        vm.prank(funder);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFutureRound.selector, 2, 2));
        game.fundWinnerReserve{value: 0.001 ether}(2);

        assertEq(game.winnerReserveEth(), 0);
    }

    function test_DistantRoundReservesApplyOnlyAtTheirTargetActivation() public {
        vm.startPrank(funder);
        game.fundRoundReserves{value: 1.5 ether}(3, 1 ether, 0.5 ether);
        game.fundRoundReserves{value: 0.5 ether}(5, 0.2 ether, 0.3 ether);
        vm.stopPrank();

        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        Round memory roundOne = game.getRound(1);
        vm.warp(roundOne.deadline);
        settlement.settleRound();

        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.winnerPool, 0.01 ether);
        assertEq(roundTwo.recoveryPool, 0);
        assertEq(game.winnerReserveEth(), 1.2 ether);
        assertEq(IRecovery(address(diamond)).recoveryReserveEth(), 0.8 ether);

        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(game.getRound(2).deadline);
        settlement.settleRound();

        Round memory roundThree = game.getRound(3);
        assertEq(roundThree.winnerPool, 1.01 ether);
        assertEq(roundThree.recoveryPool, 0.5 ether);
        (
            uint256 roundThreeWinner,
            uint256 roundThreeRecovery,
            uint256 roundThreeWinnerSponsored,
            uint256 roundThreeRecoverySponsored
        ) = game.roundFunding(3);
        assertEq(roundThreeWinner, 0);
        assertEq(roundThreeRecovery, 0);
        assertEq(roundThreeWinnerSponsored, 0);
        assertEq(roundThreeRecoverySponsored, 0);
        assertEq(game.winnerReserveEth(), 0.2 ether);
        assertEq(IRecovery(address(diamond)).recoveryReserveEth(), 0.3 ether);
        (uint256 roundFiveWinner, uint256 roundFiveRecovery) = game.roundReserves(5);
        assertEq(roundFiveWinner, 0.2 ether);
        assertEq(roundFiveRecovery, 0.3 ether);
    }
}
