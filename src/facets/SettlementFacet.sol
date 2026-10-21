// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {ISettlement} from "../interfaces/ISettlement.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibGuard} from "../libraries/LibGuard.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract SettlementFacet is ISettlement, LibGuard {
    function settleRound() external nonReentrant {
        if (LibProtocolStorage.governance().paused) revert Errors.ProtocolPaused();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        uint256 roundId = gs.currentRoundId;
        Round storage round = gs.rounds[roundId];
        if (round.currentHolder == address(0)) revert Errors.NoCurrentHolder();
        if (round.settled) revert Errors.RoundAlreadySettled();
        if (block.timestamp < round.deadline) revert Errors.RoundNotExpired();

        LibGame.finalizeEmission(round);
        LibGame.releaseTreasuryEmission(round);
        round.settled = true;

        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        uint256 totalCommitted = rs.totalCommitments[roundId];
        round.totalCommitted = totalCommitted;
        uint256 burned;
        uint256 staticsRecovered;
        uint256 carry;
        if (totalCommitted == 0) {
            carry = round.recoveryPool;
        } else {
            burned = totalCommitted;
            staticsRecovered = totalCommitted;
            IPotatoToken(address(this)).protocolRedeemRecovery(totalCommitted);
        }

        emit RoundSettled(
            roundId, round.currentHolder, round.winnerPool, round.recoveryPool, totalCommitted, burned, staticsRecovered
        );

        uint256 nextRoundId = roundId + 1;
        delete rs.stalledWithdrawalAt[nextRoundId];
        gs.currentRoundId = nextRoundId;
        LibGame.activateRound(nextRoundId, carry);
    }
}
