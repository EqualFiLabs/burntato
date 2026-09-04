// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library Constants {
    uint256 internal constant BPS = 10_000;
    uint16 internal constant MAX_HOOK_FEE_BPS = 200;
    uint16 internal constant MAX_BUYBACK_CALLER_REWARD_BPS = 100;
    uint256 internal constant STALLED_RECOVERY_DELAY = 30 days;

    uint8 internal constant POTATO_DECIMALS = 18;

    uint24 internal constant POOL_LP_FEE = 0;
    address internal constant LOCKED_LP_RECIPIENT = 0x000000000000000000000000000000000000dEaD;
}
