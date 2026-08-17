// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library Errors {
    error AlreadyInitialized();
    error AlreadyFinalized();
    error AlreadyFrozen(bytes32 key);
    error CutsDisabled();
    error EmptySelectors();
    error FacetHasNoCode(address facet);
    error FunctionNotFound(bytes4 selector);
    error InitializationFailed(bytes reason);
    error InvalidAddress();
    error InvalidBps();
    error InvalidFacetAction(uint8 action);
    error IncorrectPayment(uint256 expected, uint256 received);
    error InsufficientAllowance();
    error InsufficientBalance();
    error NoCode(address target);
    error NotGuardian(address caller);
    error NotCanonicalHook(address caller);
    error NoCurrentHolder();
    error NotAuthority(address caller);
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorFrozen(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error ParameterFrozen(bytes32 key);
    error PoolManagerAllowanceExceeded(uint256 available, uint256 required);
    error PurchasesPaused();
    error RoundExpired();
    error TransferRestricted(address from, address to);
    error VestingIncomplete();
    error ZeroAmount();
}
