// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibToken} from "../libraries/LibToken.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";

contract PotatoTokenFacet is IPotatoToken {
    function name() external pure returns (string memory) {
        return "Burntato Potato";
    }

    function symbol() external pure returns (string memory) {
        return "POTATO";
    }

    function decimals() external pure returns (uint8) {
        return Constants.POTATO_DECIMALS;
    }

    function totalSupply() external view returns (uint256) {
        return LibProtocolStorage.token().totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return LibProtocolStorage.token().balanceOf[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return LibProtocolStorage.token().allowance[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert Errors.InvalidAddress();
        LibProtocolStorage.token().allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _restrictedMove(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        uint256 approved = ts.allowance[from][msg.sender];
        if (approved < amount) revert Errors.InsufficientAllowance();
        if (approved != type(uint256).max) {
            ts.allowance[from][msg.sender] = approved - amount;
            emit Approval(from, msg.sender, approved - amount);
        }
        _restrictedMove(from, to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        LibToken.burn(msg.sender, amount);
        emit PotatoBurned(msg.sender, amount);
    }

    function authorizePoolManagerTransfer(uint256 amount) external {
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        if (msg.sender != ts.canonicalHook || msg.sender == address(0)) revert Errors.NotCanonicalHook(msg.sender);
        LibToken.setPoolManagerAllowance(amount);
        emit PoolManagerAllowanceAuthorized(amount);
    }

    function transientPoolManagerAllowance() external view returns (uint256) {
        return LibToken.poolManagerAllowance();
    }

    function _restrictedMove(address from, address to, uint256 amount) private {
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        bool poolMovement = msg.sender == ts.poolManager && (from == ts.poolManager || to == ts.poolManager);
        if (!poolMovement) revert Errors.TransferRestricted(from, to);
        LibToken.consumePoolManagerAllowance(amount);
        LibToken.protocolMove(from, to, amount);
    }
}
