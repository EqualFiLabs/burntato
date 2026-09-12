// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMarket} from "../interfaces/IMarket.sol";
import {Errors} from "../shared/Errors.sol";
import {LibMarketMath} from "./LibMarketMath.sol";

library BurntatoLaunchCurves {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant CURVE_COUNT = 6;
    uint256 internal constant POSITION_COUNT = 56;
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant INITIAL_TICK = 170_280;
    int24 internal constant TICK_LOWER = -887_220;
    int24 internal constant TICK_UPPER = INITIAL_TICK;

    struct LaunchPosition {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 potatoAmountMax;
    }

    function profile() internal pure returns (IMarket.MarketCurve[] memory curves) {
        curves = new IMarket.MarketCurve[](CURVE_COUNT);
        curves[0] = IMarket.MarketCurve({
            canonicalTickLower: -170_280, canonicalTickUpper: -153_000, positions: 11, shareBps: 250
        });
        curves[1] = IMarket.MarketCurve({
            canonicalTickLower: -160_980, canonicalTickUpper: -137_040, positions: 11, shareBps: 750
        });
        curves[2] = IMarket.MarketCurve({
            canonicalTickLower: -145_080, canonicalTickUpper: -118_500, positions: 11, shareBps: 1_250
        });
        curves[3] = IMarket.MarketCurve({
            canonicalTickLower: -126_600, canonicalTickUpper: -92_100, positions: 11, shareBps: 2_000
        });
        curves[4] = IMarket.MarketCurve({
            canonicalTickLower: -100_020, canonicalTickUpper: -65_580, positions: 11, shareBps: 4_250
        });
        curves[5] = IMarket.MarketCurve({
            canonicalTickLower: -65_580, canonicalTickUpper: 887_220, positions: 1, shareBps: 1_500
        });
    }

    function profileHash() internal pure returns (bytes32) {
        return keccak256(abi.encode(profile()));
    }

    function positionCount() internal pure returns (uint256) {
        return POSITION_COUNT;
    }

    function tickSpacing() internal pure returns (int24) {
        return TICK_SPACING;
    }

    function initialTick() internal pure returns (int24) {
        return INITIAL_TICK;
    }

    function tickLower() internal pure returns (int24) {
        return TICK_LOWER;
    }

    function tickUpper() internal pure returns (int24) {
        return TICK_UPPER;
    }

    function buildPositions(uint256 potatoSeed) internal pure returns (LaunchPosition[] memory positions) {
        IMarket.MarketCurve[] memory curves = profile();
        positions = new LaunchPosition[](POSITION_COUNT);

        uint256 totalShareBps;
        uint256 allocatedPotato;
        uint256 positionIndex;
        for (uint256 curveIndex; curveIndex < curves.length; ++curveIndex) {
            IMarket.MarketCurve memory curve = curves[curveIndex];
            totalShareBps += curve.shareBps;

            uint256 bandAmount = curveIndex + 1 == curves.length
                ? potatoSeed - allocatedPotato
                : Math.mulDiv(potatoSeed, curve.shareBps, BPS);
            allocatedPotato += bandAmount;

            uint256 amountPerPosition = bandAmount / curve.positions;
            uint256 bandRemainder = bandAmount % curve.positions;
            int24 farTick = -curve.canonicalTickUpper;
            int24 closeTick = -curve.canonicalTickLower;
            uint256 spread = uint256(uint24(closeTick - farTick));

            for (uint256 index; index < curve.positions; ++index) {
                uint256 potatoAmount = amountPerPosition + (index == 0 ? bandRemainder : 0);
                int256 rawUpper = int256(closeTick) - int256(index * spread / curve.positions);
                int24 upperTick = _alignUp(int24(rawUpper), TICK_SPACING);
                uint256 liquidity = LibMarketMath.launchLiquidity(potatoAmount, farTick, upperTick);
                if (
                    potatoAmount == 0 || potatoAmount > type(uint128).max || liquidity == 0
                        || liquidity > type(uint128).max || farTick >= upperTick
                ) revert Errors.InvalidMarketConfiguration();

                positions[positionIndex++] = LaunchPosition({
                    tickLower: farTick,
                    tickUpper: upperTick,
                    liquidity: uint128(liquidity),
                    potatoAmountMax: uint128(potatoAmount)
                });
            }
        }

        if (totalShareBps != BPS || allocatedPotato != potatoSeed || positionIndex != POSITION_COUNT) {
            revert Errors.InvalidMarketConfiguration();
        }
    }

    function _alignUp(int24 tick, int24 spacing) private pure returns (int24) {
        int24 remainder = tick % spacing;
        if (remainder == 0) return tick;
        return tick > 0 ? tick + spacing - remainder : tick - remainder;
    }
}
