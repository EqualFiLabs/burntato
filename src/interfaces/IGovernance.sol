// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ProtocolConfig} from "../shared/Types.sol";

interface IGovernance {
    event AuthorityTransferred(address indexed previousAuthority, address indexed newAuthority);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event PauseStateUpdated(bool purchasesPaused, bool commitmentsPaused);
    event ProtocolConfigUpdated(uint256 startingPrice, uint16 priceIncreaseBps);
    event TreasuryRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event ParameterFrozen(bytes32 indexed key);
    event SelectorFrozen(bytes4 indexed selector);
    event ProtocolFinalized();

    function authority() external view returns (address);
    function authorityLocked() external view returns (bool);
    function guardian() external view returns (address);
    function purchasesPaused() external view returns (bool);
    function commitmentsPaused() external view returns (bool);
    function protocolFinalized() external view returns (bool);
    function protocolConfig() external view returns (ProtocolConfig memory);
    function parameterFrozen(bytes32 key) external view returns (bool);
    function selectorFrozen(bytes4 selector) external view returns (bool);
    function setAuthority(address newAuthority) external;
    function setGuardian(address newGuardian) external;
    function setPauseState(bool pausePurchases, bool pauseCommitments) external;
    function setProtocolConfig(uint256 startingPrice, uint16 priceIncreaseBps) external;
    function setTreasuryRecipient(address newRecipient) external;
    function freezeParameter(bytes32 key) external;
    function freezeSelectors(bytes4[] calldata selectors) external;
    function finalizeProtocol() external;
}
