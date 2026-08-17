// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";

library BurntatoSelectors {
    function diamondCut() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
    }

    function loupe() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
    }

    function governance() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = IGovernance.authority.selector;
        selectors[1] = IGovernance.guardian.selector;
        selectors[2] = IGovernance.purchasesPaused.selector;
        selectors[3] = IGovernance.commitmentsPaused.selector;
        selectors[4] = IGovernance.protocolFinalized.selector;
        selectors[5] = IGovernance.protocolConfig.selector;
        selectors[6] = IGovernance.setAuthority.selector;
        selectors[7] = IGovernance.setGuardian.selector;
        selectors[8] = IGovernance.setPauseState.selector;
        selectors[9] = IGovernance.setProtocolConfig.selector;
        selectors[10] = IGovernance.setTreasuryRecipient.selector;
        selectors[11] = IGovernance.finalizeProtocol.selector;
    }

    function market() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IMarket.configureMarket.selector;
        selectors[1] = IMarket.launchMarket.selector;
        selectors[2] = IMarket.marketConfig.selector;
        selectors[3] = IMarket.canonicalPoolKey.selector;
        selectors[4] = IMarket.marketState.selector;
        selectors[5] = IMarket.marketLaunching.selector;
        selectors[6] = IMarket.marketReady.selector;
        selectors[7] = IMarket.lockedLpRecipient.selector;
    }

    function token() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](20);
        selectors[0] = IPotatoToken.name.selector;
        selectors[1] = IPotatoToken.symbol.selector;
        selectors[2] = IPotatoToken.decimals.selector;
        selectors[3] = IPotatoToken.totalSupply.selector;
        selectors[4] = IPotatoToken.balanceOf.selector;
        selectors[5] = IPotatoToken.allowance.selector;
        selectors[6] = IPotatoToken.approve.selector;
        selectors[7] = IPotatoToken.transfer.selector;
        selectors[8] = IPotatoToken.transferFrom.selector;
        selectors[9] = IPotatoToken.burn.selector;
        selectors[10] = IPotatoToken.permit.selector;
        selectors[11] = IPotatoToken.nonces.selector;
        selectors[12] = IPotatoToken.DOMAIN_SEPARATOR.selector;
        selectors[13] = IPotatoToken.protocolMint.selector;
        selectors[14] = IPotatoToken.protocolBurn.selector;
        selectors[15] = IPotatoToken.protocolTransfer.selector;
        selectors[16] = IPotatoToken.authorizePoolManagerTransfer.selector;
        selectors[17] = IPotatoToken.transientPoolManagerAllowance.selector;
        selectors[18] = IPotatoToken.isDistributor.selector;
        selectors[19] = IPotatoToken.setDistributor.selector;
    }

    function game() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IGame.buyPotato.selector;
        selectors[1] = IGame.materializeMaturedEmission.selector;
        selectors[2] = IGame.currentRoundId.selector;
        selectors[3] = IGame.getRound.selector;
        selectors[4] = IGame.currentEarnedEmission.selector;
    }

    function recovery() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IRecovery.commitRecovery.selector;
        selectors[1] = IRecovery.recoveryCommitment.selector;
        selectors[2] = IRecovery.totalRecoveryCommitment.selector;
    }

    function settlement() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ISettlement.settleRound.selector;
    }

    function claims() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IClaims.claimWinner.selector;
        selectors[1] = IClaims.claimRecovery.selector;
        selectors[2] = IClaims.claimTreasury.selector;
        selectors[3] = IClaims.claimTreasuryPotato.selector;
        selectors[4] = IClaims.treasuryRecipient.selector;
        selectors[5] = IClaims.treasuryEthAvailable.selector;
        selectors[6] = IClaims.treasuryPotatoAvailable.selector;
    }
}
