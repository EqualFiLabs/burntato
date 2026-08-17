// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FacetCut} from "../shared/Types.sol";

interface IDiamondCut {
    event DiamondCut(FacetCut[] cuts, address indexed init, bytes data);

    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external;
}
