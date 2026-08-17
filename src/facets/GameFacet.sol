// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract GameFacet is IGame {
    function buyPotato() external payable {
        if (LibProtocolStorage.governance().purchasesPaused) revert Errors.PurchasesPaused();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = _currentOrStartRound(gs);
        if (round.currentHolder != address(0) && block.timestamp >= round.deadline) revert Errors.RoundExpired();
        if (msg.value != round.nextPrice) revert Errors.IncorrectPayment(round.nextPrice, msg.value);

        if (round.currentHolder != address(0)) LibGame.finalizeEmission(round);

        uint256 winnerShare = LibMath.mulBpsDown(msg.value, round.config.winnerBps);
        uint256 recoveryShare = LibMath.mulBpsDown(msg.value, round.config.recoveryBps);
        uint256 treasuryShare = msg.value - winnerShare - recoveryShare;
        round.winnerPool += winnerShare;
        round.recoveryPool += recoveryShare;
        LibProtocolStorage.treasury().purchaseEth += treasuryShare;

        round.currentHolder = msg.sender;
        round.holderSince = block.timestamp;
        round.deadline = block.timestamp + round.config.roundTimeout;
        round.purchaseIndex += 1;
        round.holderMaxReward = LibMath.mulBpsDown(round.remainingEmission, round.config.emissionStepBps);
        round.holderEarned = 0;
        round.holderEmissionFinalized = false;
        round.nextPrice = msg.value + LibMath.mulBpsUp(msg.value, round.config.priceIncreaseBps);

        emit PotatoPurchased(
            round.roundId, msg.sender, msg.value, round.purchaseIndex, round.holderMaxReward, round.deadline
        );
    }

    function materializeMaturedEmission() external returns (uint256 earned) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[gs.currentRoundId];
        if (round.currentHolder == address(0)) revert Errors.NoCurrentHolder();
        if (round.holderEmissionFinalized) revert Errors.AlreadyFinalized();
        if (block.timestamp - round.holderSince < round.config.emissionVestingDuration) {
            revert Errors.VestingIncomplete();
        }
        earned = LibGame.finalizeEmission(round);
    }

    function currentRoundId() external view returns (uint256) {
        return LibProtocolStorage.game().currentRoundId;
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return LibProtocolStorage.game().rounds[roundId];
    }

    function currentEarnedEmission() external view returns (uint256) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[gs.currentRoundId];
        if (round.currentHolder == address(0)) return 0;
        if (round.holderEmissionFinalized) return round.holderEarned;
        return LibMath.linearEarned(
            round.holderMaxReward, block.timestamp - round.holderSince, round.config.emissionVestingDuration
        );
    }

    function _currentOrStartRound(LibProtocolStorage.GameStorage storage gs) private returns (Round storage round) {
        if (gs.currentRoundId == 0) {
            gs.currentRoundId = 1;
            round = LibGame.activateRound(1, 0);
        } else {
            round = gs.rounds[gs.currentRoundId];
        }
    }
}
