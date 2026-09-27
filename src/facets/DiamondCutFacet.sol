// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                  BURNTATO
//                         Grab it. Hold it. Burn it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {FacetCut} from "../shared/Types.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Errors} from "../shared/Errors.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external {
        LibDiamond.enforceAuthority();
        if (LibDiamond.diamondStorage().cutsDisabled) revert Errors.CutsDisabled();
        LibDiamond.diamondCut(cuts, init, data);
    }
}
