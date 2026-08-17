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
    error NoCode(address target);
    error NotGuardian(address caller);
    error NotAuthority(address caller);
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorDoesNotExist(bytes4 selector);
    error SelectorFrozen(bytes4 selector);
    error SelectorUnchanged(bytes4 selector);
    error ParameterFrozen(bytes32 key);
}
