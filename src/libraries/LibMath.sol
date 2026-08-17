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

    function splitRecovery(uint256 amount, uint256 treasuryBps)
        internal
        pure
        returns (uint256 burned, uint256 treasuryPotato)
    {
        treasuryPotato = mulBpsDown(amount, treasuryBps);
        burned = amount - treasuryPotato;
    }
}
