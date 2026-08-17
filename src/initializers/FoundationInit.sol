// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibConfig} from "../libraries/LibConfig.sol";
import {Errors} from "../shared/Errors.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {ProtocolConfig} from "../shared/Types.sol";

contract FoundationInit {
    function initialize(ProtocolConfig calldata config, address treasury) external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (gs.initialized) revert Errors.AlreadyInitialized();
        LibRecipients.enforceExternal(treasury);
        LibConfig.validate(config);
        gs.initialized = true;
        gs.config = config;
        LibProtocolStorage.treasury().recipient = treasury;
    }
}
