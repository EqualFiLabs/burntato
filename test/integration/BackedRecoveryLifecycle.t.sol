// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract BackedRecoveryLifecycleTest is DiamondTestSetup {
    IPotatoToken internal potato;
    IGame internal game;
    IRecovery internal recovery;
    IClaims internal claims;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function _initialRewardFunding() internal pure override returns (uint256) {
        return 5_000 ether;
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.roundEmissionBudget = 5_000 ether;
        config.emissionVestingDuration = 4 minutes;
    }

    function setUp() public {
        _deployCore();
        potato = IPotatoToken(address(diamond));
        vm.prank(authority);
        potato.setPublicWrapCap(2_000_000 ether);
        game = IGame(address(diamond));
        recovery = IRecovery(address(diamond));
        claims = IClaims(address(diamond));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        _buy(alice);
        vm.warp(block.timestamp + 4 minutes);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(200 ether);
        statics.mint(bob, 300 ether);
        vm.startPrank(bob);
        statics.approve(address(diamond), 300 ether);
        potato.wrap(300 ether);
        recovery.commitRecovery(300 ether);
        vm.stopPrank();
        _settle();
    }

    function _buy(address buyer) internal {
        uint256 id = game.currentRoundId();
        uint256 price = id == 0 ? 0.01 ether : game.getRound(id).nextPrice;
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }

    function _settle() internal {
        vm.warp(game.getRound(game.currentRoundId()).deadline);
        ISettlement(address(diamond)).settleRound();
    }

    function _startTargetRound() internal {
        statics.mint(address(this), 500 ether);
        statics.approve(address(diamond), 500 ether);
        potato.fundRewardReserve(500 ether);
        _buy(bob);
        vm.warp(block.timestamp + 4 minutes);
        _buy(alice);
    }

    function test_CompleteRedemptionTreasuryReceiptAndExactEthClaimsWhileUnderfunded() public {
        _startTargetRound();
        uint256 supplyBefore = potato.totalSupply();
        uint256 remainingReward = game.getRound(2).holderMaxReward;
        _settle();
        assertEq(statics.balanceOf(treasury), 500 ether);
        assertEq(potato.totalSupply(), supplyBefore + 0 - 500 ether);
        // Reward materialization transfers existing reserve supply.
        assertEq(potato.publicWrapOutstanding(), 0);
        assertEq(potato.availablePublicWrapCapacity(), 2_000_000 ether);
        assertEq(claims.treasuryPotatoAvailable(), 0);
        assertEq(potato.backingBalance(), potato.totalSupply());
        assertEq(potato.balanceOf(alice), 300 ether + remainingReward);
        (,,, bool funded) = potato.nextRoundFundingStatus();
        assertFalse(funded);
        Round memory target = game.getRound(2);
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        uint256 a = claims.claimRecovery(2, alice);
        vm.prank(bob);
        uint256 b = claims.claimRecovery(2, bob);
        assertEq(a, target.recoveryPool * 2 / 5);
        assertEq(a + b, target.recoveryPool);
        assertEq(alice.balance, aliceBefore + a);
        assertEq(bob.balance, bobBefore + b);
        vm.prank(alice);
        claims.claimWinner(2, alice);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InsufficientRewardReserve.selector, potato.rewardReserve(), 5_000 ether)
        );
        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();
    }

    function test_CurrentTreasuryRecipientReceivesUnderlyingIndependentlyOfDistributor() public {
        _startTargetRound();
        address successor = makeAddr("treasury-successor");
        vm.prank(authority);
        IGovernance(address(diamond)).setTreasuryRecipient(successor);
        assertFalse(potato.isDistributor(successor));
        _settle();
        assertEq(statics.balanceOf(successor), 500 ether);
        assertEq(statics.balanceOf(treasury), 0);
        assertGt(claims.treasuryEthAvailable(), 0);
        claims.claimTreasury();
        assertGt(successor.balance, 0);
    }

    function test_SettlementTokenFailureRollsBackCompleteTransition() public {
        _startTargetRound();
        Round memory beforeRound = game.getRound(2);
        uint256 beforeSupply = potato.totalSupply();
        uint256 beforeReserve = potato.rewardReserve();
        statics.setFailure(true);
        vm.warp(beforeRound.deadline);
        vm.expectRevert();
        ISettlement(address(diamond)).settleRound();
        assertEq(game.currentRoundId(), 2);
        assertFalse(game.getRound(2).settled);
        assertFalse(game.getRound(2).holderEmissionFinalized);
        assertEq(potato.totalSupply(), beforeSupply);
        assertEq(potato.rewardReserve(), beforeReserve);
        assertEq(statics.balanceOf(treasury), 0);
        statics.setFailure(false);
        ISettlement(address(diamond)).settleRound();
        assertEq(statics.balanceOf(treasury), 500 ether);
    }

    function test_OutgoingFeeRollsBackCompleteSettlement() public {
        _startTargetRound();
        uint256 supplyBefore = potato.totalSupply();
        uint256 reserveBefore = potato.rewardReserve();
        statics.setFee(1);
        vm.warp(game.getRound(2).deadline);
        vm.expectRevert(Errors.InvalidBacking.selector);
        ISettlement(address(diamond)).settleRound();
        assertEq(game.currentRoundId(), 2);
        assertFalse(game.getRound(2).settled);
        assertFalse(game.getRound(2).holderEmissionFinalized);
        assertEq(potato.totalSupply(), supplyBefore);
        assertEq(potato.rewardReserve(), reserveBefore);
        assertEq(potato.publicWrapOutstanding(), 300 ether);
        assertEq(statics.balanceOf(treasury), 0);
        assertEq(potato.backingBalance(), supplyBefore);
    }

    function test_SettlementUnderlyingCallbackCannotReenter() public {
        _startTargetRound();
        statics.setCallback(address(diamond), abi.encodeCall(ISettlement.settleRound, ()));
        _settle();
        assertFalse(statics.callbackSucceeded());
        assertEq(game.currentRoundId(), 3);
        assertEq(statics.balanceOf(treasury), 500 ether);
    }

    function test_UnderfundedHolderlessPredecessorKeepsStalledExitAndRedemptionLive() public {
        // Round 2 is deliberately underfunded and has no holder.
        vm.prank(alice);
        recovery.commitRecovery(300 ether);
        uint256 deadline = recovery.stalledRecoveryWithdrawalAt(3);
        vm.warp(deadline);
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        vm.prank(alice);
        recovery.withdrawStalledRecovery(3);
        assertEq(recovery.recoveryCommitment(3, alice), 0);
        assertEq(potato.balanceOf(alice), 300 ether);
        vm.prank(alice);
        potato.unwrap(300 ether);
        assertEq(statics.balanceOf(alice), 300 ether);
        assertEq(potato.publicWrapOutstanding(), 0);
        assertEq(recovery.totalRecoveryCommitment(2), 500 ether);
    }
}
