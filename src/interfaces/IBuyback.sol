// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {BuybackConfig} from "../shared/Types.sol";

interface IBuyback {
    event BuybackConfigUpdated(BuybackConfig config);
    event BuybackReserveFunded(address indexed funder, uint256 amount, uint256 reserveEth);
    event BuybackExecuted(
        address indexed caller,
        address indexed reserveRecipient,
        uint256 grossSlice,
        uint256 ethSpent,
        uint256 staticsAcquired,
        uint256 potatoReserveFunded,
        uint256 callerReward,
        uint256 reserveEth
    );

    event BuybackMarketSet(address indexed poolManager, address indexed weth, bytes32 indexed poolId);
    function setBuybackMarket(address poolManager, address weth, PoolKey calldata key) external;
    function buybackMarket() external view returns (address poolManager, address weth, PoolKey memory key);
    function setBuybackConfig(BuybackConfig calldata config) external;
    function buybackConfig() external view returns (BuybackConfig memory config);
    function fundBuybackReserve() external payable;
    function buybackReserveEth() external view returns (uint256);
    function lastBuybackBlock() external view returns (uint256);
    function buyback() external returns (uint256 amountOut);
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}
