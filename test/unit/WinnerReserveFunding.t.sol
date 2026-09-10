// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GameFacet} from "../../src/facets/GameFacet.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract WinnerReserveFundingTest is DiamondTestSetup {
    address internal funder = makeAddr("winner-reserve-funder");

    IGame internal game;

    function setUp() public {
        _deployCore();
        game = IGame(address(diamond));
    }

    function test_DirectFundingBeforeFirstRoundIsAdditiveAndExactlyBacked() public {
        vm.deal(funder, 3 ether);

        vm.startPrank(funder);
        game.fundWinnerReserve{value: 1 ether}();
        game.fundWinnerReserve{value: 2 ether}();
        vm.stopPrank();

        assertEq(game.winnerReserveEth(), 3 ether);
        assertEq(address(diamond).balance, 3 ether);
        assertEq(game.currentRoundId(), 0);
    }

    function test_ZeroFundingRevertsWithoutMutation() public {
        vm.prank(funder);
        vm.expectRevert(Errors.ZeroAmount.selector);
        game.fundWinnerReserve{value: 0}();

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
        game.fundWinnerReserve{value: 1 ether}();

        assertEq(game.winnerReserveEth(), 1 ether);
    }

    function test_FacetImplementationCannotAcceptReserveFunding() public {
        GameFacet implementation = new GameFacet();
        vm.deal(funder, 1 ether);

        vm.prank(funder);
        vm.expectRevert(Errors.InvalidAddress.selector);
        implementation.fundWinnerReserve{value: 1 ether}();

        assertEq(address(implementation).balance, 0);
    }
}
