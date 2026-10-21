// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BuybackFacet} from "../../../src/facets/BuybackFacet.sol";
import {GovernanceFacet} from "../../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../../src/facets/PotatoTokenFacet.sol";
import {IBuyback} from "../../../src/interfaces/IBuyback.sol";
import {IPotatoToken} from "../../../src/interfaces/IPotatoToken.sol";
import {LibDiamond} from "../../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../../src/libraries/LibProtocolStorage.sol";
import {Errors} from "../../../src/shared/Errors.sol";
import {BuybackConfig} from "../../../src/shared/Types.sol";

/// @notice Exposes controlled pause states while executing production governance and public-wrap logic.
/// @dev State construction and the self-call wrapper exist only in this verification harness.
contract BurntatoPauseHarness is GovernanceFacet, PotatoTokenFacet, BuybackFacet {
    uint256 private _formalUnlockCount;

    function formalConfigurePauseState(address authority_, address guardian_, bool paused_, bool purchasesInitialized_)
        external
    {
        LibDiamond.transferAuthority(authority_);
        LibProtocolStorage.GovernanceStorage storage gs = LibProtocolStorage.governance();
        gs.guardian = guardian_;
        gs.paused = paused_;
        LibProtocolStorage.game().initialized = purchasesInitialized_;
        // Public-entry properties begin outside an active guarded call.
        LibProtocolStorage.reentrancy().status = 1;
    }

    function formalPublicWrap(address recipient, uint256 amount) external {
        IPotatoToken(address(this)).wrap(amount);
    }

    function formalPublicWrapResult(address recipient, uint256 amount)
        external
        returns (bool succeeded, uint256 revertSelector)
    {
        try this.formalPublicWrap(recipient, amount) {
            return (true, 0);
        } catch (bytes memory reason) {
            if (reason.length < 4) return (false, 0);
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(reason, 0x20))
            }
            return (false, uint32(selector));
        }
    }

    function formalConfigureBuybackState(uint256 reserveEth, uint256 lastExecutionBlock) external {
        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth = reserveEth;
        bs.config = BuybackConfig({maxSpend: 1 ether, callerRewardBps: 0, delayBlocks: 0});
        bs.lastBuybackBlock = lastExecutionBlock;
        LibProtocolStorage.buybackMarket().poolManager = address(this);
        LibProtocolStorage.buybackMarket().configured = true;
        LibProtocolStorage.wrapper().underlying = address(this);
        LibProtocolStorage.treasury().recipient = address(1);
        LibProtocolStorage.reentrancy().status = 1;
        _formalUnlockCount = 0;
    }

    function formalInstallBuybackFundingSelector() external {
        LibDiamond.diamondStorage().selectorData[IBuyback.fundBuybackReserve.selector].facet = address(this);
    }

    error FormalManagerReached();

    function unlock(bytes calldata) external pure returns (bytes memory) {
        revert FormalManagerReached();
    }

    function formalManagerReachedSelector() external pure returns (uint256) {
        return uint32(FormalManagerReached.selector);
    }

    function formalUnlockCount() external view returns (uint256) {
        return _formalUnlockCount;
    }

    function formalBuybackResult() external returns (bool succeeded, uint256 revertSelector) {
        try this.buyback() returns (uint256) {
            return (true, 0);
        } catch (bytes memory reason) {
            if (reason.length < 4) return (false, 0);
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(reason, 0x20))
            }
            return (false, uint32(selector));
        }
    }

    function formalProtocolPausedSelector() external pure returns (uint256) {
        return uint32(Errors.ProtocolPaused.selector);
    }
}
