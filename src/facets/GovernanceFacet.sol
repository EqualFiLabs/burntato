// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGovernance} from "../interfaces/IGovernance.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibConfig} from "../libraries/LibConfig.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
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

    function paused() external view returns (bool) {
        return LibProtocolStorage.governance().paused;
    }

    function protocolFinalized() external view returns (bool) {
        return LibDiamond.diamondStorage().cutsDisabled;
    }

    function protocolConfig() external view returns (ProtocolConfig memory) {
        return LibProtocolStorage.game().config;
    }

    function foundationConfigured() external view returns (bool) {
        return LibProtocolStorage.initialization().foundationInitialized;
    }

    function purchasesInitialized() external view returns (bool) {
        return LibProtocolStorage.game().initialized;
    }

    function initializePurchases() external onlyAuthority {
        LibProtocolStorage.InitializationStorage storage initialization = LibProtocolStorage.initialization();
        if (!initialization.foundationInitialized) revert Errors.FoundationNotInitialized();
        LibProtocolStorage.GameStorage storage game = LibProtocolStorage.game();
        if (game.initialized) revert Errors.AlreadyInitialized();
        game.initialized = true;
        emit PurchasesInitialized(msg.sender);
    }

    function setAuthority(address newAuthority) external onlyAuthority {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        if (
            newAuthority == address(0)
                && (gs.guardian != address(0) || gs.paused || !LibProtocolStorage.game().initialized)
        ) {
            revert Errors.UnsafeAuthorityRenunciation();
        }
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

    function setPaused(bool paused_) external {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        if (msg.sender != LibDiamond.authority()) {
            if (msg.sender != gs.guardian) revert Errors.NotGuardian(msg.sender);
            if (!paused_) revert Errors.UnpauseRequiresAuthority(msg.sender);
        }
        gs.paused = paused_;
        emit PauseStateUpdated(paused_);
    }

    function setProtocolConfig(ProtocolConfig calldata config) external onlyAuthority {
        LibConfig.validate(config);
        if (config.operatorPurchaseBps != 0 && LibProtocolStorage.operatorRevenue().router == address(0)) {
            revert Errors.InvalidProtocolConfig();
        }
        LibProtocolStorage.game().config = config;
        emit ProtocolConfigUpdated(config);
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
