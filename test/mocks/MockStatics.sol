// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";

/// @dev Fixture underlying with optional transfer failure and adversarial callbacks.
contract MockStatics is ERC20 {
    bool public failTransfers;
    uint256 public fee;
    address public callback;
    bytes public callbackData;
    bool public callbackSucceeded;

    function name() public pure override returns (string memory) {
        return "Mock STATICS";
    }

    function symbol() public pure override returns (string memory) {
        return "STATICS";
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFailure(bool fail) external {
        failTransfers = fail;
    }

    function setFee(uint256 amount) external {
        fee = amount;
    }

    function setCallback(address target, bytes calldata data) external {
        callback = target;
        callbackData = data;
    }

    function _beforeTokenTransfer(address from, address, uint256) internal override {
        if (from != address(0)) {
            require(!failTransfers, "transfer failed");
            if (callback != address(0)) (callbackSucceeded,) = callback.call(callbackData);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && fee != 0 && amount >= fee) _burn(to, fee);
    }
}
