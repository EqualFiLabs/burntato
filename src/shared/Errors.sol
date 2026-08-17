// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library Errors {
    error AlreadyClaimed();
    error AlreadyFinalized();
    error AlreadyFrozen(bytes32 key);
    error AlreadyInitialized();
    error CommitmentClosed(uint256 roundId);
    error CommitmentsPaused();
    error CutsDisabled();
    error EmptySelectors();
    error FacetHasNoCode(address facet);
    error FunctionNotFound(bytes4 selector);
    error IncorrectPayment(uint256 expected, uint256 received);
    error InitializationFailed(bytes reason);
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidAddress();
    error InvalidBps();
    error InvalidFacetAction(uint8 action);
    error InvalidRound(uint256 roundId);
    error NativeTransferFailed();
    error NoCode(address target);
    error NoCurrentHolder();
    error NotAuthority(address caller);
    error NotCanonicalHook(address caller);
    error NotGuardian(address caller);
    error NothingToClaim();
    error ParameterFrozen(bytes32 key);
    error PoolManagerAllowanceExceeded(uint256 available, uint256 required);
    error PurchasesPaused();
    error Reentrancy();
    error RoundAlreadySettled();
    error RoundExpired();
    error RoundNotExpired();
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorFrozen(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error TransferRestricted(address from, address to);
    error UnauthorizedWinner(address caller);
    error VestingIncomplete();
    error ZeroAmount();
}
