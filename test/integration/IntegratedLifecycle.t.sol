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
import {Round} from "../../src/shared/Types.sol";

contract IntegratedLifecycleTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");

    IClaims internal claims;
    IGame internal game;
    IGovernance internal governance;
    IPotatoToken internal potato;
    IRecovery internal recovery;
    ISettlement internal settlement;

    function setUp() public {
        _deployCore();
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        governance = IGovernance(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.deal(carol, 1_000 ether);
    }

    function test_CompleteRoundUsesTimeEmissionForwardRecoveryAndPullClaims() public {
        _buy(alice);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        _buy(bob);
        _advance(30);
        _buy(carol);
        assertEq(potato.balanceOf(bob), 2_500 ether);
        _advance(120);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(carol), 9_750 ether);
        _expireAndSettle();

        Round memory round = game.getRound(2);
        assertEq(round.remainingEmission, 87_750 ether);
        assertEq(round.emittedPotato, 12_250 ether);
        assertEq(round.totalCommitted, 10_000 ether);
        assertEq(potato.balanceOf(address(diamond)), 1_000 ether);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.0155 ether);
        assertEq(alice.balance - aliceBefore, 0.0155 ether);

        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        assertEq(claims.claimWinner(2, carol), 0.00525 ether);
        assertEq(carol.balance - carolBefore, 0.00525 ether);
        assertEq(game.getRound(3).remainingEmission, 100_000 ether);
    }

    function test_MaturedRoundEmissionCanParlayOnlyIntoImmediatelyNextOpenMarket() public {
        _buy(alice);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        _buy(bob);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(bob);
        recovery.commitRecovery(10_000 ether);

        assertEq(recovery.totalRecoveryCommitment(2), 10_000 ether);
        assertEq(recovery.totalRecoveryCommitment(3), 10_000 ether);
        _expireAndSettle();
        assertEq(game.getRound(2).totalCommitted, 10_000 ether);
        assertEq(game.getRound(3).totalCommitted, 0);
    }

    function test_InflationaryTargetRoundIncreasesSupply() public {
        (uint256 beforeSupply, uint256 afterSupply) = _settleTargetWithCommitment(1_000 ether);
        assertEq(afterSupply, beforeSupply + 9_100 ether);
    }

    function test_SupplyNeutralTargetRoundOffsetsEmissionWithExactBurn() public {
        uint256 commitment = 11_111_111_111_111_111_111_111;
        (uint256 beforeSupply, uint256 afterSupply) = _settleTargetWithCommitment(commitment);
        assertEq(afterSupply, beforeSupply);
    }

    function test_DeflationaryTargetRoundReducesSupply() public {
        (uint256 beforeSupply, uint256 afterSupply) = _settleTargetWithCommitment(19_000 ether);
        assertEq(afterSupply, beforeSupply - 7_100 ether);
    }

    function test_ZeroCommitmentRecoveryRollsUntilACommittedRoundConsumesIt() public {
        _buy(alice);
        _expireAndSettle();
        assertEq(game.getRound(2).recoveryCarryIn, 0.005 ether);

        _buy(bob);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(bob);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();
        assertEq(game.getRound(3).recoveryCarryIn, 0.01 ether);

        _buy(carol);
        _expireAndSettle();
        assertEq(game.getRound(3).recoveryPool, 0.015 ether);
        assertEq(game.getRound(4).recoveryCarryIn, 0);
        vm.prank(bob);
        assertEq(claims.claimRecovery(3, bob), 0.015 ether);
    }

    function test_RoundActivationSnapshotsNextRoundBeforeAnyCommitment() public {
        _buy(alice);
        Round memory preMutationRoundTwo = game.getRound(2);
        assertEq(preMutationRoundTwo.config.startingPrice, 0.01 ether);
        assertEq(preMutationRoundTwo.config.priceIncreaseBps, 1_000);
        assertEq(recovery.totalRecoveryCommitment(2), 0);

        vm.prank(authority);
        governance.setProtocolConfig(0.02 ether, 2_000);

        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(1 ether);
        _expireAndSettle();
        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.config.startingPrice, 0.01 ether);
        assertEq(roundTwo.config.priceIncreaseBps, 1_000);

        _buy(bob);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(bob);
        recovery.commitRecovery(1 ether);
        Round memory roundThree = game.getRound(3);
        assertEq(roundThree.config.startingPrice, 0.02 ether);
        assertEq(roundThree.config.priceIncreaseBps, 2_000);
    }

    function test_PauseBlocksOnlyNewRiskAndLeavesResolutionPathsLive() public {
        _buy(alice);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        _buy(bob);
        _advance(120);
        vm.prank(guardian);
        governance.setPauseState(true, true);

        vm.prank(carol);
        vm.expectRevert(Errors.PurchasesPaused.selector);
        game.buyPotato{value: 0.011 ether}();
        game.materializeMaturedEmission();
        vm.prank(bob);
        vm.expectRevert(Errors.CommitmentsPaused.selector);
        recovery.commitRecovery(1 ether);
        vm.prank(bob);
        potato.burn(1 ether);

        _expireAndSettle();
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.01 ether);
        vm.prank(bob);
        assertEq(claims.claimWinner(2, bob), 0.0025 ether);
    }

    function test_FinalizedProtocolContinuesNormalPermissionlessLifecycle() public {
        vm.prank(authority);
        governance.finalizeProtocol();
        assertTrue(governance.protocolFinalized());

        _buy(alice);
        _advance(120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();
        _buy(bob);
        _expireAndSettle();

        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.01 ether);
        vm.prank(authority);
        vm.expectRevert(Errors.AlreadyFinalized.selector);
        governance.setProtocolConfig(0.02 ether, 2_000);
        vm.prank(guardian);
        vm.expectRevert(Errors.AlreadyFinalized.selector);
        governance.setPauseState(true, true);
    }

    function test_OneHundredFullHoldsFollowGeometricCurveAndLeaveAsymptoticDust() public {
        uint256 expectedRemaining = 100_000 ether;
        for (uint256 i; i < 100; ++i) {
            address holder = address(uint160(10_000 + i));
            _buy(holder);
            _advance(120);
            if (i < 99) {
                uint256 reward = expectedRemaining * 1_000 / 10_000;
                expectedRemaining -= reward;
            }
        }
        game.materializeMaturedEmission();
        expectedRemaining -= expectedRemaining * 1_000 / 10_000;

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(address(uint160(10_000))), 10_000 ether);
        assertEq(potato.balanceOf(address(uint160(10_001))), 9_000 ether);
        assertEq(potato.balanceOf(address(uint160(10_002))), 8_100 ether);
        assertEq(round.remainingEmission, expectedRemaining);
        assertEq(round.emittedPotato + round.remainingEmission, 100_000 ether);
        assertApproxEqAbs(round.remainingEmission, 2.656 ether, 0.001 ether);
    }

    function _settleTargetWithCommitment(uint256 totalCommitment)
        internal
        returns (uint256 beforeSupply, uint256 afterSupply)
    {
        _buy(alice);
        _advance(120);
        _buy(bob);
        _advance(120);
        game.materializeMaturedEmission();

        uint256 aliceCommitment = totalCommitment > 10_000 ether ? 10_000 ether : totalCommitment;
        if (aliceCommitment != 0) {
            vm.prank(alice);
            recovery.commitRecovery(aliceCommitment);
        }
        uint256 bobCommitment = totalCommitment - aliceCommitment;
        if (bobCommitment != 0) {
            vm.prank(bob);
            recovery.commitRecovery(bobCommitment);
        }
        _expireAndSettle();
        beforeSupply = potato.totalSupply();

        _buy(carol);
        _expireAndSettle();
        afterSupply = potato.totalSupply();
        assertEq(game.getRound(2).emittedPotato, 10_000 ether);
        assertEq(game.getRound(2).totalCommitted, totalCommitment);
    }

    function _buy(address buyer) internal {
        uint256 roundId = game.currentRoundId();
        uint256 price = roundId == 0 ? 0.01 ether : game.getRound(roundId).nextPrice;
        vm.deal(buyer, buyer.balance + price);
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        vm.prank(keeper);
        settlement.settleRound();
    }

    function _advance(uint256 secondsForward) internal {
        vm.warp(vm.getBlockTimestamp() + secondsForward);
    }
}
