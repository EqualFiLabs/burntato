// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../shared/Constants.sol";
import {BuybackQuote, PurchaseAllocation} from "../shared/Types.sol";

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

    function splitPurchase(
        uint256 amount,
        uint256 winnerBps,
        uint256 nextRoundWinnerBps,
        uint256 recoveryBps,
        uint256 buybackBps,
        uint256 operatorBps
    ) internal pure returns (PurchaseAllocation memory allocation) {
        allocation.winner = mulBpsDown(amount, winnerBps);
        allocation.nextRoundWinner = mulBpsDown(amount, nextRoundWinnerBps);
        allocation.recovery = mulBpsDown(amount, recoveryBps);
        allocation.buyback = mulBpsDown(amount, buybackBps);
        allocation.operator = mulBpsDown(amount, operatorBps);
        allocation.treasury = amount - allocation.winner - allocation.nextRoundWinner - allocation.recovery
            - allocation.buyback - allocation.operator;
    }

    function quoteBuyback(uint256 reserve, uint256 maxSpend, uint256 callerRewardBps)
        internal
        pure
        returns (BuybackQuote memory quote)
    {
        quote.grossSlice = reserve < maxSpend ? reserve : maxSpend;
        quote.requestedInput = Math.mulDiv(quote.grossSlice, Constants.BPS, Constants.BPS + callerRewardBps);
        quote.callerReward = mulBpsDown(quote.requestedInput, callerRewardBps);
    }

    function recoveryClaimAmount(
        uint256 recoveryPool,
        uint256 totalCommitted,
        uint256 claimedCommitments,
        uint256 recoveryPaid,
        uint256 committed
    ) internal pure returns (uint256 amount) {
        if (committed == 0) return 0;
        uint256 newClaimedCommitments = claimedCommitments + committed;
        if (newClaimedCommitments == totalCommitted) return recoveryPool - recoveryPaid;
        return Math.mulDiv(recoveryPool, committed, totalCommitted);
    }

    function splitSchedule(uint256 amount, uint256 roundCount)
        internal
        pure
        returns (uint256 perRound, uint256 firstRoundRemainder)
    {
        perRound = amount / roundCount;
        firstRoundRemainder = amount - perRound * roundCount;
    }
}
