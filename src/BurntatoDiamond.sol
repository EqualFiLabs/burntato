// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FacetCut, FacetCutAction} from "./shared/Types.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {Errors} from "./shared/Errors.sol";

contract BurntatoDiamond {
    constructor(address authority, address cutFacet) payable {
        LibDiamond.setAuthority(authority);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(cutFacet, FacetCutAction.Add, selectors);
        LibDiamond.diamondCut(cuts, address(0), "");
    }

    receive() external payable {}

    fallback() external payable {
        address facet = LibDiamond.diamondStorage().selectorData[msg.sig].facet;
        if (facet == address(0)) revert Errors.FunctionNotFound(msg.sig);
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
