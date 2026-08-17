// SPDX-License-Identifier: BUSL-1.1
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
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), facet, ptr, calldatasize(), 0, 0)
            returndatacopy(ptr, 0, returndatasize())
            switch result
            case 0 { revert(ptr, returndatasize()) }
            default { return(ptr, returndatasize()) }
        }
    }
}
