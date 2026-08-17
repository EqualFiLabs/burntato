// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IPotatoToken {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PotatoBurned(address indexed account, uint256 amount);
    event PoolManagerAllowanceAuthorized(uint256 amount);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burn(uint256 amount) external;
    function authorizePoolManagerTransfer(uint256 amount) external;
    function transientPoolManagerAllowance() external view returns (uint256);
}
