// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FacetCut, FacetCutAction} from "../shared/Types.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {Errors} from "../shared/Errors.sol";

library LibDiamond {
    bytes32 internal constant DIAMOND_SLOT = keccak256("burntato.storage.diamond.v1");

    struct SelectorData {
        address facet;
        uint32 selectorPosition;
    }

    struct FacetData {
        bytes4[] selectors;
        uint32 facetPosition;
    }

    struct DiamondStorage {
        mapping(bytes4 => SelectorData) selectorData;
        mapping(address => FacetData) facetData;
        address[] facetAddresses;
        address authority;
        mapping(bytes4 => bool) frozenSelector;
        bool cutsDisabled;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage s) {
        bytes32 slot = DIAMOND_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function setAuthority(address authority_) internal {
        if (authority_ == address(0)) revert Errors.InvalidAddress();
        diamondStorage().authority = authority_;
    }

    function authority() internal view returns (address) {
        return diamondStorage().authority;
    }

    function enforceAuthority() internal view {
        if (msg.sender != diamondStorage().authority) revert Errors.NotAuthority(msg.sender);
    }

    function enforceHasCode(address target) internal view {
        if (target.code.length == 0) revert Errors.NoCode(target);
    }

    function diamondCut(FacetCut[] memory cuts, address init, bytes memory data) internal {
        DiamondStorage storage ds = diamondStorage();
        for (uint256 i; i < cuts.length; ++i) {
            bytes4[] memory selectors = cuts[i].functionSelectors;
            if (selectors.length == 0) revert Errors.EmptySelectors();
            if (cuts[i].action == FacetCutAction.Add) {
                _add(ds, cuts[i].facetAddress, selectors);
            } else if (cuts[i].action == FacetCutAction.Replace) {
                _replace(ds, cuts[i].facetAddress, selectors);
            } else if (cuts[i].action == FacetCutAction.Remove) {
                _remove(ds, cuts[i].facetAddress, selectors);
            } else {
                revert Errors.InvalidFacetAction(uint8(cuts[i].action));
            }
        }
        emit IDiamondCut.DiamondCut(cuts, init, data);
        _initialize(init, data);
    }

    function _add(DiamondStorage storage ds, address facet, bytes4[] memory selectors) private {
        enforceHasCode(facet);
        FacetData storage fd = ds.facetData[facet];
        if (fd.selectors.length == 0) {
            fd.facetPosition = uint32(ds.facetAddresses.length);
            ds.facetAddresses.push(facet);
        }
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector = selectors[i];
            if (ds.selectorData[selector].facet != address(0)) revert Errors.SelectorAlreadyExists(selector);
            ds.selectorData[selector] = SelectorData(facet, uint32(fd.selectors.length));
            fd.selectors.push(selector);
        }
    }

    function _replace(DiamondStorage storage ds, address facet, bytes4[] memory selectors) private {
        enforceHasCode(facet);
        FacetData storage newFd = ds.facetData[facet];
        if (newFd.selectors.length == 0) {
            newFd.facetPosition = uint32(ds.facetAddresses.length);
            ds.facetAddresses.push(facet);
        }
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector = selectors[i];
            if (ds.frozenSelector[selector]) revert Errors.SelectorFrozen(selector);
            address oldFacet = ds.selectorData[selector].facet;
            if (oldFacet == address(0)) revert Errors.SelectorDoesNotExist(selector);
            if (oldFacet == facet) revert Errors.SelectorUnchanged(selector);
            _removeSelector(ds, oldFacet, selector);
            ds.selectorData[selector] = SelectorData(facet, uint32(newFd.selectors.length));
            newFd.selectors.push(selector);
        }
    }

    function _remove(DiamondStorage storage ds, address facet, bytes4[] memory selectors) private {
        if (facet != address(0)) revert Errors.InvalidAddress();
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector = selectors[i];
            if (ds.frozenSelector[selector]) revert Errors.SelectorFrozen(selector);
            address oldFacet = ds.selectorData[selector].facet;
            if (oldFacet == address(0)) revert Errors.SelectorDoesNotExist(selector);
            _removeSelector(ds, oldFacet, selector);
            delete ds.selectorData[selector];
        }
    }

    function _removeSelector(DiamondStorage storage ds, address facet, bytes4 selector) private {
        FacetData storage fd = ds.facetData[facet];
        uint256 position = ds.selectorData[selector].selectorPosition;
        uint256 last = fd.selectors.length - 1;
        if (position != last) {
            bytes4 moved = fd.selectors[last];
            fd.selectors[position] = moved;
            ds.selectorData[moved].selectorPosition = uint32(position);
        }
        fd.selectors.pop();
        if (fd.selectors.length == 0) {
            uint256 facetPosition = fd.facetPosition;
            uint256 lastFacet = ds.facetAddresses.length - 1;
            if (facetPosition != lastFacet) {
                address movedFacet = ds.facetAddresses[lastFacet];
                ds.facetAddresses[facetPosition] = movedFacet;
                ds.facetData[movedFacet].facetPosition = uint32(facetPosition);
            }
            ds.facetAddresses.pop();
            delete ds.facetData[facet];
        }
    }

    function _initialize(address init, bytes memory data) private {
        if (init == address(0)) {
            if (data.length != 0) revert Errors.InvalidAddress();
            return;
        }
        enforceHasCode(init);
        (bool ok, bytes memory reason) = init.delegatecall(data);
        if (!ok) revert Errors.InitializationFailed(reason);
    }
}
