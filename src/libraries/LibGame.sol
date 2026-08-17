// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibConfig} from "./LibConfig.sol";
import {LibMath} from "./LibMath.sol";
import {LibProtocolStorage} from "./LibProtocolStorage.sol";
import {Round} from "../shared/Types.sol";

library LibGame {
    function snapshotFutureRound(uint256 roundId) internal returns (Round storage round) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        round = gs.rounds[roundId];
        if (round.roundId == 0) {
            round.roundId = roundId;
            LibConfig.snapshot(gs.config, round.config);
        }
    }

    function activateRound(uint256 roundId, uint256 recoveryCarryIn) internal returns (Round storage round) {
        round = snapshotFutureRound(roundId);
        round.activated = true;
        round.nextPrice = round.config.startingPrice;
        round.remainingEmission = round.config.roundEmissionBudget;
        round.recoveryCarryIn = recoveryCarryIn;
        round.recoveryPool = recoveryCarryIn;
        snapshotFutureRound(roundId + 1);
        emit IGame.RoundStarted(roundId, round.nextPrice, round.remainingEmission);
    }

    function finalizeEmission(Round storage round) internal returns (uint256 earned) {
        if (round.holderEmissionFinalized) return round.holderEarned;
        uint256 heldSeconds = block.timestamp - round.holderSince;
        earned = LibMath.linearEarned(round.holderMaxReward, heldSeconds, round.config.emissionVestingDuration);
        round.holderEmissionFinalized = true;
        round.holderEarned = earned;
        round.remainingEmission -= earned;
        round.emittedPotato += earned;
        IPotatoToken(address(this)).protocolMint(round.currentHolder, earned);
        emit IGame.EmissionFinalized(round.roundId, round.currentHolder, round.holderMaxReward, earned, heldSeconds);
    }
}
