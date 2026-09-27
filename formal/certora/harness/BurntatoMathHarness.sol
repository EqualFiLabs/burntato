// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibMath} from "../../../src/libraries/LibMath.sol";
import {BuybackQuote, PurchaseAllocation} from "../../../src/shared/Types.sol";

/// @notice Thin executable surface over the production arithmetic used by CVL.
contract BurntatoMathHarness {
    function mulBpsDown(uint256 amount, uint256 bps) external pure returns (uint256) {
        return LibMath.mulBpsDown(amount, bps);
    }

    function mulBpsUp(uint256 amount, uint256 bps) external pure returns (uint256) {
        return LibMath.mulBpsUp(amount, bps);
    }

    function linearEarned(uint256 maximum, uint256 heldSeconds, uint256 vestingDuration)
        external
        pure
        returns (uint256)
    {
        return LibMath.linearEarned(maximum, heldSeconds, vestingDuration);
    }

    function diminishingTimeout(
        uint256 initialTimeout,
        uint256 decay,
        uint256 minimumTimeout,
        uint256 priorPurchases
    ) external pure returns (uint256) {
        return LibMath.diminishingTimeout(initialTimeout, decay, minimumTimeout, priorPurchases);
    }

    function splitRecovery(uint256 amount, uint256 treasuryBps)
        external
        pure
        returns (uint256 burned, uint256 treasury)
    {
        return LibMath.splitRecovery(amount, treasuryBps);
    }

    function purchaseSplit(
        uint256 amount,
        uint256 winnerBps,
        uint256 nextRoundWinnerBps,
        uint256 recoveryBps,
        uint256 buybackBps,
        uint256 operatorBps
    )
        external
        pure
        returns (
            uint256 winner,
            uint256 nextRoundWinner,
            uint256 recovery,
            uint256 treasury,
            uint256 buyback,
            uint256 operator
        )
    {
        PurchaseAllocation memory allocation =
            LibMath.splitPurchase(amount, winnerBps, nextRoundWinnerBps, recoveryBps, buybackBps, operatorBps);
        return (
            allocation.winner,
            allocation.nextRoundWinner,
            allocation.recovery,
            allocation.treasury,
            allocation.buyback,
            allocation.operator
        );
    }

    function buybackQuote(uint256 reserve, uint256 maxSpend, uint256 callerRewardBps)
        external
        pure
        returns (uint256 grossSlice, uint256 requestedInput, uint256 callerReward)
    {
        BuybackQuote memory quote = LibMath.quoteBuyback(reserve, maxSpend, callerRewardBps);
        return (quote.grossSlice, quote.requestedInput, quote.callerReward);
    }

    function recoveryClaimAmount(
        uint256 recoveryPool,
        uint256 totalCommitted,
        uint256 claimedCommitments,
        uint256 recoveryPaid,
        uint256 committed
    ) external pure returns (uint256 amount) {
        return LibMath.recoveryClaimAmount(
            recoveryPool, totalCommitted, claimedCommitments, recoveryPaid, committed
        );
    }

    function splitSchedule(uint256 amount, uint256 roundCount)
        external
        pure
        returns (uint256 perRound, uint256 firstRoundRemainder)
    {
        return LibMath.splitSchedule(amount, roundCount);
    }
}
