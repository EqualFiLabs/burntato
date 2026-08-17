// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";

import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Errors} from "../shared/Errors.sol";

contract PotatoTokenFacet is ERC20 {
    event PotatoBurned(address indexed account, uint256 amount);
    event PoolManagerAllowanceAuthorized(uint256 amount);
    event PoolManagerAllowanceSpent(address indexed from, address indexed to, uint256 amount);

    function name() public pure override returns (string memory) {
        return "Burntato Potato";
    }

    function symbol() public pure override returns (string memory) {
        return "POTATO";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit PotatoBurned(msg.sender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) revert Errors.TransferRestricted(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (from == address(0) || to == address(0)) revert Errors.TransferRestricted(from, to);
        return super.transferFrom(from, to, amount);
    }

    function protocolMint(address to, uint256 amount) external {
        _enforceProtocol();
        _mint(to, amount);
    }

    function protocolBurn(address from, uint256 amount) external {
        _enforceProtocol();
        _burn(from, amount);
    }

    function protocolTransfer(address from, address to, uint256 amount) external {
        _enforceProtocol();
        if (from == address(0) || to == address(0)) revert Errors.TransferRestricted(from, to);
        _setProtocolMovement(keccak256(abi.encode(from, to, amount)));
        _transfer(from, to, amount);
    }

    function authorizePoolManagerTransfer(uint256 amount) external {
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        if (msg.sender != ts.canonicalHook || msg.sender == address(0)) revert Errors.NotCanonicalHook(msg.sender);
        _setPoolManagerAllowance(_poolManagerAllowance() + amount);
        emit PoolManagerAllowanceAuthorized(amount);
    }

    function transientPoolManagerAllowance() external view returns (uint256) {
        return _poolManagerAllowance();
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) return;

        bytes32 movement = keccak256(abi.encode(from, to, amount));
        if (_protocolMovement() == movement) {
            _setProtocolMovement(bytes32(0));
            return;
        }

        address poolManager = LibProtocolStorage.token().poolManager;
        if (from == poolManager || to == poolManager) {
            uint256 available = _poolManagerAllowance();
            if (available < amount) revert Errors.PoolManagerAllowanceExceeded(available, amount);
            _setPoolManagerAllowance(available - amount);
            emit PoolManagerAllowanceSpent(from, to, amount);
            return;
        }

        revert Errors.TransferRestricted(from, to);
    }

    function _enforceProtocol() private view {
        if (msg.sender != address(this)) revert Errors.NotProtocol(msg.sender);
    }

    function _poolManagerAllowance() private view returns (uint256 amount) {
        bytes32 slot = LibProtocolStorage.POOL_MANAGER_ALLOWANCE_SLOT;
        assembly ("memory-safe") {
            amount := tload(slot)
        }
    }

    function _setPoolManagerAllowance(uint256 amount) private {
        bytes32 slot = LibProtocolStorage.POOL_MANAGER_ALLOWANCE_SLOT;
        assembly ("memory-safe") {
            tstore(slot, amount)
        }
    }

    function _protocolMovement() private view returns (bytes32 movement) {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") {
            movement := tload(slot)
        }
    }

    function _setProtocolMovement(bytes32 movement) private {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") {
            tstore(slot, movement)
        }
    }
}
