// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library Constants {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MIN_TIMELOCK_DELAY = 1 days;

    uint8 internal constant POTATO_DECIMALS = 18;

    uint24 internal constant POOL_LP_FEE = 0;
    uint16 internal constant HOOK_FEE_BPS = 100;
    address internal constant LOCKED_LP_RECIPIENT = 0x000000000000000000000000000000000000dEaD;
}
