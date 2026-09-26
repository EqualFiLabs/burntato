// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BuybackFacet} from "../../../src/facets/BuybackFacet.sol";
import {GovernanceFacet} from "../../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../../src/facets/PotatoTokenFacet.sol";
import {IBuyback} from "../../../src/interfaces/IBuyback.sol";
import {IPotatoToken} from "../../../src/interfaces/IPotatoToken.sol";
import {LibDiamond} from "../../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../../src/libraries/LibProtocolStorage.sol";
import {BuybackConfig} from "../../../src/shared/Types.sol";

/// @notice Exposes controlled pause states while executing production governance and mint logic.
/// @dev State construction and the self-call wrapper exist only in this verification harness.
contract BurntatoPauseHarness is GovernanceFacet, PotatoTokenFacet, BuybackFacet {
    function formalConfigurePauseState(
        address authority_,
        address guardian_,
        bool paused_,
        bool purchasesInitialized_
    ) external {
        LibDiamond.transferAuthority(authority_);
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        gs.guardian = guardian_;
        gs.paused = paused_;
        LibProtocolStorage.game().initialized = purchasesInitialized_;
    }

    function formalProtocolMint(address recipient, uint256 amount) external {
        IPotatoToken(address(this)).protocolMint(recipient, amount);
    }

    function formalConfigureBuybackState(uint256 reserveEth, uint256 lastExecutionBlock) external {
        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth = reserveEth;
        bs.config = BuybackConfig({maxSpend: 1 ether, callerRewardBps: 50, delayBlocks: 1});
        bs.lastBuybackBlock = lastExecutionBlock;
    }

    function formalInstallBuybackFundingSelector() external {
        LibDiamond.diamondStorage().selectorData[IBuyback.fundBuybackReserve.selector].facet = address(this);
    }
}
