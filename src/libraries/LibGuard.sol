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

abstract contract LibGuard {
    modifier nonReentrant() {
        _enterReentrancyGuard();
        _;
        _exitReentrancyGuard();
    }

    function _enterReentrancyGuard() internal {
        LibProtocolStorage.ReentrancyStorage storage guard = LibProtocolStorage.reentrancy();
        if (guard.status == 2) revert Errors.Reentrancy();
        guard.status = 2;
    }

    function _exitReentrancyGuard() internal {
        LibProtocolStorage.reentrancy().status = 1;
    }
}
