// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {RewardSchedule, Round} from "../../src/shared/Types.sol";

contract TreasuryRewardsLifecycleTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    IClaims internal claims;
    IGame internal game;
    IPotatoToken internal potato;
    IRecovery internal recovery;
    ISettlement internal settlement;
    ITreasuryRewards internal rewards;

    function setUp() public {
        _deployCore();
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        rewards = ITreasuryRewards(address(diamond));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
    }

    function test_TreasuryFundsFutureRewardsThatTransferWithoutAdditionalMinting() public {
        _fundTreasury();

        vm.prank(treasury);
        uint256 scheduleId = rewards.allocateTreasuryRewards(900 ether, 4, 3);

        RewardSchedule memory schedule = rewards.rewardSchedule(scheduleId);
        assertEq(schedule.amount, 900 ether);
        assertEq(schedule.perRound, 300 ether);
        assertEq(schedule.firstRoundRemainder, 0);
        assertEq(rewards.treasuryRewardsReserved(), 900 ether);
        assertEq(claims.treasuryPotatoAvailable(), 0);
        (uint256 nextRoundId, uint256 nextBudget) = rewards.nextTreasuryRewardBudget();
        assertEq(nextRoundId, 4);
        assertEq(nextBudget, 300 ether);

        _advanceEmptyRound();
        Round memory round = game.getRound(4);
        assertEq(round.treasuryEmissionBudget, 300 ether);
        assertEq(round.remainingTreasuryEmission, 300 ether);
        uint256 supplyBefore = potato.totalSupply();

        _buy(alice);
        round = game.getRound(4);
        assertEq(round.holderMaxReward, 10_000 ether);
        assertEq(round.holderTreasuryMaxReward, 30 ether);
        vm.warp(block.timestamp + 120);
        (uint256 baseEarned, uint256 treasuryEarned) = game.materializeMaturedEmission();
        assertEq(baseEarned, 10_000 ether);
        assertEq(treasuryEarned, 30 ether);
        assertEq(potato.balanceOf(alice), 10_030 ether);
        assertEq(potato.totalSupply(), supplyBefore + baseEarned);
        assertEq(rewards.treasuryRewardsReserved(), 870 ether);
        vm.prank(alice);
        recovery.commitRecovery(treasuryEarned);
        assertEq(recovery.recoveryCommitment(5, alice), treasuryEarned);

        vm.expectRevert(Errors.AlreadyFinalized.selector);
        game.materializeMaturedEmission();

        _expireAndSettle();
        round = game.getRound(4);
        assertEq(round.treasuryEmittedPotato, 30 ether);
        assertEq(round.treasuryReleasedPotato, 270 ether);
        assertEq(round.remainingTreasuryEmission, 0);
        assertEq(rewards.treasuryRewardsReserved(), 600 ether);
        assertEq(claims.treasuryPotatoAvailable(), 270 ether);
    }

    function test_PartialAndFullHoldsShareOnlyActuallyEarnedTreasuryBudget() public {
        _fundTreasury();
        vm.prank(treasury);
        rewards.allocateTreasuryRewards(300 ether, 4, 1);
        _advanceEmptyRound();
        uint256 supplyBefore = potato.totalSupply();

        _buy(alice);
        vm.warp(block.timestamp + 30);
        (uint256 currentBaseEarned, uint256 currentTreasuryEarned) = game.currentEarnedEmission();
        assertEq(currentBaseEarned, 2_500 ether);
        assertEq(currentTreasuryEarned, 7.5 ether);
        _buy(bob);
        assertEq(potato.balanceOf(alice), 2_507.5 ether);

        Round memory round = game.getRound(4);
        assertEq(round.treasuryEmittedPotato, 7.5 ether);
        assertEq(round.remainingTreasuryEmission, 292.5 ether);
        assertEq(round.holderTreasuryMaxReward, 29.25 ether);
        vm.warp(block.timestamp + 120);
        (uint256 baseEarned, uint256 treasuryEarned) = game.materializeMaturedEmission();
        assertEq(baseEarned, 9_750 ether);
        assertEq(treasuryEarned, 29.25 ether);

        _expireAndSettle();
        round = game.getRound(4);
        assertEq(round.treasuryEmittedPotato, 36.75 ether);
        assertEq(round.treasuryReleasedPotato, 263.25 ether);
        assertEq(round.treasuryEmissionBudget, round.treasuryEmittedPotato + round.treasuryReleasedPotato);
        assertEq(potato.totalSupply(), supplyBefore + 12_250 ether);
        assertEq(rewards.treasuryRewardsReserved(), 0);
        assertEq(claims.treasuryPotatoAvailable(), 263.25 ether);
    }

    function test_CancelReleasesOnlyUnactivatedRoundsToTreasuryInventory() public {
        _fundTreasury();
        vm.prank(treasury);
        uint256 scheduleId = rewards.allocateTreasuryRewards(900 ether, 4, 3);
        _advanceEmptyRound();

        vm.prank(treasury);
        assertEq(rewards.cancelTreasuryRewards(scheduleId), 600 ether);

        RewardSchedule memory schedule = rewards.rewardSchedule(scheduleId);
        assertEq(schedule.canceledFromRound, 5);
        assertEq(schedule.canceledAmount, 600 ether);
        assertEq(rewards.treasuryRewardsReserved(), 300 ether);
        assertEq(claims.treasuryPotatoAvailable(), 600 ether);
        (uint256 nextRoundId, uint256 nextBudget) = rewards.nextTreasuryRewardBudget();
        assertEq(nextRoundId, 5);
        assertEq(nextBudget, 0);
        assertEq(game.getRound(4).treasuryEmissionBudget, 300 ether);

        vm.prank(treasury);
        vm.expectRevert(Errors.NothingToCancel.selector);
        rewards.cancelTreasuryRewards(scheduleId);

        uint256 before = potato.balanceOf(treasury);
        assertEq(claims.claimTreasuryPotato(), 600 ether);
        assertEq(potato.balanceOf(treasury) - before, 600 ether);
    }

    function test_OverlappingSchedulesAndRemainderComposeExactly() public {
        _fundTreasury();
        vm.startPrank(treasury);
        rewards.allocateTreasuryRewards(100 ether, 4, 3);
        rewards.allocateTreasuryRewards(200 ether, 4, 2);
        vm.stopPrank();

        (, uint256 nextBudget) = rewards.nextTreasuryRewardBudget();
        assertEq(nextBudget, 133_333_333_333_333_333_334);
        _advanceEmptyRound();
        assertEq(game.getRound(4).treasuryEmissionBudget, 133_333_333_333_333_333_334);

        _buy(carol);
        _expireAndSettle();
        assertEq(game.getRound(5).treasuryEmissionBudget, 133_333_333_333_333_333_333);

        _buy(carol);
        _expireAndSettle();
        assertEq(game.getRound(6).treasuryEmissionBudget, 33_333_333_333_333_333_333);
    }

    function test_AllocatorAdministrationRemainsAvailableAfterFinalization() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotRewardAllocator.selector, alice));
        rewards.allocateTreasuryRewards(1 ether, 1, 1);

        vm.startPrank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        rewards.setRewardAllocator(address(diamond));
        IGovernance(address(diamond)).finalizeProtocol();
        rewards.setRewardAllocator(alice);
        rewards.setRewardAllocator(address(0));
        vm.stopPrank();
        assertEq(rewards.rewardAllocator(), address(0));

        vm.prank(treasury);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotRewardAllocator.selector, treasury));
        rewards.allocateTreasuryRewards(1 ether, 1, 1);
    }

    function test_AllocationRequiresBalanceAndFutureUnactivatedRounds() public {
        vm.prank(treasury);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        rewards.allocateTreasuryRewards(1 ether, 1, 1);

        _fundTreasury();
        vm.startPrank(treasury);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRound.selector, 3));
        rewards.allocateTreasuryRewards(1 ether, 3, 1);
        vm.expectRevert(Errors.ZeroAmount.selector);
        rewards.allocateTreasuryRewards(1 ether, 4, 0);
        vm.stopPrank();
    }

    function _fundTreasury() internal {
        _buy(alice);
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        _buy(bob);
        _expireAndSettle();
        assertEq(claims.claimTreasuryPotato(), 1_000 ether);
        assertEq(potato.balanceOf(treasury), 1_000 ether);
        assertEq(game.currentRoundId(), 3);
    }

    function _advanceEmptyRound() internal {
        _buy(carol);
        _expireAndSettle();
    }

    function _buy(address buyer) internal {
        Round memory round = game.getRound(game.currentRoundId());
        uint256 price = round.nextPrice == 0 ? 0.01 ether : round.nextPrice;
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        settlement.settleRound();
    }
}
