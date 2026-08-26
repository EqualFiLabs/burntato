// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {Round} from "../../src/shared/Types.sol";

contract RecoveryDistributionFuzzTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    IClaims internal claims;
    IGame internal game;
    IPotatoToken internal potato;
    IRecovery internal recovery;
    ISettlement internal settlement;

    function setUp() public {
        _deployCore();
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(carol, 1 ether);
    }

    function testFuzz_ProRataClaimsAndRecoveryConsumptionConserveValue(
        uint96 rawAliceCommitment,
        uint96 rawBobCommitment,
        bool bobClaimsFirst
    ) public {
        _buy(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _buy(bob, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();

        uint256 aliceCommitment = bound(uint256(rawAliceCommitment), 1, 10_000 ether);
        uint256 bobCommitment = bound(uint256(rawBobCommitment), 1, 9_000 ether);
        vm.prank(alice);
        recovery.commitRecovery(aliceCommitment);
        vm.prank(bob);
        recovery.commitRecovery(bobCommitment);
        _expireAndSettle();

        uint256 supplyBefore = potato.totalSupply();
        _buy(carol, 0.01 ether);
        _expireAndSettle();

        Round memory target = game.getRound(2);
        uint256 totalCommitted = aliceCommitment + bobCommitment;
        uint256 treasuryPotato = totalCommitted * 1_000 / 10_000;
        uint256 burned = totalCommitted - treasuryPotato;
        assertEq(target.totalCommitted, totalCommitted);
        assertEq(potato.totalSupply(), supplyBefore + 10_000 ether - burned);
        assertEq(potato.balanceOf(address(diamond)), GENESIS_MARKET_SUPPLY + treasuryPotato);

        uint256 ordinaryAlice = target.recoveryPool * aliceCommitment / totalCommitted;
        uint256 ordinaryBob = target.recoveryPool * bobCommitment / totalCommitted;
        assertEq(claims.claimableRecovery(2, alice), ordinaryAlice);
        assertEq(claims.claimableRecovery(2, bob), ordinaryBob);
        uint256 firstPaid;
        uint256 finalPaid;
        if (bobClaimsFirst) {
            vm.prank(bob);
            firstPaid = claims.claimRecovery(2, bob);
            assertEq(firstPaid, ordinaryBob);
            assertEq(claims.claimableRecovery(2, alice), target.recoveryPool - firstPaid);
            vm.prank(alice);
            finalPaid = claims.claimRecovery(2, alice);
        } else {
            vm.prank(alice);
            firstPaid = claims.claimRecovery(2, alice);
            assertEq(firstPaid, ordinaryAlice);
            assertEq(claims.claimableRecovery(2, bob), target.recoveryPool - firstPaid);
            vm.prank(bob);
            finalPaid = claims.claimRecovery(2, bob);
        }
        assertEq(firstPaid + finalPaid, target.recoveryPool);
        assertTrue(claims.recoveryClaimed(2, alice));
        assertTrue(claims.recoveryClaimed(2, bob));
        assertEq(claims.claimableRecovery(2, alice), 0);
        assertEq(claims.claimableRecovery(2, bob), 0);

        vm.prank(alice);
        vm.expectRevert(Errors.AlreadyClaimed.selector);
        claims.claimRecovery(2, alice);
    }

    function _buy(address buyer, uint256 price) internal {
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        settlement.settleRound();
    }
}
