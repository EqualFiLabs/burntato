// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Round} from "../shared/Types.sol";

interface IGame {
    event RoundStarted(uint256 indexed roundId, uint256 startingPrice, uint256 remainingEmission);
    event PotatoPurchased(
        uint256 indexed roundId,
        address indexed buyer,
        uint256 price,
        uint256 purchaseIndex,
        uint256 maxReward,
        uint256 deadline
    );
    event EmissionFinalized(
        uint256 indexed roundId, address indexed holder, uint256 maxReward, uint256 earned, uint256 heldSeconds
    );
    event BuybackFunded(uint256 indexed roundId, uint256 amount, uint256 reserveEth);
    event OperatorPurchaseRevenueQueued(uint256 indexed roundId, address indexed router, uint256 amount);
    event WinnerReserveFunded(
        address indexed funder, uint256 indexed targetRoundId, uint256 amount, uint256 roundReserveEth
    );
    event NextRoundWinnerFunded(
        uint256 indexed roundId, uint256 indexed targetRoundId, uint256 amount, uint256 roundReserveEth
    );
    event WinnerReserveApplied(uint256 indexed roundId, uint256 amount, uint256 winnerPool);

    function buyPotato() external payable;
    function fundWinnerReserve(uint256 targetRoundId) external payable;
    function fundRoundReserves(uint256 targetRoundId, uint256 winnerAmount, uint256 recoveryAmount) external payable;
    function winnerReserveEth() external view returns (uint256);
    function roundReserves(uint256 roundId) external view returns (uint256 winnerEth, uint256 recoveryEth);
    function materializeMaturedEmission() external returns (uint256 baseEarned, uint256 treasuryEarned);
    function currentRoundId() external view returns (uint256);
    function getRound(uint256 roundId) external view returns (Round memory);
    function currentEarnedEmission() external view returns (uint256 baseEarned, uint256 treasuryEarned);
    function purchaseOperatorRewardsRouter() external view returns (address);
}
