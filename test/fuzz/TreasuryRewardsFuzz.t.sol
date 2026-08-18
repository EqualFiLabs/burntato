// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {RewardSchedule} from "../../src/shared/Types.sol";

contract TreasuryRewardsFuzzTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");

    IClaims internal claims;
    IGame internal game;
    IPotatoToken internal potato;
    ITreasuryRewards internal rewards;

    function setUp() public {
        _deployCore();
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        rewards = ITreasuryRewards(address(diamond));
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();
        vm.prank(authority);
        rewards.setRewardAllocator(alice);
    }

    function testFuzz_FundedScheduleAndCancellationConserveEveryBaseUnit(uint96 rawAmount, uint8 rawRoundCount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 10_000 ether);
        uint256 roundCount = bound(uint256(rawRoundCount), 1, 50);
        uint256 supplyBefore = potato.totalSupply();

        vm.prank(alice);
        uint256 scheduleId = rewards.allocateTreasuryRewards(amount, 2, roundCount);

        RewardSchedule memory schedule = rewards.rewardSchedule(scheduleId);
        assertEq(schedule.perRound * roundCount + schedule.firstRoundRemainder, amount);
        assertLt(schedule.firstRoundRemainder, roundCount);
        (, uint256 nextBudget) = rewards.nextTreasuryRewardBudget();
        assertEq(nextBudget, schedule.perRound + schedule.firstRoundRemainder);
        assertEq(rewards.treasuryRewardsReserved(), amount);
        assertEq(claims.treasuryPotatoAvailable(), 0);

        vm.prank(alice);
        assertEq(rewards.cancelTreasuryRewards(scheduleId), amount);
        assertEq(rewards.treasuryRewardsReserved(), 0);
        assertEq(claims.treasuryPotatoAvailable(), amount);
        assertEq(potato.totalSupply(), supplyBefore);
    }
}
