// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Constants} from "../shared/Constants.sol";

library LibMath {
    function mulBpsDown(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return Math.mulDiv(amount, bps, Constants.BPS);
    }

    function mulBpsUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return Math.mulDiv(amount, bps, Constants.BPS, Math.Rounding.Ceil);
    }

    function linearEarned(uint256 maxReward, uint256 heldSeconds) internal pure returns (uint256) {
        uint256 capped =
            heldSeconds > Constants.EMISSION_VESTING_DURATION ? Constants.EMISSION_VESTING_DURATION : heldSeconds;
        return Math.mulDiv(maxReward, capped, Constants.EMISSION_VESTING_DURATION);
    }

    function splitRecovery(uint256 amount) internal pure returns (uint256 burned, uint256 treasuryPotato) {
        treasuryPotato = mulBpsDown(amount, Constants.RECOVERY_TREASURY_BPS);
        burned = amount - treasuryPotato;
    }
}
