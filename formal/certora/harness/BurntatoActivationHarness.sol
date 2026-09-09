// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GovernanceFacet} from "../../../src/facets/GovernanceFacet.sol";
import {LibDiamond} from "../../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../../src/libraries/LibProtocolStorage.sol";

/// @notice Exposes controlled starting states while executing production governance logic.
/// @dev The state setter exists only in this verification harness and is never deployed.
contract BurntatoActivationHarness is GovernanceFacet {
    function formalConfigureState(address authority_, bool foundationInitialized_, bool purchasesInitialized_)
        external
    {
        LibDiamond.transferAuthority(authority_);
        LibProtocolStorage.initialization().foundationInitialized = foundationInitialized_;
        LibProtocolStorage.game().initialized = purchasesInitialized_;
    }
}
