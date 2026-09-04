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
        LibProtocolStorage.ReentrancyStorage storage rs = LibProtocolStorage.reentrancy();
        if (rs.status == 2) revert Errors.Reentrancy();
        rs.status = 2;

        if (LibProtocolStorage.governance().purchasesPaused) revert Errors.PurchasesPaused();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = _currentOrStartRound(gs);
        if (round.currentHolder != address(0) && block.timestamp >= round.deadline) revert Errors.RoundExpired();
        if (msg.value != round.nextPrice) revert Errors.IncorrectPayment(round.nextPrice, msg.value);

        if (round.currentHolder != address(0)) LibGame.finalizeEmission(round);

        uint256 winnerShare = LibMath.mulBpsDown(msg.value, round.config.winnerBps);
        uint256 recoveryShare = LibMath.mulBpsDown(msg.value, round.config.recoveryBps);
        uint256 buybackShare = LibMath.mulBpsDown(msg.value, round.config.buybackBps);
        uint256 operatorShare = LibMath.mulBpsDown(msg.value, round.config.operatorPurchaseBps);
        uint256 treasuryShare = msg.value - winnerShare - recoveryShare - buybackShare - operatorShare;
        round.winnerPool += winnerShare;
        round.recoveryPool += recoveryShare;
        LibProtocolStorage.treasury().purchaseEth += treasuryShare;
        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth += buybackShare;
        emit BuybackFunded(round.roundId, buybackShare, bs.reserveEth);

        round.currentHolder = msg.sender;
        round.holderSince = block.timestamp;
        uint256 resetDuration = LibMath.diminishingTimeout(
            round.config.roundTimeout,
            round.config.roundTimeoutDecay,
            round.config.minimumRoundTimeout,
            round.purchaseIndex
        );
        round.deadline = block.timestamp + resetDuration;
        round.purchaseIndex += 1;
        round.holderMaxReward = LibMath.mulBpsDown(round.remainingEmission, round.config.emissionStepBps);
        round.holderTreasuryMaxReward =
            LibMath.mulBpsDown(round.remainingTreasuryEmission, round.config.emissionStepBps);
        round.holderEarned = 0;
        round.holderTreasuryEarned = 0;
        round.holderEmissionFinalized = false;
        round.nextPrice = msg.value + LibMath.mulBpsUp(msg.value, round.config.priceIncreaseBps);

        emit PotatoPurchased(
            round.roundId, msg.sender, msg.value, round.purchaseIndex, round.holderMaxReward, round.deadline
        );

        if (operatorShare != 0) {
            address router = LibProtocolStorage.operatorRevenue().router;
            if (router == address(0)) revert Errors.InvalidProtocolConfig();
            emit OperatorPurchaseRevenueQueued(round.roundId, router, operatorShare);
            (bool success,) = router.call{value: operatorShare}("");
            if (!success) revert Errors.OperatorRevenueTransferFailed(router, operatorShare);
        }
        rs.status = 1;
    }

    function materializeMaturedEmission() external returns (uint256 baseEarned, uint256 treasuryEarned) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[gs.currentRoundId];
        if (round.currentHolder == address(0)) revert Errors.NoCurrentHolder();
        if (round.holderEmissionFinalized) revert Errors.AlreadyFinalized();
        if (block.timestamp - round.holderSince < round.config.emissionVestingDuration) {
            revert Errors.VestingIncomplete();
        }
        (baseEarned, treasuryEarned) = LibGame.finalizeEmission(round);
    }

    function currentRoundId() external view returns (uint256) {
        return LibProtocolStorage.game().currentRoundId;
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return LibProtocolStorage.game().rounds[roundId];
    }

    function currentEarnedEmission() external view returns (uint256 baseEarned, uint256 treasuryEarned) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[gs.currentRoundId];
        if (round.currentHolder == address(0)) return (0, 0);
        if (round.holderEmissionFinalized) return (round.holderEarned, round.holderTreasuryEarned);
        baseEarned = LibMath.linearEarned(
            round.holderMaxReward, block.timestamp - round.holderSince, round.config.emissionVestingDuration
        );
        treasuryEarned = LibMath.linearEarned(
            round.holderTreasuryMaxReward, block.timestamp - round.holderSince, round.config.emissionVestingDuration
        );
    }

    function purchaseOperatorRewardsRouter() external view returns (address) {
        return LibProtocolStorage.operatorRevenue().router;
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
