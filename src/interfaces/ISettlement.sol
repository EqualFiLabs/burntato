// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

interface ISettlement {
    event RoundSettled(
        uint256 indexed roundId,
        address indexed winner,
        uint256 winnerPool,
        uint256 recoveryPool,
        uint256 totalCommitted,
        uint256 burnedPotato,
        uint256 staticsRecovered
    );

    function settleRound() external;
}
