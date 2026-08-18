// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {RewardSchedule} from "../shared/Types.sol";

interface ITreasuryRewards {
    event RewardAllocatorUpdated(address indexed previousAllocator, address indexed newAllocator);
    event TreasuryRewardsAllocated(
        uint256 indexed scheduleId,
        address indexed allocator,
        uint256 amount,
        uint256 firstRoundId,
        uint256 roundCount,
        uint256 perRound,
        uint256 firstRoundRemainder
    );
    event TreasuryRewardsCanceled(
        uint256 indexed scheduleId, uint256 indexed canceledFromRound, uint256 amountReleased
    );
    event TreasuryRewardRoundActivated(uint256 indexed roundId, uint256 budget, uint256 totalEscrowed);
    event TreasuryRewardFinalized(
        uint256 indexed roundId, address indexed holder, uint256 maxReward, uint256 earned, uint256 heldSeconds
    );
    event TreasuryRewardReleased(uint256 indexed roundId, uint256 amount, uint256 totalEscrowed);

    function setRewardAllocator(address newAllocator) external;
    function allocateTreasuryRewards(uint256 amount, uint256 firstRoundId, uint256 roundCount)
        external
        returns (uint256 scheduleId);
    function cancelTreasuryRewards(uint256 scheduleId) external returns (uint256 amountReleased);
    function rewardAllocator() external view returns (address);
    function treasuryRewardsReserved() external view returns (uint256);
    function rewardSchedule(uint256 scheduleId) external view returns (RewardSchedule memory);
    function nextTreasuryRewardBudget() external view returns (uint256 roundId, uint256 budget);
}
