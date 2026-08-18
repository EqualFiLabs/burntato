// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ITreasuryRewards} from "../interfaces/ITreasuryRewards.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {Errors} from "../shared/Errors.sol";
import {RewardSchedule} from "../shared/Types.sol";

contract TreasuryRewardsFacet is ITreasuryRewards {
    function setRewardAllocator(address newAllocator) external {
        LibDiamond.enforceAuthority();
        if (newAllocator != address(0)) LibRecipients.enforceExternal(newAllocator);
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        address previous = trs.allocator;
        trs.allocator = newAllocator;
        emit RewardAllocatorUpdated(previous, newAllocator);
    }

    function allocateTreasuryRewards(uint256 amount, uint256 firstRoundId, uint256 roundCount)
        external
        returns (uint256 scheduleId)
    {
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        _enforceAllocator(trs);
        if (amount == 0 || roundCount == 0) revert Errors.ZeroAmount();

        uint256 currentRoundId = LibProtocolStorage.game().currentRoundId;
        if (currentRoundId == type(uint256).max) revert Errors.InvalidRound(currentRoundId);
        uint256 earliestRound = currentRoundId + 1;
        if (firstRoundId < earliestRound) revert Errors.InvalidRound(firstRoundId);
        if (roundCount > type(uint256).max - firstRoundId) revert Errors.InvalidRound(firstRoundId);
        if (IPotatoToken(address(this)).balanceOf(msg.sender) < amount) revert Errors.InsufficientBalance();

        uint256 lastRoundId = firstRoundId + roundCount - 1;
        uint256 perRound = amount / roundCount;
        uint256 remainder = amount - perRound * roundCount;

        IPotatoToken(address(this)).protocolTransfer(msg.sender, address(this), amount);
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        ts.potatoInventory += amount;
        ts.reservedPotato += amount;
        trs.escrowedPotato += amount;

        if (perRound != 0) {
            trs.perRoundIncrease[firstRoundId] += perRound;
            trs.perRoundDecrease[lastRoundId + 1] += perRound;
        }
        if (remainder != 0) trs.firstRoundRemainder[firstRoundId] += remainder;

        scheduleId = ++trs.nextScheduleId;
        trs.schedules[scheduleId] = RewardSchedule({
            scheduleId: scheduleId,
            amount: amount,
            firstRoundId: firstRoundId,
            roundCount: roundCount,
            perRound: perRound,
            firstRoundRemainder: remainder,
            canceledFromRound: 0,
            canceledAmount: 0
        });
        emit TreasuryRewardsAllocated(scheduleId, msg.sender, amount, firstRoundId, roundCount, perRound, remainder);
    }

    function cancelTreasuryRewards(uint256 scheduleId) external returns (uint256 amountReleased) {
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        _enforceAllocator(trs);
        RewardSchedule storage schedule = trs.schedules[scheduleId];
        if (schedule.scheduleId == 0) revert Errors.InvalidSchedule(scheduleId);
        if (schedule.canceledFromRound != 0) revert Errors.NothingToCancel();

        uint256 currentRoundId = LibProtocolStorage.game().currentRoundId;
        if (currentRoundId == type(uint256).max) revert Errors.NothingToCancel();
        uint256 earliestRound = currentRoundId + 1;
        uint256 cancelFrom = earliestRound > schedule.firstRoundId ? earliestRound : schedule.firstRoundId;
        uint256 lastRoundId = schedule.firstRoundId + schedule.roundCount - 1;
        if (cancelFrom > lastRoundId) revert Errors.NothingToCancel();

        uint256 canceledRounds = lastRoundId - cancelFrom + 1;
        amountReleased = schedule.perRound * canceledRounds;
        if (cancelFrom == schedule.firstRoundId) {
            amountReleased += schedule.firstRoundRemainder;
            trs.firstRoundRemainder[schedule.firstRoundId] -= schedule.firstRoundRemainder;
        }
        if (amountReleased == 0) revert Errors.NothingToCancel();
        if (schedule.perRound != 0) {
            trs.perRoundDecrease[cancelFrom] += schedule.perRound;
            trs.perRoundIncrease[lastRoundId + 1] += schedule.perRound;
        }

        schedule.canceledFromRound = cancelFrom;
        schedule.canceledAmount = amountReleased;
        trs.escrowedPotato -= amountReleased;
        LibProtocolStorage.treasury().reservedPotato -= amountReleased;
        emit TreasuryRewardsCanceled(scheduleId, cancelFrom, amountReleased);
    }

    function rewardAllocator() external view returns (address) {
        return LibProtocolStorage.treasuryRewards().allocator;
    }

    function treasuryRewardsReserved() external view returns (uint256) {
        return LibProtocolStorage.treasuryRewards().escrowedPotato;
    }

    function rewardSchedule(uint256 scheduleId) external view returns (RewardSchedule memory) {
        return LibProtocolStorage.treasuryRewards().schedules[scheduleId];
    }

    function nextTreasuryRewardBudget() external view returns (uint256 roundId, uint256 budget) {
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        uint256 currentRoundId = LibProtocolStorage.game().currentRoundId;
        if (currentRoundId == type(uint256).max) revert Errors.InvalidRound(currentRoundId);
        roundId = currentRoundId + 1;
        budget = trs.activePerRound + trs.perRoundIncrease[roundId] - trs.perRoundDecrease[roundId]
            + trs.firstRoundRemainder[roundId];
    }

    function _enforceAllocator(LibProtocolStorage.TreasuryRewardsStorage storage trs) private view {
        if (msg.sender != trs.allocator || msg.sender == address(0)) revert Errors.NotRewardAllocator(msg.sender);
    }
}
