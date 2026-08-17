// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library Constants {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant ROUND_TIMEOUT = 1 hours;
    uint256 internal constant MIN_TIMELOCK_DELAY = 1 days;

    uint8 internal constant POTATO_DECIMALS = 18;
    uint256 internal constant POTATO_SCALE = 1e18;
    uint256 internal constant ROUND_EMISSION_BUDGET = 100_000 * POTATO_SCALE;
    uint16 internal constant EMISSION_STEP_BPS = 1_000;
    uint256 internal constant EMISSION_VESTING_DURATION = 120 seconds;

    uint16 internal constant WINNER_BPS = 2_500;
    uint16 internal constant RECOVERY_BPS = 5_000;
    uint16 internal constant TREASURY_BPS = 2_500;
    uint16 internal constant RECOVERY_BURN_BPS = 9_000;
    uint16 internal constant RECOVERY_TREASURY_BPS = 1_000;

    uint24 internal constant POOL_LP_FEE = 0;
    uint16 internal constant HOOK_FEE_BPS = 100;
    address internal constant LOCKED_LP_RECIPIENT = 0x000000000000000000000000000000000000dEaD;
}
