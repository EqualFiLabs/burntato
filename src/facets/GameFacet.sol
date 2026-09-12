// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGame} from "../interfaces/IGame.sol";
import {IRecovery} from "../interfaces/IRecovery.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract GameFacet is IGame {
    function buyPotato() external payable {
        if (LibProtocolStorage.governance().paused) revert Errors.ProtocolPaused();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (!gs.initialized) revert Errors.PurchasesNotInitialized();
        LibProtocolStorage.ReentrancyStorage storage rs = LibProtocolStorage.reentrancy();
        if (rs.status == 2) revert Errors.Reentrancy();
        rs.status = 2;

        Round storage round = _currentOrStartRound(gs);
        if (round.currentHolder != address(0) && block.timestamp >= round.deadline) revert Errors.RoundExpired();
        if (msg.value != round.nextPrice) revert Errors.IncorrectPayment(round.nextPrice, msg.value);

        if (round.currentHolder != address(0)) LibGame.finalizeEmission(round);

        uint256 operatorShare;
        if (round.purchaseIndex == 0) {
            _fundWinnerReserve(gs, msg.sender, round.roundId + 1, msg.value, false);
        } else {
            uint256 winnerShare = LibMath.mulBpsDown(msg.value, round.config.winnerBps);
            uint256 nextRoundWinnerShare = LibMath.mulBpsDown(msg.value, round.config.nextRoundWinnerBps);
            uint256 recoveryShare = LibMath.mulBpsDown(msg.value, round.config.recoveryBps);
            uint256 buybackShare = LibMath.mulBpsDown(msg.value, round.config.buybackBps);
            operatorShare = LibMath.mulBpsDown(msg.value, round.config.operatorPurchaseBps);
            uint256 treasuryShare =
                msg.value - winnerShare - nextRoundWinnerShare - recoveryShare - buybackShare - operatorShare;
            round.winnerPool += winnerShare;
            round.recoveryPool += recoveryShare;
            _fundWinnerReserve(gs, msg.sender, round.roundId + 1, nextRoundWinnerShare, false);
            LibProtocolStorage.treasury().purchaseEth += treasuryShare;
            LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
            bs.reserveEth += buybackShare;
            emit BuybackFunded(round.roundId, buybackShare, bs.reserveEth);
        }

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

    function fundWinnerReserve(uint256 targetRoundId) external payable {
        if (LibDiamond.diamondStorage().selectorData[msg.sig].facet == address(0)) revert Errors.InvalidAddress();
        if (msg.value == 0) revert Errors.ZeroAmount();
        LibGame.enforceFutureRound(targetRoundId);
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        LibProtocolStorage.ReentrancyStorage storage rs = LibProtocolStorage.reentrancy();
        if (rs.status == 2) revert Errors.Reentrancy();
        rs.status = 2;
        _fundWinnerReserve(gs, msg.sender, targetRoundId, msg.value, true);
        rs.status = 1;
    }

    function fundRoundReserves(uint256 targetRoundId, uint256 winnerAmount, uint256 recoveryAmount) external payable {
        if (LibDiamond.diamondStorage().selectorData[msg.sig].facet == address(0)) revert Errors.InvalidAddress();
        if (msg.value == 0) revert Errors.ZeroAmount();
        if (winnerAmount > msg.value || recoveryAmount != msg.value - winnerAmount) {
            uint256 expected =
                winnerAmount > type(uint256).max - recoveryAmount ? type(uint256).max : winnerAmount + recoveryAmount;
            revert Errors.IncorrectPayment(expected, msg.value);
        }
        LibGame.enforceFutureRound(targetRoundId);
        LibProtocolStorage.ReentrancyStorage storage guard = LibProtocolStorage.reentrancy();
        if (guard.status == 2) revert Errors.Reentrancy();
        guard.status = 2;

        if (winnerAmount != 0) {
            _fundWinnerReserve(LibProtocolStorage.game(), msg.sender, targetRoundId, winnerAmount, true);
        }
        if (recoveryAmount != 0) {
            LibProtocolStorage.RecoveryStorage storage recovery = LibProtocolStorage.recovery();
            recovery.recoveryReserveEth += recoveryAmount;
            uint256 roundRecoveryReserve = recovery.recoveryReserveByRound[targetRoundId] + recoveryAmount;
            recovery.recoveryReserveByRound[targetRoundId] = roundRecoveryReserve;
            recovery.recoverySponsoredByRound[targetRoundId] += recoveryAmount;
            emit IRecovery.RecoveryReserveFunded(msg.sender, targetRoundId, recoveryAmount, roundRecoveryReserve);
        }
        guard.status = 1;
    }

    function winnerReserveEth() external view returns (uint256) {
        return LibProtocolStorage.game().winnerReserveEth;
    }

    function roundReserves(uint256 roundId) external view returns (uint256 winnerEth, uint256 recoveryEth) {
        winnerEth = LibProtocolStorage.game().winnerReserveByRound[roundId];
        recoveryEth = LibProtocolStorage.recovery().recoveryReserveByRound[roundId];
    }

    function roundFunding(uint256 roundId)
        external
        view
        returns (
            uint256 winnerReserve,
            uint256 recoveryReserve,
            uint256 winnerSponsoredEth,
            uint256 recoverySponsoredEth
        )
    {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        winnerReserve = gs.winnerReserveByRound[roundId];
        recoveryReserve = rs.recoveryReserveByRound[roundId];
        winnerSponsoredEth = gs.winnerSponsoredByRound[roundId];
        recoverySponsoredEth = rs.recoverySponsoredByRound[roundId];
    }

    function materializeMaturedEmission() external returns (uint256 baseEarned, uint256 treasuryEarned) {
        if (LibProtocolStorage.governance().paused) revert Errors.ProtocolPaused();
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

    function _fundWinnerReserve(
        LibProtocolStorage.GameStorage storage gs,
        address funder,
        uint256 targetRoundId,
        uint256 amount,
        bool direct
    ) private {
        if (amount == 0) return;
        gs.winnerReserveEth += amount;
        uint256 roundWinnerReserve = gs.winnerReserveByRound[targetRoundId] + amount;
        gs.winnerReserveByRound[targetRoundId] = roundWinnerReserve;
        if (direct) {
            gs.winnerSponsoredByRound[targetRoundId] += amount;
            emit WinnerReserveFunded(funder, targetRoundId, amount, roundWinnerReserve);
        } else {
            emit NextRoundWinnerFunded(targetRoundId - 1, targetRoundId, amount, roundWinnerReserve);
        }
    }
}
