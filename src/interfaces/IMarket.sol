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
        uint256 potatoSeed
    );
    event MarketCurvePinned(bytes32 indexed curveHash, uint256 positionCount);
    event MarketLaunched(
        bytes32 indexed poolId,
        bytes32 indexed curveHash,
        uint256 positionCount,
        uint256 potatoUsed,
        address indexed lockedRecipient
    );

    struct MarketCurve {
        int24 canonicalTickLower;
        int24 canonicalTickUpper;
        uint16 positions;
        uint16 shareBps;
    }

    struct MarketConfig {
        address hook;
        address poolManager;
        address positionManager;
        address permit2;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        uint256 potatoSeed;
    }

    function configureMarket(MarketConfig calldata config) external;
    function launchMarket() external returns (bytes32 poolId, uint256 positionCount, uint256 potatoUsed);
    function marketConfig() external view returns (MarketConfig memory config);
    function marketCurves() external pure returns (MarketCurve[] memory curves);
    function marketCurveHash() external pure returns (bytes32 curveHash);
    function canonicalPoolKey() external view returns (PoolKey memory key);
    function marketState() external view returns (bytes32 poolId, bool configured, bool launching, bool launched);
    function marketLaunching() external view returns (bool);
    function marketReady() external view returns (bool);
    function lockedLpRecipient() external pure returns (address);
}
