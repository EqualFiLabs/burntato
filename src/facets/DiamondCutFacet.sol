// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FacetCut} from "../shared/Types.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external {
        LibDiamond.enforceAuthority();
        if (LibDiamond.diamondStorage().cutsDisabled) revert();
        LibDiamond.diamondCut(cuts, init, data);
    }
}
