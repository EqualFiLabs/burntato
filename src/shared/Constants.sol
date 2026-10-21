// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

library Constants {
    uint256 internal constant BPS = 10_000;
    uint16 internal constant MAX_BUYBACK_CALLER_REWARD_BPS = 100;
    uint256 internal constant STALLED_RECOVERY_DELAY = 30 days;
}
