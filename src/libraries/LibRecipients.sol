// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibProtocolStorage} from "./LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";

library LibRecipients {
    function enforceExternal(address recipient) internal view {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (
            recipient == address(0) || recipient == address(this) || recipient == Constants.LOCKED_LP_RECIPIENT
                || recipient == ms.hook || recipient == ms.poolManager || recipient == ms.positionManager
                || recipient == ms.permit2
        ) revert Errors.InvalidAddress();
    }
}
