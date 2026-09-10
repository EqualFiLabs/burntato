// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
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
        vm.deal(funder, 1 ether);
    }

    function test_ReserveFundsFirstWinnerAndPriorPurchasesFundNextRound() public {
        vm.prank(funder);
        game.fundWinnerReserve{value: 0.008 ether}();

        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();

        Round memory roundOne = game.getRound(1);
        assertEq(roundOne.winnerPool, 0.0105 ether);
        assertEq(game.winnerReserveEth(), 0.0002 ether);

        vm.prank(funder);
        game.fundWinnerReserve{value: 0.001 ether}();
        assertEq(game.winnerReserveEth(), 0.0012 ether);

        vm.warp(roundOne.deadline);
        settlement.settleRound();

        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.winnerPool, 0.0012 ether);
        assertEq(game.winnerReserveEth(), 0);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        claims.claimWinner(1, alice);
        assertEq(alice.balance - aliceBefore, 0.0105 ether);

        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();

        roundTwo = game.getRound(2);
        assertEq(roundTwo.winnerPool, 0.0037 ether);
        assertEq(game.winnerReserveEth(), 0.0002 ether);
    }
}
