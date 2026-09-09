methods {
    function mulBpsDown(uint128, uint16) external returns (uint256) envfree;
    function mulBpsUp(uint128, uint16) external returns (uint256) envfree;
    function linearEarned(uint128, uint64, uint64) external returns (uint256) envfree;
    function diminishingTimeout(uint64, uint64, uint64, uint64) external returns (uint256) envfree;
    function splitRecovery(uint128, uint16) external returns (uint256, uint256) envfree;
    function purchaseSplit(uint128, uint16, uint16, uint16, uint16)
        external returns (uint256, uint256, uint256, uint256, uint256) envfree;
}

rule bpsRoundingBounds(uint128 amount, uint16 bps) {
    require bps <= 10000;

    uint256 down = mulBpsDown(amount, bps);
    uint256 up = mulBpsUp(amount, bps);

    assert down <= amount, "rounded-down BPS share exceeds its source";
    assert up <= amount, "rounded-up BPS share exceeds its source";
    assert down <= up, "rounding directions are inverted";
    assert up - down <= 1, "rounding directions differ by more than one wei";
}

rule fullBpsIsIdentity(uint128 amount) {
    assert mulBpsDown(amount, 10000) == amount, "full BPS rounded down is not identity";
    assert mulBpsUp(amount, 10000) == amount, "full BPS rounded up is not identity";
}

rule purchaseSplitConservesEveryWei(
    uint128 amount,
    uint16 winnerBps,
    uint16 recoveryBps,
    uint16 buybackBps,
    uint16 operatorBps
) {
    require winnerBps <= 10000;
    require recoveryBps <= 10000;
    require buybackBps <= 10000;
    require operatorBps <= 10000;
    require winnerBps + recoveryBps + buybackBps + operatorBps <= 10000;

    uint256 winner;
    uint256 recovery;
    uint256 treasury;
    uint256 buyback;
    uint256 operator;
    winner, recovery, treasury, buyback, operator =
        purchaseSplit(amount, winnerBps, recoveryBps, buybackBps, operatorBps);

    assert winner + recovery + treasury + buyback + operator == amount,
        "purchase split loses or creates wei";
}

rule purchaseDustBelongsToTreasury(
    uint128 amount,
    uint16 winnerBps,
    uint16 recoveryBps,
    uint16 buybackBps,
    uint16 operatorBps
) {
    require winnerBps <= 10000;
    require recoveryBps <= 10000;
    require buybackBps <= 10000;
    require operatorBps <= 10000;
    require winnerBps + recoveryBps + buybackBps + operatorBps <= 10000;

    uint256 winner;
    uint256 recovery;
    uint256 treasury;
    uint256 buyback;
    uint256 operator;
    winner, recovery, treasury, buyback, operator =
        purchaseSplit(amount, winnerBps, recoveryBps, buybackBps, operatorBps);

    uint16 treasuryBps = assert_uint16(10000 - winnerBps - recoveryBps - buybackBps - operatorBps);
    uint256 nominalTreasury = mulBpsDown(amount, treasuryBps);
    assert treasury >= nominalTreasury, "purchase dust is not assigned to Treasury";
    assert treasury - nominalTreasury <= 4, "purchase dust exceeds four floor remainders";
}

rule linearEarnedBoundsAndSaturates(uint128 maximum, uint64 heldSeconds, uint64 vestingDuration) {
    require vestingDuration > 0;

    uint256 earned = linearEarned(maximum, heldSeconds, vestingDuration);
    assert earned <= maximum, "earned emission exceeds holder maximum";
    assert heldSeconds < vestingDuration || earned == maximum, "vesting does not saturate";
    assert heldSeconds != 0 || earned == 0, "zero holding time earns emission";
}

rule linearEarnedIsMonotonic(uint128 maximum, uint64 earlier, uint64 later, uint64 vestingDuration) {
    require vestingDuration > 0;
    require earlier <= later;

    assert linearEarned(maximum, earlier, vestingDuration) <= linearEarned(maximum, later, vestingDuration),
        "earned emission decreases as holding time increases";
}

rule diminishingTimeoutStaysInBounds(
    uint64 initialTimeout,
    uint64 decay,
    uint64 minimumTimeout,
    uint64 priorPurchases
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
    uint64 initialTimeout,
    uint64 decay,
    uint64 minimumTimeout,
    uint64 earlierPurchases,
    uint64 laterPurchases
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

rule recoverySplitConserves(uint128 amount, uint16 treasuryBps) {
    require treasuryBps <= 10000;

    uint256 burned;
    uint256 treasury;
    burned, treasury = splitRecovery(amount, treasuryBps);

    assert burned + treasury == amount, "Recovery split loses or creates POTATO";
    assert burned <= amount, "burn exceeds commitment";
    assert treasury <= amount, "Treasury inventory exceeds commitment";
}
