// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

library LibMarketMath {
    function launchLiquidity(uint256 potatoSeed, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (uint256 liquidity)
    {
        if (potatoSeed == 0 || potatoSeed > type(uint128).max) return 0;
        uint256 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        liquidity = potatoSeed * FixedPoint96.Q96 / (sqrtUpper - sqrtLower);
        if (liquidity > type(uint128).max) return 0;
    }
}
