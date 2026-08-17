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
        assertEq(potato.balanceOf(address(diamond)), treasuryPotato);

        uint256 expectedAlice = target.recoveryPool * aliceCommitment / totalCommitted;
        uint256 expectedBob = target.recoveryPool * bobCommitment / totalCommitted;
        if (bobClaimsFirst) {
            vm.prank(bob);
            assertEq(claims.claimRecovery(2, bob), expectedBob);
            vm.prank(alice);
            assertEq(claims.claimRecovery(2, alice), expectedAlice);
        } else {
            vm.prank(alice);
            assertEq(claims.claimRecovery(2, alice), expectedAlice);
            vm.prank(bob);
            assertEq(claims.claimRecovery(2, bob), expectedBob);
        }
        assertLe(expectedAlice + expectedBob, target.recoveryPool);

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
