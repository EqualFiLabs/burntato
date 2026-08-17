// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {LibProtocolStorage} from "./LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";

library LibToken {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) internal {
        if (to == address(0)) revert Errors.InvalidAddress();
        if (amount == 0) return;
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        ts.totalSupply += amount;
        ts.balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) internal {
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        if (ts.balanceOf[from] < amount) revert Errors.InsufficientBalance();
        ts.balanceOf[from] -= amount;
        ts.totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function protocolMove(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert Errors.InvalidAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        if (ts.balanceOf[from] < amount) revert Errors.InsufficientBalance();
        ts.balanceOf[from] -= amount;
        ts.balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function poolManagerAllowance() internal view returns (uint256 amount) {
        bytes32 slot = LibProtocolStorage.POOL_MANAGER_ALLOWANCE_SLOT;
        assembly ("memory-safe") {
            amount := tload(slot)
        }
    }

    function setPoolManagerAllowance(uint256 amount) internal {
        bytes32 slot = LibProtocolStorage.POOL_MANAGER_ALLOWANCE_SLOT;
        assembly ("memory-safe") {
            tstore(slot, amount)
        }
    }

    function consumePoolManagerAllowance(uint256 amount) internal {
        uint256 available = poolManagerAllowance();
        if (available < amount) revert Errors.PoolManagerAllowanceExceeded(available, amount);
        setPoolManagerAllowance(available - amount);
    }
}
