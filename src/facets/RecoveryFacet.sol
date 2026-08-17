// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRecovery} from "../interfaces/IRecovery.sol";
import {LibGame} from "../libraries/LibGame.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibToken} from "../libraries/LibToken.sol";
import {Errors} from "../shared/Errors.sol";

contract RecoveryFacet is IRecovery {
    function commitRecovery(uint256 amount) external {
        if (LibProtocolStorage.governance().commitmentsPaused) revert Errors.CommitmentsPaused();
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (gs.currentRoundId == 0) revert Errors.InvalidRound(0);
        uint256 targetRoundId = gs.currentRoundId + 1;
        if (gs.rounds[targetRoundId].remainingEmission != 0) revert Errors.CommitmentClosed(targetRoundId);

        LibGame.snapshotFutureRound(targetRoundId);
        LibToken.protocolMove(msg.sender, address(this), amount);
        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        rs.commitments[targetRoundId][msg.sender] += amount;
        rs.totalCommitments[targetRoundId] += amount;
        emit RecoveryCommitted(targetRoundId, msg.sender, amount, rs.totalCommitments[targetRoundId]);
    }

    function recoveryCommitment(uint256 roundId, address account) external view returns (uint256) {
        return LibProtocolStorage.recovery().commitments[roundId][account];
    }

    function totalRecoveryCommitment(uint256 roundId) external view returns (uint256) {
        return LibProtocolStorage.recovery().totalCommitments[roundId];
    }
}
