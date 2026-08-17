// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IRecovery {
    event RecoveryCommitted(uint256 indexed roundId, address indexed account, uint256 amount, uint256 totalCommitted);

    function commitRecovery(uint256 amount) external;
    function recoveryCommitment(uint256 roundId, address account) external view returns (uint256);
    function totalRecoveryCommitment(uint256 roundId) external view returns (uint256);
}
