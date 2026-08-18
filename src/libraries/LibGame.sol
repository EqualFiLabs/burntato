// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {ITreasuryRewards} from "../interfaces/ITreasuryRewards.sol";
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
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        trs.activePerRound += trs.perRoundIncrease[roundId];
        trs.activePerRound -= trs.perRoundDecrease[roundId];
        uint256 treasuryBudget = trs.activePerRound + trs.firstRoundRemainder[roundId];
        round.activated = true;
        round.nextPrice = round.config.startingPrice;
        round.remainingEmission = round.config.roundEmissionBudget;
        round.treasuryEmissionBudget = treasuryBudget;
        round.remainingTreasuryEmission = treasuryBudget;
        round.recoveryCarryIn = recoveryCarryIn;
        round.recoveryPool = recoveryCarryIn;
        snapshotFutureRound(roundId + 1);
        emit IGame.RoundStarted(roundId, round.nextPrice, round.remainingEmission);
        emit ITreasuryRewards.TreasuryRewardRoundActivated(roundId, treasuryBudget, trs.escrowedPotato);
    }

    function finalizeEmission(Round storage round) internal returns (uint256 baseEarned, uint256 treasuryEarned) {
        if (round.holderEmissionFinalized) return (round.holderEarned, round.holderTreasuryEarned);
        uint256 heldSeconds = block.timestamp - round.holderSince;
        baseEarned = LibMath.linearEarned(round.holderMaxReward, heldSeconds, round.config.emissionVestingDuration);
        treasuryEarned =
            LibMath.linearEarned(round.holderTreasuryMaxReward, heldSeconds, round.config.emissionVestingDuration);
        round.holderEmissionFinalized = true;
        round.holderEarned = baseEarned;
        round.holderTreasuryEarned = treasuryEarned;
        round.remainingEmission -= baseEarned;
        round.emittedPotato += baseEarned;
        round.remainingTreasuryEmission -= treasuryEarned;
        round.treasuryEmittedPotato += treasuryEarned;
        if (baseEarned != 0) IPotatoToken(address(this)).protocolMint(round.currentHolder, baseEarned);
        if (treasuryEarned != 0) {
            LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
            LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
            ts.potatoInventory -= treasuryEarned;
            ts.reservedPotato -= treasuryEarned;
            trs.escrowedPotato -= treasuryEarned;
            IPotatoToken(address(this)).protocolTransfer(address(this), round.currentHolder, treasuryEarned);
        }
        emit IGame.EmissionFinalized(round.roundId, round.currentHolder, round.holderMaxReward, baseEarned, heldSeconds);
        emit ITreasuryRewards.TreasuryRewardFinalized(
            round.roundId, round.currentHolder, round.holderTreasuryMaxReward, treasuryEarned, heldSeconds
        );
    }

    function releaseTreasuryEmission(Round storage round) internal returns (uint256 released) {
        released = round.remainingTreasuryEmission;
        if (released == 0) return 0;
        round.remainingTreasuryEmission = 0;
        round.treasuryReleasedPotato += released;
        LibProtocolStorage.TreasuryRewardsStorage storage trs = LibProtocolStorage.treasuryRewards();
        trs.escrowedPotato -= released;
        LibProtocolStorage.treasury().reservedPotato -= released;
        emit ITreasuryRewards.TreasuryRewardReleased(round.roundId, released, trs.escrowedPotato);
    }
}
