// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IGame} from "../../src/interfaces/IGame.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {Round} from "../../src/shared/Types.sol";

contract PotatoGameLifecycleTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    IGame internal game;
    IPotatoToken internal potato;

    function setUp() public {
        _deployCore();
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_FullHoldReproducesGeometricStep() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 10_000 ether);
        assertEq(round.remainingEmission, 90_000 ether);
        assertEq(round.emittedPotato, 10_000 ether);
        assertEq(round.holderMaxReward, 9_000 ether);
    }

    function test_PartialHoldPreservesUnusedBudget() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 30);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 2_500 ether);
        assertEq(round.remainingEmission, 97_500 ether);
        assertEq(round.holderMaxReward, 9_750 ether);
    }

    function test_ZeroTimeCyclingDoesNotConsumeEmission() public {
        _buy(alice, 0.01 ether);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 0);
        assertEq(round.remainingEmission, 100_000 ether);
        assertEq(round.holderMaxReward, 10_000 ether);
    }

    function test_MaterializedRewardCannotMintTwice() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        assertEq(game.materializeMaturedEmission(), 10_000 ether);
        assertEq(potato.balanceOf(alice), 10_000 ether);

        _buy(bob, 0.011 ether);
        assertEq(potato.balanceOf(alice), 10_000 ether);
        assertEq(potato.totalSupply(), 10_000 ether);
    }

    function test_RewardNeverExceedsSnapshot() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 10 days);
        assertEq(game.currentEarnedEmission(), 10_000 ether);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 10_000 ether);
    }

    function test_ApprovalDoesNotBypassTransferRestrictionAndSelfBurnWorks() public {
        _earnForAlice();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transfer(bob, 1 ether);

        vm.prank(alice);
        potato.approve(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transferFrom(alice, bob, 1 ether);
        assertEq(potato.allowance(alice, bob), 1 ether);

        vm.prank(alice);
        potato.burn(1 ether);
        assertEq(potato.balanceOf(alice), 9_999 ether);
        assertEq(potato.totalSupply(), 9_999 ether);
    }

    function test_PurchaseConservesNativeAllocationAndRaisesPrice() public {
        _buy(alice, 0.01 ether);
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 0.0025 ether);
        assertEq(round.recoveryPool, 0.005 ether);
        assertEq(round.nextPrice, 0.011 ether);
        assertEq(round.deadline, block.timestamp + 1 hours);
    }

    function _earnForAlice() internal {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
    }

    function _buy(address buyer, uint256 price) internal {
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }
}
