// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibToken} from "../libraries/LibToken.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract GameFacet is IGame {
    function buyPotato() external payable {
        if (LibProtocolStorage.governance().purchasesPaused) revert Errors.PurchasesPaused();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = _currentOrStartRound(gs);
        if (round.currentHolder != address(0) && block.timestamp >= round.deadline) revert Errors.RoundExpired();
        if (msg.value != round.nextPrice) revert Errors.IncorrectPayment(round.nextPrice, msg.value);

        if (round.currentHolder != address(0)) _finalizeEmission(round);

        uint256 winnerShare = LibMath.mulBpsDown(msg.value, Constants.WINNER_BPS);
        uint256 recoveryShare = LibMath.mulBpsDown(msg.value, Constants.RECOVERY_BPS);
        uint256 treasuryShare = msg.value - winnerShare - recoveryShare;
        round.winnerPool += winnerShare;
        round.recoveryPool += recoveryShare;
        LibProtocolStorage.treasury().purchaseEth += treasuryShare;

        round.currentHolder = msg.sender;
        round.holderSince = uint64(block.timestamp);
        round.deadline = uint64(block.timestamp + Constants.ROUND_TIMEOUT);
        round.purchaseIndex += 1;
        round.holderMaxReward = LibMath.mulBpsDown(round.remainingEmission, Constants.EMISSION_STEP_BPS);
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
        if (block.timestamp - round.holderSince < Constants.EMISSION_VESTING_DURATION) {
            revert Errors.VestingIncomplete();
        }
        earned = _finalizeEmission(round);
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
        return LibMath.linearEarned(round.holderMaxReward, block.timestamp - round.holderSince);
    }

    function _currentOrStartRound(LibProtocolStorage.GameStorage storage gs) private returns (Round storage round) {
        if (gs.currentRoundId == 0) {
            gs.currentRoundId = 1;
            round = gs.rounds[1];
            round.roundId = 1;
            round.config.startingPrice = gs.config.startingPrice;
            round.config.priceIncreaseBps = gs.config.priceIncreaseBps;
            round.nextPrice = round.config.startingPrice;
            round.remainingEmission = Constants.ROUND_EMISSION_BUDGET;
            emit RoundStarted(1, round.nextPrice, round.remainingEmission);
        } else {
            round = gs.rounds[gs.currentRoundId];
        }
    }

    function _finalizeEmission(Round storage round) private returns (uint256 earned) {
        if (round.holderEmissionFinalized) return round.holderEarned;
        uint256 heldSeconds = block.timestamp - round.holderSince;
        earned = LibMath.linearEarned(round.holderMaxReward, heldSeconds);
        round.holderEmissionFinalized = true;
        round.holderEarned = earned;
        round.remainingEmission -= earned;
        round.emittedPotato += earned;
        LibToken.mint(round.currentHolder, earned);
        emit EmissionFinalized(round.roundId, round.currentHolder, round.holderMaxReward, earned, heldSeconds);
    }
}
