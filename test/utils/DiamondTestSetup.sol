// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {ClaimsFacet} from "../../src/facets/ClaimsFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../../src/facets/SettlementFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";

abstract contract DiamondTestSetup is Test {
    address internal authority = makeAddr("authority");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");

    BurntatoDiamond internal diamond;

    function _deployCore() internal {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(authority, address(cutFacet));

        _install(address(new DiamondLoupeFacet()), _loupeSelectors());
        _install(address(new GovernanceFacet()), _governanceSelectors());
        _install(address(new PotatoTokenFacet()), _tokenSelectors());
        _install(address(new GameFacet()), _gameSelectors());
        _install(address(new RecoveryFacet()), _recoverySelectors());
        _install(address(new SettlementFacet()), _settlementSelectors());
        _install(address(new ClaimsFacet()), _claimSelectors());

        FoundationInit initializer = new FoundationInit();
        FacetCut[] memory noCuts = new FacetCut[](0);
        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                noCuts, address(initializer), abi.encodeCall(FoundationInit.initialize, (0.01 ether, 1_000, treasury))
            );
        vm.prank(authority);
        IGovernance(address(diamond)).setGuardian(guardian);
    }

    function _install(address facet, bytes4[] memory selectors) internal {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(facet, FacetCutAction.Add, selectors);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
    }

    function _governanceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = IGovernance.authority.selector;
        selectors[1] = IGovernance.guardian.selector;
        selectors[2] = IGovernance.purchasesPaused.selector;
        selectors[3] = IGovernance.commitmentsPaused.selector;
        selectors[4] = IGovernance.protocolFinalized.selector;
        selectors[5] = IGovernance.parameterFrozen.selector;
        selectors[6] = IGovernance.selectorFrozen.selector;
        selectors[7] = IGovernance.setAuthority.selector;
        selectors[8] = IGovernance.setGuardian.selector;
        selectors[9] = IGovernance.setPauseState.selector;
        selectors[10] = IGovernance.setProtocolConfig.selector;
        selectors[11] = IGovernance.setTreasuryRecipient.selector;
        selectors[12] = IGovernance.freezeParameter.selector;
        selectors[13] = IGovernance.freezeSelectors.selector;
        selectors[14] = IGovernance.finalizeProtocol.selector;
    }

    function _tokenSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
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
        selectors[10] = IPotatoToken.authorizePoolManagerTransfer.selector;
        selectors[11] = IPotatoToken.transientPoolManagerAllowance.selector;
    }

    function _gameSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IGame.buyPotato.selector;
        selectors[1] = IGame.materializeMaturedEmission.selector;
        selectors[2] = IGame.currentRoundId.selector;
        selectors[3] = IGame.getRound.selector;
        selectors[4] = IGame.currentEarnedEmission.selector;
    }

    function _recoverySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IRecovery.commitRecovery.selector;
        selectors[1] = IRecovery.recoveryCommitment.selector;
        selectors[2] = IRecovery.totalRecoveryCommitment.selector;
    }

    function _settlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ISettlement.settleRound.selector;
    }

    function _claimSelectors() internal pure returns (bytes4[] memory selectors) {
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
