// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {LibProtocolStorage} from "./LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";

library LibRecipients {
    function enforceExternal(address recipient) internal view {
        LibProtocolStorage.BuybackMarketStorage storage buybackMarket = LibProtocolStorage.buybackMarket();
        address operatorRewardsRouter = LibProtocolStorage.operatorRevenue().router;
        if (
            recipient == address(0) || recipient == address(this) || recipient == operatorRewardsRouter
                || recipient == LibProtocolStorage.wrapper().underlying || recipient == buybackMarket.poolManager
                || recipient == buybackMarket.weth || recipient == address(buybackMarket.key.hooks)
        ) revert Errors.InvalidAddress();
    }
}
