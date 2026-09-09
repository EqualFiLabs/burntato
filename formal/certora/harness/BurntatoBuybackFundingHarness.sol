// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BuybackFacet} from "../../../src/facets/BuybackFacet.sol";
import {IBuyback} from "../../../src/interfaces/IBuyback.sol";
import {LibDiamond} from "../../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../../src/libraries/LibProtocolStorage.sol";

/// @notice Exposes controlled starting states while executing production buyback funding logic.
/// @dev The state setter exists only in this verification harness and is never deployed.
contract BurntatoBuybackFundingHarness is BuybackFacet {
    function formalConfigureFundingState(uint256 reserveEth, uint256 lastBuybackBlock_, uint256 reentrancyStatus)
        external
    {
        LibProtocolStorage.BuybackStorage storage buybackStorage = LibProtocolStorage.buyback();
        buybackStorage.reserveEth = reserveEth;
        buybackStorage.lastBuybackBlock = lastBuybackBlock_;
        LibProtocolStorage.reentrancy().status = reentrancyStatus;
        LibDiamond.diamondStorage().selectorData[IBuyback.fundBuybackReserve.selector].facet = address(this);
    }

    function formalReentrancyStatus() external view returns (uint256) {
        return LibProtocolStorage.reentrancy().status;
    }
}
