// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGovernance} from "../interfaces/IGovernance.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {ProtocolConfig} from "../shared/Types.sol";

contract GovernanceFacet is IGovernance {
    modifier onlyAuthority() {
        LibDiamond.enforceAuthority();
        _;
    }

    function authority() external view returns (address) {
        return LibDiamond.authority();
    }

    function guardian() external view returns (address) {
        return LibProtocolStorage.governance().guardian;
    }

    function purchasesPaused() external view returns (bool) {
        return LibProtocolStorage.governance().purchasesPaused;
    }

    function commitmentsPaused() external view returns (bool) {
        return LibProtocolStorage.governance().commitmentsPaused;
    }

    function protocolFinalized() external view returns (bool) {
        return LibDiamond.diamondStorage().cutsDisabled;
    }

    function protocolConfig() external view returns (ProtocolConfig memory) {
        return LibProtocolStorage.game().config;
    }

    function setAuthority(address newAuthority) external onlyAuthority {
        address previous = LibDiamond.authority();
        LibDiamond.transferAuthority(newAuthority);
        emit AuthorityTransferred(previous, newAuthority);
    }

    function setGuardian(address newGuardian) external onlyAuthority {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        address previous = gs.guardian;
        gs.guardian = newGuardian;
        emit GuardianUpdated(previous, newGuardian);
    }

    function setPauseState(bool pausePurchases, bool pauseCommitments) external {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        if (msg.sender != LibDiamond.authority()) {
            if (msg.sender != gs.guardian) revert Errors.NotGuardian(msg.sender);
            if ((gs.purchasesPaused && !pausePurchases) || (gs.commitmentsPaused && !pauseCommitments)) {
                revert Errors.UnpauseRequiresAuthority(msg.sender);
            }
        }
        gs.purchasesPaused = pausePurchases;
        gs.commitmentsPaused = pauseCommitments;
        emit PauseStateUpdated(pausePurchases, pauseCommitments);
    }

    function setProtocolConfig(uint256 startingPrice, uint16 priceIncreaseBps) external onlyAuthority {
        if (startingPrice == 0) revert Errors.InvalidAddress();
        if (priceIncreaseBps == 0 || priceIncreaseBps > Constants.BPS) revert Errors.InvalidBps();
        LibProtocolStorage.game().config.startingPrice = startingPrice;
        LibProtocolStorage.game().config.priceIncreaseBps = priceIncreaseBps;
        emit ProtocolConfigUpdated(startingPrice, priceIncreaseBps);
    }

    function setTreasuryRecipient(address newRecipient) external onlyAuthority {
        LibRecipients.enforceExternal(newRecipient);
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        address previous = ts.recipient;
        ts.recipient = newRecipient;
        emit TreasuryRecipientUpdated(previous, newRecipient);
    }

    function finalizeProtocol() external onlyAuthority {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.cutsDisabled) revert Errors.AlreadyFinalized();
        ds.cutsDisabled = true;
        emit ProtocolFinalized();
    }
}
