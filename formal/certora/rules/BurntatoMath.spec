methods {
    function mulBpsDown(uint256, uint256) external returns (uint256) envfree;
    function mulBpsUp(uint256, uint256) external returns (uint256) envfree;
    function linearEarned(uint256, uint256, uint256) external returns (uint256) envfree;
    function diminishingTimeout(uint256, uint256, uint256, uint256) external returns (uint256) envfree;
    function splitRecovery(uint256, uint256) external returns (uint256, uint256) envfree;
    function purchaseSplit(uint256, uint256, uint256, uint256, uint256, uint256)
        external returns (uint256, uint256, uint256, uint256, uint256, uint256) envfree;
    function buybackQuote(uint256, uint256, uint256) external returns (uint256, uint256, uint256) envfree;
    function recoveryClaimAmount(uint256, uint256, uint256, uint256, uint256)
        external returns (uint256) envfree;
    function splitSchedule(uint256, uint256) external returns (uint256, uint256) envfree;
}

rule bpsRoundingBounds(uint256 amount, uint256 bps) {
    require bps <= 10000;

    uint256 down = mulBpsDown(amount, bps);
    uint256 up = mulBpsUp(amount, bps);

    assert down <= amount, "rounded-down BPS share exceeds its source";
    assert up <= amount, "rounded-up BPS share exceeds its source";
    assert down <= up, "rounding directions are inverted";
    assert up - down <= 1, "rounding directions differ by more than one wei";
}

rule bpsBoundaryIdentities(uint256 amount) {
    assert mulBpsDown(amount, 0) == 0, "zero BPS rounded down is not zero";
    assert mulBpsUp(amount, 0) == 0, "zero BPS rounded up is not zero";
    assert mulBpsDown(amount, 10000) == amount, "full BPS rounded down is not identity";
    assert mulBpsUp(amount, 10000) == amount, "full BPS rounded up is not identity";
}

rule purchaseSplitConservesEveryWei(
    uint256 amount,
    uint256 winnerBps,
    uint256 nextRoundWinnerBps,
    uint256 recoveryBps,
    uint256 buybackBps,
    uint256 operatorBps
) {
    require winnerBps <= 10000;
    require nextRoundWinnerBps <= 10000;
    require recoveryBps <= 10000;
    require buybackBps <= 10000;
    require operatorBps <= 10000;
    require winnerBps + nextRoundWinnerBps + recoveryBps + buybackBps + operatorBps <= 10000;

    uint256 winner;
    uint256 nextRoundWinner;
    uint256 recovery;
    uint256 treasury;
    uint256 buyback;
    uint256 operator;
    winner, nextRoundWinner, recovery, treasury, buyback, operator =
        purchaseSplit(amount, winnerBps, nextRoundWinnerBps, recoveryBps, buybackBps, operatorBps);

    assert winner + nextRoundWinner + recovery + treasury + buyback + operator == amount,
        "purchase split loses or creates wei";
}

rule purchaseDustBelongsToTreasury(
    uint256 amount,
    uint256 winnerBps,
    uint256 nextRoundWinnerBps,
    uint256 recoveryBps,
    uint256 buybackBps,
    uint256 operatorBps
) {
    require winnerBps <= 10000;
    require nextRoundWinnerBps <= 10000;
    require recoveryBps <= 10000;
    require buybackBps <= 10000;
    require operatorBps <= 10000;
    require winnerBps + nextRoundWinnerBps + recoveryBps + buybackBps + operatorBps <= 10000;

    uint256 winner;
    uint256 nextRoundWinner;
    uint256 recovery;
    uint256 treasury;
    uint256 buyback;
    uint256 operator;
    winner, nextRoundWinner, recovery, treasury, buyback, operator =
        purchaseSplit(amount, winnerBps, nextRoundWinnerBps, recoveryBps, buybackBps, operatorBps);

    uint256 treasuryBps = 10000 - winnerBps - nextRoundWinnerBps - recoveryBps - buybackBps - operatorBps;
    uint256 nominalTreasury = mulBpsDown(amount, treasuryBps);
    assert treasury >= nominalTreasury, "purchase dust is not assigned to Treasury";
    assert treasury - nominalTreasury <= 5, "purchase dust exceeds five floor remainders";
}

rule linearEarnedBoundsAndSaturates(uint256 maximum, uint256 heldSeconds, uint256 vestingDuration) {
    require vestingDuration > 0;

    uint256 earned = linearEarned(maximum, heldSeconds, vestingDuration);
    assert earned <= maximum, "earned emission exceeds holder maximum";
    assert heldSeconds < vestingDuration || earned == maximum, "vesting does not saturate";
    assert heldSeconds != 0 || earned == 0, "zero holding time earns emission";
}

