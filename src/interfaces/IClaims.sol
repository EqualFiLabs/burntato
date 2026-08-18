// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IClaims {
    event WinnerClaimed(uint256 indexed roundId, address indexed winner, address indexed recipient, uint256 amount);
    event RecoveryClaimed(uint256 indexed roundId, address indexed account, address indexed recipient, uint256 amount);
    event TreasuryEthClaimed(address indexed recipient, uint256 amount);
    event TreasuryPotatoClaimed(address indexed recipient, uint256 amount);

    function claimWinner(uint256 roundId, address recipient) external returns (uint256 amount);
    function claimRecovery(uint256 roundId, address recipient) external returns (uint256 amount);
    function winnerClaimed(uint256 roundId) external view returns (bool);
    function recoveryClaimed(uint256 roundId, address account) external view returns (bool);
    function claimableRecovery(uint256 roundId, address account) external view returns (uint256 amount);
    function claimTreasury() external returns (uint256 amount);
    function claimTreasuryPotato() external returns (uint256 amount);
    function treasuryRecipient() external view returns (address);
    function treasuryEthAvailable() external view returns (uint256);
    function treasuryPotatoAvailable() external view returns (uint256);
}
