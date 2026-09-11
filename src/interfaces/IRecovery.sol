// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IRecovery {
    event RecoveryCommitted(uint256 indexed roundId, address indexed account, uint256 amount, uint256 totalCommitted);
    event StalledRecoveryWithdrawn(
        uint256 indexed roundId, address indexed account, uint256 amount, uint256 totalCommitted
    );
    event RecoveryReserveFunded(
        address indexed funder, uint256 indexed targetRoundId, uint256 amount, uint256 reserveEth
    );
    event RecoveryReserveApplied(uint256 indexed roundId, uint256 amount, uint256 recoveryPool);

    function commitRecovery(uint256 amount) external;
    function fundRecoveryReserve(uint256 expectedRoundId) external payable;
    function recoveryReserveEth() external view returns (uint256);
    function withdrawStalledRecovery(uint256 targetRoundId) external returns (uint256 amount);
    function recoveryCommitment(uint256 roundId, address account) external view returns (uint256);
    function totalRecoveryCommitment(uint256 roundId) external view returns (uint256);
    function stalledRecoveryWithdrawalAt(uint256 targetRoundId) external view returns (uint256 availableAt);
}
