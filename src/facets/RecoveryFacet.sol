// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IRecovery} from "../interfaces/IRecovery.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract RecoveryFacet is IRecovery {
    function commitRecovery(uint256 amount) external {
        if (LibProtocolStorage.governance().commitmentsPaused) revert Errors.CommitmentsPaused();
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (gs.currentRoundId == 0) revert Errors.InvalidRound(0);
        uint256 targetRoundId = gs.currentRoundId + 1;
        if (gs.rounds[targetRoundId].activated) revert Errors.CommitmentClosed(targetRoundId);

        LibGame.snapshotFutureRound(targetRoundId);
        IPotatoToken(address(this)).protocolTransfer(msg.sender, address(this), amount);
        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        if (
            rs.stalledWithdrawalAt[targetRoundId] == 0 && gs.rounds[gs.currentRoundId].currentHolder == address(0)
                && gs.rounds[gs.currentRoundId].activated
        ) {
            rs.stalledWithdrawalAt[targetRoundId] = block.timestamp + Constants.STALLED_RECOVERY_DELAY;
        }
        rs.commitments[targetRoundId][msg.sender] += amount;
        rs.totalCommitments[targetRoundId] += amount;
        emit RecoveryCommitted(targetRoundId, msg.sender, amount, rs.totalCommitments[targetRoundId]);
    }

    function withdrawStalledRecovery(uint256 targetRoundId) external returns (uint256 amount) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (!_isStalledTarget(gs, targetRoundId)) revert Errors.RecoveryWithdrawalUnavailable(targetRoundId);

        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        uint256 availableAt = rs.stalledWithdrawalAt[targetRoundId];
        if (availableAt == 0) revert Errors.RecoveryWithdrawalUnavailable(targetRoundId);
        if (block.timestamp < availableAt) revert Errors.RecoveryWithdrawalTooSoon(availableAt);

        amount = rs.commitments[targetRoundId][msg.sender];
        if (amount == 0) revert Errors.NothingToCancel();
        rs.commitments[targetRoundId][msg.sender] = 0;
        uint256 remaining = rs.totalCommitments[targetRoundId] - amount;
        rs.totalCommitments[targetRoundId] = remaining;
        if (remaining == 0) delete rs.stalledWithdrawalAt[targetRoundId];

        IPotatoToken(address(this)).protocolTransfer(address(this), msg.sender, amount);
        emit StalledRecoveryWithdrawn(targetRoundId, msg.sender, amount, remaining);
    }

    function recoveryCommitment(uint256 roundId, address account) external view returns (uint256) {
        return LibProtocolStorage.recovery().commitments[roundId][account];
    }

    function totalRecoveryCommitment(uint256 roundId) external view returns (uint256) {
        return LibProtocolStorage.recovery().totalCommitments[roundId];
    }

    function stalledRecoveryWithdrawalAt(uint256 targetRoundId) external view returns (uint256 availableAt) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (!_isStalledTarget(gs, targetRoundId)) return 0;
        return LibProtocolStorage.recovery().stalledWithdrawalAt[targetRoundId];
    }

    function _isStalledTarget(LibProtocolStorage.GameStorage storage gs, uint256 targetRoundId)
        private
        view
        returns (bool)
    {
        uint256 currentRoundId = gs.currentRoundId;
        if (currentRoundId == 0 || targetRoundId != currentRoundId + 1) return false;
        Round storage current = gs.rounds[currentRoundId];
        return current.activated && current.currentHolder == address(0) && !gs.rounds[targetRoundId].activated;
    }
}
