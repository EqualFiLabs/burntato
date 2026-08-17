// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IClaims} from "../interfaces/IClaims.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract ClaimsFacet is IClaims {
    modifier nonReentrant() {
        LibProtocolStorage.ReentrancyStorage storage rs = LibProtocolStorage.reentrancy();
        if (rs.status == 2) revert Errors.Reentrancy();
        rs.status = 2;
        _;
        rs.status = 1;
    }

    function claimWinner(uint256 roundId, address recipient) external nonReentrant returns (uint256 amount) {
        LibRecipients.enforceExternal(recipient);
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[roundId];
        if (!round.settled) revert Errors.InvalidRound(roundId);
        if (msg.sender != round.currentHolder) revert Errors.UnauthorizedWinner(msg.sender);
        if (gs.winnerClaimed[roundId]) revert Errors.AlreadyClaimed();
        amount = round.winnerPool;
        if (amount == 0) revert Errors.NothingToClaim();
        gs.winnerClaimed[roundId] = true;
        _sendNative(recipient, amount);
        emit WinnerClaimed(roundId, msg.sender, recipient, amount);
    }

    function claimRecovery(uint256 roundId, address recipient) external nonReentrant returns (uint256 amount) {
        LibRecipients.enforceExternal(recipient);
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[roundId];
        if (!round.settled || round.totalCommitted == 0) revert Errors.InvalidRound(roundId);
        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        if (rs.claimed[roundId][msg.sender]) revert Errors.AlreadyClaimed();
        uint256 committed = rs.commitments[roundId][msg.sender];
        if (committed == 0) revert Errors.NothingToClaim();
        amount = Math.mulDiv(round.recoveryPool, committed, round.totalCommitted);
        rs.claimed[roundId][msg.sender] = true;
        rs.recoveryPaid[roundId] += amount;
        _sendNative(recipient, amount);
        emit RecoveryClaimed(roundId, msg.sender, recipient, amount);
    }

    function claimTreasury() external nonReentrant returns (uint256 amount) {
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        LibRecipients.enforceExternal(ts.recipient);
        amount = ts.purchaseEth > ts.reservedEth ? ts.purchaseEth - ts.reservedEth : 0;
        if (amount == 0) revert Errors.NothingToClaim();
        ts.purchaseEth -= amount;
        _sendNative(ts.recipient, amount);
        emit TreasuryEthClaimed(ts.recipient, amount);
    }

    function claimTreasuryPotato() external nonReentrant returns (uint256 amount) {
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        LibRecipients.enforceExternal(ts.recipient);
        amount = ts.potatoInventory > ts.reservedPotato ? ts.potatoInventory - ts.reservedPotato : 0;
        if (amount == 0) revert Errors.NothingToClaim();
        ts.potatoInventory -= amount;
        IPotatoToken(address(this)).protocolTransfer(address(this), ts.recipient, amount);
        emit TreasuryPotatoClaimed(ts.recipient, amount);
    }

    function treasuryRecipient() external view returns (address) {
        return LibProtocolStorage.treasury().recipient;
    }

    function treasuryEthAvailable() external view returns (uint256) {
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        return ts.purchaseEth > ts.reservedEth ? ts.purchaseEth - ts.reservedEth : 0;
    }

    function treasuryPotatoAvailable() external view returns (uint256) {
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        return ts.potatoInventory > ts.reservedPotato ? ts.potatoInventory - ts.reservedPotato : 0;
    }

    function _sendNative(address recipient, uint256 amount) private {
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert Errors.NativeTransferFailed();
    }
}
