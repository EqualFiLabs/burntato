// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

interface IPotatoToken {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Wrapped(address indexed account, uint256 staticsDeposited, uint256 potatoMinted);
    event Unwrapped(address indexed account, address indexed recipient, uint256 potatoBurned, uint256 staticsReturned);
    event RewardReserveFunded(address indexed funder, uint256 staticsDeposited, uint256 potatoMinted, uint256 reserve);
    event PublicWrapCapSet(uint256 previousCap, uint256 cap);
    event DistributorSet(address indexed account, bool allowed);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function underlying() external view returns (address);
    function backingBalance() external view returns (uint256);
    function publicWrapCap() external view returns (uint256);
    function publicWrapOutstanding() external view returns (uint256);
    function availablePublicWrapCapacity() external view returns (uint256);
    function rewardReserve() external view returns (uint256);
    function availableRewardInventory() external view returns (uint256);
    function nextRoundFundingStatus()
        external
        view
        returns (uint256 roundId, uint256 required, uint256 available, bool funded);
    function setPublicWrapCap(uint256 amount) external;
    function wrap(uint256 amount) external;
    function unwrap(uint256 amount) external;
    function fundRewardReserve(uint256 amount) external;
    function protocolCreditRewardReserve(uint256 amount, uint256 backingBefore) external;
    function protocolRedeemRecovery(uint256 amount) external;
    function isDistributor(address account) external view returns (bool);
    function setDistributor(address account, bool allowed) external;
    function protocolTransfer(address from, address to, uint256 amount) external;
}
