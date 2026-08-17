// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BuybackConfig} from "../shared/Types.sol";

interface IBuyback {
    event BuybackConfigUpdated(BuybackConfig config);
    event BuybackExecuted(
        address indexed caller,
        address indexed treasuryRecipient,
        uint256 grossSlice,
        uint256 ethSpent,
        uint256 potatoBought,
        uint256 callerReward,
        uint256 reserveEth
    );

    function setBuybackConfig(BuybackConfig calldata config) external;
    function buybackConfig() external view returns (BuybackConfig memory config);
    function buybackReserveEth() external view returns (uint256);
    function lastBuybackBlock() external view returns (uint256);
    function buyback() external returns (uint256 amountOut);
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}
