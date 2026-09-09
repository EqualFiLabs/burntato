// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GovernanceFacet} from "../../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../../src/facets/PotatoTokenFacet.sol";
import {IPotatoToken} from "../../../src/interfaces/IPotatoToken.sol";
import {LibDiamond} from "../../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../../src/libraries/LibProtocolStorage.sol";

/// @notice Exposes controlled pause states while executing production governance and mint logic.
/// @dev State construction and the self-call wrapper exist only in this verification harness.
contract BurntatoPauseHarness is GovernanceFacet, PotatoTokenFacet {
    function formalConfigurePauseState(address authority_, address guardian_, bool paused_) external {
        LibDiamond.transferAuthority(authority_);
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        gs.guardian = guardian_;
        gs.paused = paused_;
    }

    function formalProtocolMint(address recipient, uint256 amount) external {
        IPotatoToken(address(this)).protocolMint(recipient, amount);
    }
}