rule linearEarnedIsMonotonic(uint256 maximum, uint256 earlier, uint256 later, uint256 vestingDuration) {
    require vestingDuration > 0;
    require earlier <= later;

    assert linearEarned(maximum, earlier, vestingDuration) <= linearEarned(maximum, later, vestingDuration),
        "earned emission decreases as holding time increases";
}

rule diminishingTimeoutStaysInBounds(
    uint256 initialTimeout,
    uint256 decay,
    uint256 minimumTimeout,
    uint256 priorPurchases
) {
    require initialTimeout > 0;
    require minimumTimeout > 0;
    require minimumTimeout <= initialTimeout;
    require decay <= initialTimeout;

    uint256 duration = diminishingTimeout(initialTimeout, decay, minimumTimeout, priorPurchases);
    assert duration >= minimumTimeout, "timeout decays below its configured floor";
    assert duration <= initialTimeout, "timeout exceeds its configured start";
}

rule diminishingTimeoutIsMonotonic(
    uint256 initialTimeout,
    uint256 decay,
    uint256 minimumTimeout,
    uint256 earlierPurchases,
    uint256 laterPurchases
) {
    require initialTimeout > 0;
    require minimumTimeout > 0;
    require minimumTimeout <= initialTimeout;
    require decay <= initialTimeout;
    require earlierPurchases <= laterPurchases;

    assert diminishingTimeout(initialTimeout, decay, minimumTimeout, earlierPurchases)
        >= diminishingTimeout(initialTimeout, decay, minimumTimeout, laterPurchases),
        "timeout increases with purchase count";
}

rule recoverySplitConserves(uint256 amount, uint256 treasuryBps) {
    require treasuryBps <= 10000;

    uint256 burned;
    uint256 treasury;
    burned, treasury = splitRecovery(amount, treasuryBps);

    assert burned + treasury == amount, "Recovery split loses or creates POTATO";
    assert burned <= amount, "burn exceeds commitment";
    assert treasury <= amount, "Treasury inventory exceeds commitment";
}

rule buybackQuoteConservesGrossSlice(uint256 reserve, uint256 maxSpend, uint256 callerRewardBps) {
    require callerRewardBps <= 100;

    uint256 grossSlice;
    uint256 requestedInput;
    uint256 callerReward;
    grossSlice, requestedInput, callerReward = buybackQuote(reserve, maxSpend, callerRewardBps);

    assert grossSlice == (reserve < maxSpend ? reserve : maxSpend), "gross slice is not the configured minimum";
    assert requestedInput <= grossSlice, "requested input exceeds gross slice";
    assert callerReward <= grossSlice - requestedInput, "caller reward exceeds reserved compensation";
    assert grossSlice - requestedInput - callerReward <= 2, "buyback rounding residue exceeds two wei";
}

rule finalRecoveryClaimGetsExactRemainder(
    uint256 recoveryPool,
    uint256 totalCommitted,
    uint256 claimedCommitments,
    uint256 recoveryPaid,
    uint256 committed
) {
    require totalCommitted > 0;
    require claimedCommitments <= totalCommitted;
    require committed > 0;
    require committed <= totalCommitted - claimedCommitments;
    require claimedCommitments + committed == totalCommitted;
    require recoveryPaid <= recoveryPool;

    assert recoveryClaimAmount(recoveryPool, totalCommitted, claimedCommitments, recoveryPaid, committed)
        == recoveryPool - recoveryPaid,
        "final Recovery claim does not receive the exact remainder";
}

rule ordinaryRecoveryClaimCannotOverpay(
    uint256 recoveryPool,
    uint256 totalCommitted,
    uint256 claimedCommitments,
    uint256 recoveryPaid,
    uint256 committed
) {
    require totalCommitted > 0;
    require claimedCommitments <= totalCommitted;
    require committed > 0;
    require committed < totalCommitted - claimedCommitments;
    require recoveryPaid <= recoveryPool;

    uint256 amount = recoveryClaimAmount(
        recoveryPool, totalCommitted, claimedCommitments, recoveryPaid, committed
    );
    assert amount <= recoveryPool, "ordinary Recovery claim exceeds the complete pool";
}

rule rewardScheduleSplitConserves(uint256 amount, uint256 roundCount) {
    require roundCount > 0;

    uint256 perRound;
    uint256 firstRoundRemainder;
    perRound, firstRoundRemainder = splitSchedule(amount, roundCount);

    assert perRound * roundCount + firstRoundRemainder == amount,
        "reward schedule split loses or creates POTATO";
    assert firstRoundRemainder < roundCount, "reward schedule remainder is not canonical";
}
