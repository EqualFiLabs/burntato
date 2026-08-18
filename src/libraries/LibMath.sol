// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../shared/Constants.sol";

library LibMath {
    function mulBpsDown(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return Math.mulDiv(amount, bps, Constants.BPS);
    }

    function mulBpsUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return Math.mulDiv(amount, bps, Constants.BPS, Math.Rounding.Ceil);
    }

    function linearEarned(uint256 maxReward, uint256 heldSeconds, uint256 vestingDuration)
        internal
        pure
        returns (uint256)
    {
        uint256 capped = heldSeconds > vestingDuration ? vestingDuration : heldSeconds;
        return Math.mulDiv(maxReward, capped, vestingDuration);
    }

    function diminishingTimeout(uint256 initialTimeout, uint256 decay, uint256 minimumTimeout, uint256 priorPurchases)
        internal
        pure
        returns (uint256)
    {
        if (decay == 0 || priorPurchases == 0 || initialTimeout == minimumTimeout) return initialTimeout;

        uint256 maximumReduction = initialTimeout - minimumTimeout;
        if (priorPurchases > maximumReduction / decay) return minimumTimeout;

        uint256 reduction = priorPurchases * decay;
        return reduction >= maximumReduction ? minimumTimeout : initialTimeout - reduction;
    }

    function splitRecovery(uint256 amount, uint256 treasuryBps)
        internal
        pure
        returns (uint256 burned, uint256 treasuryPotato)
    {
        treasuryPotato = mulBpsDown(amount, treasuryBps);
        burned = amount - treasuryPotato;
    }
}
