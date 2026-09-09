// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibMath} from "../../../src/libraries/LibMath.sol";
import {Constants} from "../../../src/shared/Constants.sol";

/// @notice Thin executable surface over the production arithmetic used by CVL.
contract BurntatoMathHarness {
    function mulBpsDown(uint128 amount, uint16 bps) external pure returns (uint256) {
        return LibMath.mulBpsDown(amount, bps);
    }

    function mulBpsUp(uint128 amount, uint16 bps) external pure returns (uint256) {
        return LibMath.mulBpsUp(amount, bps);
    }

    function linearEarned(uint128 maximum, uint64 heldSeconds, uint64 vestingDuration)
        external
        pure
        returns (uint256)
    {
        return LibMath.linearEarned(maximum, heldSeconds, vestingDuration);
    }

    function diminishingTimeout(
        uint64 initialTimeout,
        uint64 decay,
        uint64 minimumTimeout,
        uint64 priorPurchases
    ) external pure returns (uint256) {
        return LibMath.diminishingTimeout(initialTimeout, decay, minimumTimeout, priorPurchases);
    }

    function splitRecovery(uint128 amount, uint16 treasuryBps)
        external
        pure
        returns (uint256 burned, uint256 treasury)
    {
        return LibMath.splitRecovery(amount, treasuryBps);
    }

    function purchaseSplit(
        uint128 amount,
        uint16 winnerBps,
        uint16 recoveryBps,
        uint16 buybackBps,
        uint16 operatorBps
    ) external pure returns (uint256 winner, uint256 recovery, uint256 treasury, uint256 buyback, uint256 operator) {
        require(uint256(winnerBps) + recoveryBps + buybackBps + operatorBps <= Constants.BPS);
        winner = LibMath.mulBpsDown(amount, winnerBps);
        recovery = LibMath.mulBpsDown(amount, recoveryBps);
        buyback = LibMath.mulBpsDown(amount, buybackBps);
        operator = LibMath.mulBpsDown(amount, operatorBps);
        treasury = amount - winner - recovery - buyback - operator;
    }
}
