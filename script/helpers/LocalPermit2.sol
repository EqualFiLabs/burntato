// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";

contract LocalPermit2 is IAllowanceTransfer {
    mapping(address owner => mapping(address token => mapping(address spender => PackedAllowance))) private _allowance;

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), "Burntato Local Permit2"));
    }

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        PackedAllowance memory current = _allowance[user][token][spender];
        return (current.amount, current.expiration, current.nonce);
    }

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        PackedAllowance storage current = _allowance[msg.sender][token][spender];
        current.amount = amount;
        current.expiration = expiration;
        emit Approval(msg.sender, token, spender, amount, expiration);
    }

    function permit(address, PermitSingle memory, bytes calldata) external pure {
        revert("LocalPermit2: signatures unsupported");
    }

    function permit(address, PermitBatch memory, bytes calldata) external pure {
        revert("LocalPermit2: signatures unsupported");
    }

    function transferFrom(address from, address to, uint160 amount, address token) public {
        _spend(from, token, msg.sender, amount);
        require(IERC20(token).transferFrom(from, to, amount), "LocalPermit2: transfer failed");
    }

    function transferFrom(AllowanceTransferDetails[] calldata transferDetails) external {
        for (uint256 i; i < transferDetails.length; ++i) {
            AllowanceTransferDetails calldata details = transferDetails[i];
            transferFrom(details.from, details.to, details.amount, details.token);
        }
    }

    function lockdown(TokenSpenderPair[] calldata approvals) external {
        for (uint256 i; i < approvals.length; ++i) {
            TokenSpenderPair calldata approval = approvals[i];
            _allowance[msg.sender][approval.token][approval.spender].amount = 0;
            emit Lockdown(msg.sender, approval.token, approval.spender);
        }
    }

    function invalidateNonces(address token, address spender, uint48 newNonce) external {
        PackedAllowance storage current = _allowance[msg.sender][token][spender];
        uint48 oldNonce = current.nonce;
        if (newNonce <= oldNonce || newNonce - oldNonce > type(uint16).max) revert ExcessiveInvalidation();
        current.nonce = newNonce;
        emit NonceInvalidation(msg.sender, token, spender, newNonce, oldNonce);
    }

    function _spend(address owner, address token, address spender, uint160 amount) private {
        PackedAllowance storage current = _allowance[owner][token][spender];
        if (block.timestamp > current.expiration) revert AllowanceExpired(current.expiration);
        uint160 available = current.amount;
        if (available < amount) revert InsufficientAllowance(available);
        if (available != type(uint160).max) current.amount = available - amount;
    }
}
