// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract RecoverySettlementLifecycleTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    IGame internal game;
    IPotatoToken internal potato;
    IRecovery internal recovery;
    ISettlement internal settlement;
    IClaims internal claims;

    function setUp() public {
        _deployCore();
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        claims = IClaims(address(diamond));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_CompleteForwardRecoveryAndClaimLifecycle() public {
        _prepareRoundTwoCommitment();
        _expireAndSettle();

        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.remainingEmission, 100_000 ether);
        assertEq(roundTwo.recoveryCarryIn, 0.004 ether);
        assertFalse(claims.winnerClaimed(2));
        assertFalse(claims.recoveryClaimed(2, alice));
        assertEq(claims.claimableRecovery(2, alice), 0);

        _buy(bob, 0.01 ether);
        _expireAndSettle();

        roundTwo = game.getRound(2);
        assertTrue(roundTwo.settled);
        assertEq(roundTwo.totalCommitted, 10_000 ether);
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY + 11_000 ether);
        assertEq(potato.balanceOf(address(diamond)), GENESIS_MARKET_SUPPLY + 1_000 ether);
        assertEq(claims.treasuryPotatoAvailable(), 1_000 ether);
        assertEq(game.getRound(3).remainingEmission, 100_000 ether);
        assertEq(claims.claimableRecovery(2, alice), 0.008 ether);
        assertEq(claims.claimableRecovery(2, bob), 0);

        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.008 ether);
        assertEq(alice.balance - aliceEthBefore, 0.008 ether);
        assertTrue(claims.recoveryClaimed(2, alice));
        assertEq(claims.claimableRecovery(2, alice), 0);

        uint256 bobEthBefore = bob.balance;
        vm.prank(bob);
        assertEq(claims.claimWinner(2, bob), 0.0025 ether);
        assertEq(bob.balance - bobEthBefore, 0.0025 ether);
        assertTrue(claims.winnerClaimed(2));

        uint256 treasuryEthBefore = treasury.balance;
        assertEq(claims.claimTreasury(), 0.005 ether);
        assertEq(treasury.balance - treasuryEthBefore, 0.005 ether);

        assertEq(claims.claimTreasuryPotato(), 1_000 ether);
        assertEq(potato.balanceOf(treasury), 1_000 ether);
    }

    function test_FinalOutstandingCommitmentReceivesExactRecoveryRemainderInEitherOrder() public {
        _buy(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _buy(bob, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();

        uint256 aliceCommitment = 3_333 ether + 1;
        uint256 bobCommitment = 2_222 ether + 2;
        vm.prank(alice);
        recovery.commitRecovery(aliceCommitment);
        vm.prank(bob);
        recovery.commitRecovery(bobCommitment);
        _expireAndSettle();

        _buy(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 60);
        _buy(bob, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _expireAndSettle();
        Round memory roundTwo = game.getRound(2);
        uint256 totalCommitted = aliceCommitment + bobCommitment;
        assertEq(roundTwo.totalCommitted, totalCommitted);
        assertNotEq(mulmod(roundTwo.recoveryPool, aliceCommitment, totalCommitted), 0);

        uint256 snapshot = vm.snapshotState();
        _assertExactRecoveryClaims(roundTwo.recoveryPool, alice, aliceCommitment, bob);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        _assertExactRecoveryClaims(roundTwo.recoveryPool, bob, bobCommitment, alice);
    }

    function test_ZeroCommitmentRecoveryRollsForwardExactly() public {
        _buy(alice, 0.01 ether);
        _expireAndSettle();
        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.recoveryCarryIn, 0.004 ether);
        assertEq(roundTwo.recoveryPool, 0.004 ether);
        assertEq(claims.treasuryPotatoAvailable(), 0);
    }

    function test_ConfiguredRecoverySplitCanRouteAllCommittedPotatoToTreasury() public {
        ProtocolConfig memory config = _defaultConfig();
        config.recoveryBurnBps = 0;
        config.recoveryTreasuryBps = 10_000;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);

        _prepareRoundTwoCommitment();
        _expireAndSettle();
        _buy(bob, 0.01 ether);
        _expireAndSettle();

        assertEq(game.getRound(2).totalCommitted, 10_000 ether);
        assertEq(claims.treasuryPotatoAvailable(), 10_000 ether);
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY + 20_000 ether);
    }

    function test_CommitmentRemainsLockedOncePredecessorHasHolderAndTargetAdvancesAtRoundStart() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(9_000 ether);
        assertEq(recovery.recoveryCommitment(2, alice), 9_000 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(2), 0);
        assertEq(potato.balanceOf(alice), 1_000 ether);

        _expireAndSettle();
        vm.prank(alice);
        recovery.commitRecovery(1_000 ether);

        assertEq(recovery.recoveryCommitment(2, alice), 9_000 ether);
        assertEq(recovery.recoveryCommitment(3, alice), 1_000 ether);
        assertEq(potato.balanceOf(alice), 0);
        assertEq(potato.balanceOf(address(diamond)), GENESIS_MARKET_SUPPLY + 10_000 ether);
    }

    function test_StalledRecoveryWithdrawsAfterThirtyDaysEvenWhenCommitmentsPaused() public {
        uint256 amount = 6_000 ether;
        uint256 availableAt = _prepareStalledRecovery(amount);
        assertEq(availableAt, vm.getBlockTimestamp() + 30 days);

        vm.prank(authority);
        IGovernance(address(diamond)).setPauseState(false, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.RecoveryWithdrawalTooSoon.selector, availableAt));
        recovery.withdrawStalledRecovery(3);

        vm.warp(availableAt);
        vm.prank(bob);
        vm.expectRevert(Errors.NothingToCancel.selector);
        recovery.withdrawStalledRecovery(3);

        uint256 aliceBefore = potato.balanceOf(alice);
        uint256 diamondBefore = potato.balanceOf(address(diamond));
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IRecovery.StalledRecoveryWithdrawn(3, alice, amount, 0);
        vm.prank(alice);
        assertEq(recovery.withdrawStalledRecovery(3), amount);

        assertEq(potato.balanceOf(alice) - aliceBefore, amount);
        assertEq(diamondBefore - potato.balanceOf(address(diamond)), amount);
        assertEq(recovery.recoveryCommitment(3, alice), 0);
        assertEq(recovery.totalRecoveryCommitment(3), 0);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), 0);
    }

    function test_StalledRecoveryUsesSharedClockAndRestartsAfterAllCommitmentsExit() public {
        _buy(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _buy(bob, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();
        _expireAndSettle();

        vm.prank(alice);
        recovery.commitRecovery(5_000 ether);
        uint256 sharedAvailableAt = recovery.stalledRecoveryWithdrawalAt(3);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(bob);
        recovery.commitRecovery(4_000 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), sharedAvailableAt);

        vm.warp(sharedAvailableAt);
        vm.prank(alice);
        assertEq(recovery.withdrawStalledRecovery(3), 5_000 ether);
        assertEq(recovery.totalRecoveryCommitment(3), 4_000 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), sharedAvailableAt);

        vm.prank(bob);
        assertEq(recovery.withdrawStalledRecovery(3), 4_000 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), 0);

        vm.prank(alice);
        recovery.commitRecovery(1_000 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), vm.getBlockTimestamp() + 30 days);
    }

    function test_FirstPurchasePermanentlyClosesStalledRecoveryWithdrawal() public {
        uint256 amount = 6_000 ether;
        uint256 availableAt = _prepareStalledRecovery(amount);

        _buy(bob, 0.01 ether);
        assertEq(recovery.stalledRecoveryWithdrawalAt(3), 0);
        vm.warp(availableAt);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.RecoveryWithdrawalUnavailable.selector, 3));
        recovery.withdrawStalledRecovery(3);

        _expireAndSettle();
        assertTrue(game.getRound(3).activated);
        assertEq(recovery.recoveryCommitment(3, alice), amount);
        assertEq(recovery.totalRecoveryCommitment(3), amount);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.RecoveryWithdrawalUnavailable.selector, 3));
        recovery.withdrawStalledRecovery(3);
    }

    function test_ClaimsCannotBeRepeated() public {
        _prepareRoundTwoCommitment();
        _expireAndSettle();
        _buy(bob, 0.01 ether);
        _expireAndSettle();

        vm.startPrank(alice);
        claims.claimRecovery(2, alice);
        vm.expectRevert(Errors.AlreadyClaimed.selector);
        claims.claimRecovery(2, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        claims.claimWinner(2, bob);
        vm.expectRevert(Errors.AlreadyClaimed.selector);
        claims.claimWinner(2, bob);
        vm.stopPrank();
    }

    function test_ClaimsRejectDiamondRecipientWithoutConsumingEntitlement() public {
        _prepareRoundTwoCommitment();
        _expireAndSettle();
        _buy(bob, 0.01 ether);
        _expireAndSettle();

        vm.prank(alice);
        vm.expectRevert(Errors.InvalidAddress.selector);
        claims.claimRecovery(2, address(diamond));

        uint256 before = alice.balance;
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.008 ether);
        assertEq(alice.balance - before, 0.008 ether);
    }

    function test_TreasuryRecipientRejectsProtocolCustody() public {
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        IGovernance(address(diamond)).setTreasuryRecipient(address(diamond));
    }

    function test_RecoveryClaimUsesFullPrecisionForLargeValues() public {
        uint256 largePrice = 1 << 200;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(_configWithPrice(largePrice, 1_000));
        vm.deal(alice, largePrice);
        vm.deal(bob, largePrice);

        _buy(alice, largePrice);
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        _buy(bob, largePrice);
        _expireAndSettle();
        Round memory roundTwo = game.getRound(2);
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), roundTwo.recoveryPool);
    }

    function test_ForcedEthDoesNotBecomeTreasuryRevenue() public {
        _buy(alice, 0.01 ether);
        assertEq(claims.treasuryEthAvailable(), 0.0025 ether);
        vm.deal(address(diamond), address(diamond).balance + 7 ether);
        assertEq(claims.treasuryEthAvailable(), 0.0025 ether);
    }

    function _assertExactRecoveryClaims(uint256 recoveryPool, address first, uint256 firstCommitment, address last)
        internal
    {
        uint256 totalCommitted = game.getRound(2).totalCommitted;
        uint256 ordinaryFloor = recoveryPool * firstCommitment / totalCommitted;
        assertEq(claims.claimableRecovery(2, first), ordinaryFloor);

        uint256 diamondEthBefore = address(diamond).balance;
        uint256 firstEthBefore = first.balance;
        vm.prank(first);
        uint256 firstPaid = claims.claimRecovery(2, first);
        assertEq(firstPaid, ordinaryFloor);
        assertEq(first.balance - firstEthBefore, firstPaid);

        uint256 finalRemainder = recoveryPool - firstPaid;
        assertEq(claims.claimableRecovery(2, last), finalRemainder);
        uint256 lastEthBefore = last.balance;
        vm.prank(last);
        uint256 lastPaid = claims.claimRecovery(2, last);
        assertEq(lastPaid, finalRemainder);
        assertEq(last.balance - lastEthBefore, lastPaid);
        assertEq(firstPaid + lastPaid, recoveryPool);
        assertEq(diamondEthBefore - address(diamond).balance, recoveryPool);
        assertEq(claims.claimableRecovery(2, first), 0);
        assertEq(claims.claimableRecovery(2, last), 0);
        assertTrue(claims.recoveryClaimed(2, first));
        assertTrue(claims.recoveryClaimed(2, last));
    }

    function _prepareRoundTwoCommitment() internal {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
    }

    function _prepareStalledRecovery(uint256 amount) internal returns (uint256 availableAt) {
        _buy(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();
        _expireAndSettle();
        assertEq(game.currentRoundId(), 2);
        assertEq(game.getRound(2).currentHolder, address(0));

        vm.prank(alice);
        recovery.commitRecovery(amount);
        availableAt = recovery.stalledRecoveryWithdrawalAt(3);
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        vm.prank(keeper);
        settlement.settleRound();
    }

    function _buy(address buyer, uint256 price) internal {
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }
}
