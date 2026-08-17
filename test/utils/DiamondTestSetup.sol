// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {ClaimsFacet} from "../../src/facets/ClaimsFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {MarketFacet} from "../../src/facets/MarketFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../../src/facets/SettlementFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {BuybackConfig, FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";

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
        _install(address(new MarketFacet()), _marketSelectors());
        _install(address(new BuybackFacet()), _buybackSelectors());
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
                noCuts, address(initializer), abi.encodeCall(FoundationInit.initialize, (_defaultConfig(), treasury))
            );
        vm.prank(authority);
        IGovernance(address(diamond)).setGuardian(guardian);
        vm.prank(authority);
        IPotatoToken(address(diamond)).setDistributor(treasury, true);
        vm.prank(authority);
        IBuyback(address(diamond)).setBuybackConfig(_defaultBuybackConfig());
    }

    function _install(address facet, bytes4[] memory selectors) internal {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(facet, FacetCutAction.Add, selectors);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _defaultConfig() internal pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: 0.01 ether,
            priceIncreaseBps: 1_000,
            roundTimeout: 1 hours,
            roundEmissionBudget: 100_000 ether,
            emissionStepBps: 1_000,
            emissionVestingDuration: 120 seconds,
            winnerBps: 2_500,
            recoveryBps: 4_000,
            treasuryBps: 2_500,
            buybackBps: 1_000,
            recoveryBurnBps: 9_000,
            recoveryTreasuryBps: 1_000
        });
    }

    function _configWithPrice(uint256 price, uint16 increaseBps) internal pure returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.startingPrice = price;
        config.priceIncreaseBps = increaseBps;
    }

    function _defaultBuybackConfig() internal pure returns (BuybackConfig memory config) {
        config = BuybackConfig({maxSpend: 2 ether, callerRewardBps: 50, delayBlocks: 1});
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
    }

    function _governanceSelectors() internal pure returns (bytes4[] memory selectors) {
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

    function _tokenSelectors() internal pure returns (bytes4[] memory selectors) {
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

    function _marketSelectors() internal pure returns (bytes4[] memory selectors) {
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

    function _buybackSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IBuyback.setBuybackConfig.selector;
        selectors[1] = IBuyback.buybackConfig.selector;
        selectors[2] = IBuyback.buybackReserveEth.selector;
        selectors[3] = IBuyback.lastBuybackBlock.selector;
        selectors[4] = IBuyback.buyback.selector;
        selectors[5] = IBuyback.unlockCallback.selector;
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
