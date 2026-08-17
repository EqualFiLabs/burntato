// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {LibMath} from "./LibMath.sol";
import {LibProtocolStorage} from "./LibProtocolStorage.sol";
import {LibToken} from "./LibToken.sol";
import {Constants} from "../shared/Constants.sol";
import {Round} from "../shared/Types.sol";

library LibGame {
    function snapshotFutureRound(uint256 roundId) internal returns (Round storage round) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        round = gs.rounds[roundId];
        if (round.roundId == 0) {
            round.roundId = roundId;
            round.config.startingPrice = gs.config.startingPrice;
            round.config.priceIncreaseBps = gs.config.priceIncreaseBps;
        }
    }

    function activateRound(uint256 roundId, uint256 recoveryCarryIn) internal returns (Round storage round) {
        round = snapshotFutureRound(roundId);
        round.nextPrice = round.config.startingPrice;
        round.remainingEmission = Constants.ROUND_EMISSION_BUDGET;
        round.recoveryCarryIn = recoveryCarryIn;
        round.recoveryPool = recoveryCarryIn;
        snapshotFutureRound(roundId + 1);
        emit IGame.RoundStarted(roundId, round.nextPrice, round.remainingEmission);
    }

    function finalizeEmission(Round storage round) internal returns (uint256 earned) {
        if (round.holderEmissionFinalized) return round.holderEarned;
        uint256 heldSeconds = block.timestamp - round.holderSince;
        earned = LibMath.linearEarned(round.holderMaxReward, heldSeconds);
        round.holderEmissionFinalized = true;
        round.holderEarned = earned;
        round.remainingEmission -= earned;
        round.emittedPotato += earned;
        LibToken.mint(round.currentHolder, earned);
        emit IGame.EmissionFinalized(round.roundId, round.currentHolder, round.holderMaxReward, earned, heldSeconds);
    }
}
