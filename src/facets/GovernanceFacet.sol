// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IGovernance} from "../interfaces/IGovernance.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";

interface ITimelockDelay {
    function getMinDelay() external view returns (uint256);
}

contract GovernanceFacet is IGovernance {
    bytes32 public constant PROTOCOL_CONFIG_KEY = keccak256("burntato.parameter.protocol-config");
    bytes32 public constant TREASURY_RECIPIENT_KEY = keccak256("burntato.parameter.treasury-recipient");
    bytes32 public constant GUARDIAN_KEY = keccak256("burntato.parameter.guardian");

    modifier onlyAuthority() {
        LibDiamond.enforceAuthority();
        _;
    }

    modifier beforeFinalization() {
        if (LibProtocolStorage.governance().finalized) revert Errors.AlreadyFinalized();
        _;
    }

    function authority() external view returns (address) {
        return LibDiamond.authority();
    }

    function authorityLocked() external view returns (bool) {
        return LibDiamond.diamondStorage().authorityLocked;
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
        return LibProtocolStorage.governance().finalized;
    }

    function parameterFrozen(bytes32 key) external view returns (bool) {
        return LibProtocolStorage.governance().frozenParameters[key];
    }

    function selectorFrozen(bytes4 selector) external view returns (bool) {
        return LibDiamond.diamondStorage().frozenSelector[selector];
    }

    function setAuthority(address newAuthority) external onlyAuthority beforeFinalization {
        if (newAuthority.code.length == 0) revert Errors.NoCode(newAuthority);
        try ITimelockDelay(newAuthority).getMinDelay() returns (uint256 delay) {
            if (delay < Constants.MIN_TIMELOCK_DELAY) revert Errors.InvalidTimelock(newAuthority);
        } catch {
            revert Errors.InvalidTimelock(newAuthority);
        }
        address previous = LibDiamond.authority();
        LibDiamond.transferAuthorityAndLock(newAuthority);
        emit AuthorityTransferred(previous, newAuthority);
    }

    function setGuardian(address newGuardian) external onlyAuthority beforeFinalization {
        _enforceMutable(GUARDIAN_KEY);
        if (newGuardian == address(0)) revert Errors.InvalidAddress();
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        address previous = gs.guardian;
        gs.guardian = newGuardian;
        emit GuardianUpdated(previous, newGuardian);
    }

    function setPauseState(bool pausePurchases, bool pauseCommitments) external beforeFinalization {
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

    function setProtocolConfig(uint256 startingPrice, uint16 priceIncreaseBps)
        external
        onlyAuthority
        beforeFinalization
    {
        _enforceMutable(PROTOCOL_CONFIG_KEY);
        if (startingPrice == 0) revert Errors.InvalidAddress();
        if (priceIncreaseBps == 0 || priceIncreaseBps > Constants.BPS) revert Errors.InvalidBps();
        LibProtocolStorage.game().config.startingPrice = startingPrice;
        LibProtocolStorage.game().config.priceIncreaseBps = priceIncreaseBps;
        emit ProtocolConfigUpdated(startingPrice, priceIncreaseBps);
    }

    function setTreasuryRecipient(address newRecipient) external onlyAuthority beforeFinalization {
        _enforceMutable(TREASURY_RECIPIENT_KEY);
        if (newRecipient == address(0)) revert Errors.InvalidAddress();
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        address previous = ts.recipient;
        ts.recipient = newRecipient;
        emit TreasuryRecipientUpdated(previous, newRecipient);
    }

    function freezeParameter(bytes32 key) external onlyAuthority beforeFinalization {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        if (gs.frozenParameters[key]) revert Errors.AlreadyFrozen(key);
        gs.frozenParameters[key] = true;
        emit ParameterFrozen(key);
    }

    function freezeSelectors(bytes4[] calldata selectors) external onlyAuthority beforeFinalization {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector = selectors[i];
            if (ds.selectorData[selector].facet == address(0)) revert Errors.SelectorDoesNotExist(selector);
            if (ds.frozenSelector[selector]) revert Errors.SelectorFrozen(selector);
            ds.frozenSelector[selector] = true;
            emit SelectorFrozen(selector);
        }
    }

    function finalizeProtocol() external onlyAuthority beforeFinalization {
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        gs.finalized = true;
        gs.guardian = address(0);
        gs.purchasesPaused = false;
        gs.commitmentsPaused = false;
        LibDiamond.diamondStorage().cutsDisabled = true;
        emit ProtocolFinalized();
    }

    function _enforceMutable(bytes32 key) private view {
        if (LibProtocolStorage.governance().frozenParameters[key]) revert Errors.ParameterFrozen(key);
    }
}
