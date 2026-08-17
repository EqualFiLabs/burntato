// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IMarket {
    event MarketConfigured(
        address indexed hook,
        address indexed poolManager,
        address positionManager,
        address permit2,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        uint256 nativeSeed,
        uint256 potatoSeed
    );
    event MarketLaunched(
        bytes32 indexed poolId,
        uint128 liquidity,
        uint256 nativeUsed,
        uint256 potatoUsed,
        address indexed lockedRecipient
    );
    event HookRevenueRecorded(uint256 amount);

    struct MarketConfig {
        address hook;
        address poolManager;
        address positionManager;
        address permit2;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        uint256 nativeSeed;
        uint256 potatoSeed;
    }

    function configureMarket(MarketConfig calldata config) external;
    function launchMarket() external returns (bytes32 poolId, uint128 liquidity);
    function recordHookRevenue() external payable;
    function marketConfig() external view returns (MarketConfig memory config);
    function canonicalPoolKey() external view returns (PoolKey memory key);
    function marketState() external view returns (bytes32 poolId, bool configured, bool launching, bool launched);
    function marketLaunching() external view returns (bool);
    function marketReady() external view returns (bool);
    function lockedLpRecipient() external pure returns (address);
}
