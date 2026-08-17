// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ISettlement} from "../interfaces/ISettlement.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract SettlementFacet is ISettlement {
    function settleRound() external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        uint256 roundId = gs.currentRoundId;
        Round storage round = gs.rounds[roundId];
        if (round.currentHolder == address(0)) revert Errors.NoCurrentHolder();
        if (round.settled) revert Errors.RoundAlreadySettled();
        if (block.timestamp < round.deadline) revert Errors.RoundNotExpired();

        LibGame.finalizeEmission(round);
        round.settled = true;

        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        uint256 totalCommitted = rs.totalCommitments[roundId];
        round.totalCommitted = totalCommitted;
        uint256 burned;
        uint256 treasuryPotato;
        uint256 carry;
        if (totalCommitted == 0) {
            carry = round.recoveryPool;
        } else {
            (burned, treasuryPotato) = LibMath.splitRecovery(totalCommitted, round.config.recoveryTreasuryBps);
            IPotatoToken(address(this)).protocolBurn(address(this), burned);
            LibProtocolStorage.treasury().potatoInventory += treasuryPotato;
        }

        emit RoundSettled(
            roundId, round.currentHolder, round.winnerPool, round.recoveryPool, totalCommitted, burned, treasuryPotato
        );

        uint256 nextRoundId = roundId + 1;
        gs.currentRoundId = nextRoundId;
        LibGame.activateRound(nextRoundId, carry);
    }
}
