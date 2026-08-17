// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";
import {Constants} from "../shared/Constants.sol";

contract FoundationInit {
    function initialize(uint256 startingPrice, uint16 priceIncreaseBps, address treasury) external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (gs.initialized) revert Errors.AlreadyInitialized();
        if (startingPrice == 0 || treasury == address(0)) revert Errors.InvalidAddress();
        if (priceIncreaseBps == 0 || priceIncreaseBps > Constants.BPS) revert Errors.InvalidBps();
        gs.initialized = true;
        gs.config.startingPrice = startingPrice;
        gs.config.priceIncreaseBps = priceIncreaseBps;
        LibProtocolStorage.treasury().recipient = treasury;
    }
}
