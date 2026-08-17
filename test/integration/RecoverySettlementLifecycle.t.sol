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

        _buy(bob, 0.01 ether);
        _expireAndSettle();

        roundTwo = game.getRound(2);
        assertTrue(roundTwo.settled);
        assertEq(roundTwo.totalCommitted, 10_000 ether);
        assertEq(potato.totalSupply(), 11_000 ether);
        assertEq(potato.balanceOf(address(diamond)), 1_000 ether);
        assertEq(claims.treasuryPotatoAvailable(), 1_000 ether);
        assertEq(game.getRound(3).remainingEmission, 100_000 ether);

        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        assertEq(claims.claimRecovery(2, alice), 0.008 ether);
        assertEq(alice.balance - aliceEthBefore, 0.008 ether);

        uint256 bobEthBefore = bob.balance;
        vm.prank(bob);
        assertEq(claims.claimWinner(2, bob), 0.0025 ether);
        assertEq(bob.balance - bobEthBefore, 0.0025 ether);

        uint256 treasuryEthBefore = treasury.balance;
        assertEq(claims.claimTreasury(), 0.005 ether);
        assertEq(treasury.balance - treasuryEthBefore, 0.005 ether);

        assertEq(claims.claimTreasuryPotato(), 1_000 ether);
        assertEq(potato.balanceOf(treasury), 1_000 ether);
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
        assertEq(potato.totalSupply(), 20_000 ether);
    }

    function test_CommitmentIsIrrevocableAndTargetAdvancesAtRoundStart() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(9_000 ether);
        assertEq(recovery.recoveryCommitment(2, alice), 9_000 ether);
        assertEq(potato.balanceOf(alice), 1_000 ether);

        _expireAndSettle();
        vm.prank(alice);
        recovery.commitRecovery(1_000 ether);

        assertEq(recovery.recoveryCommitment(2, alice), 9_000 ether);
        assertEq(recovery.recoveryCommitment(3, alice), 1_000 ether);
        assertEq(potato.balanceOf(alice), 0);
        assertEq(potato.balanceOf(address(diamond)), 10_000 ether);
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

    function _prepareRoundTwoCommitment() internal {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
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
