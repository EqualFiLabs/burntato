// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

import {MockStatics} from "../mocks/MockStatics.sol";

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {ClaimsFacet} from "../../src/facets/ClaimsFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../../src/facets/SettlementFacet.sol";
import {TreasuryRewardsFacet} from "../../src/facets/TreasuryRewardsFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {BuybackConfig, FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";

abstract contract DiamondTestSetup is Test {
    uint256 internal constant INITIAL_REWARD_INVENTORY = 1_000_000 ether;
    address internal authority = makeAddr("authority");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");

    BurntatoDiamond internal diamond;
    MockStatics internal statics;

    function _deployCore() internal {
        _deployCoreWithPurchaseInitialization(true);
    }

    function _deployCoreWithoutPurchaseInitialization() internal {
        _deployCoreWithPurchaseInitialization(false);
    }

    function _deployCoreWithPurchaseInitialization(bool initializePurchases_) private {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(authority, address(cutFacet));

        _install(address(new DiamondLoupeFacet()), BurntatoSelectors.loupe());
        _install(address(new GovernanceFacet()), BurntatoSelectors.governance());
        _install(address(new BuybackFacet()), BurntatoSelectors.buyback());
        _install(address(new PotatoTokenFacet()), BurntatoSelectors.token());
        _install(address(new GameFacet()), BurntatoSelectors.game());
        _install(address(new RecoveryFacet()), BurntatoSelectors.recovery());
        _install(address(new SettlementFacet()), BurntatoSelectors.settlement());
        _install(address(new ClaimsFacet()), BurntatoSelectors.claims());
        _install(address(new TreasuryRewardsFacet()), BurntatoSelectors.treasuryRewards());

        statics = new MockStatics();
        FoundationInit initializer = new FoundationInit();
        ProtocolConfig memory initialConfig = _initialConfig();
        address operatorRewardsRouter = _operatorRewardsRouterForInit();
        FacetCut[] memory noCuts = new FacetCut[](0);
        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                noCuts,
                address(initializer),
                abi.encodeCall(
                    FoundationInit.initialize, (initialConfig, treasury, operatorRewardsRouter, _underlyingForInit(), 0)
                )
            );
        vm.prank(authority);
        IGovernance(address(diamond)).setGuardian(guardian);
        vm.prank(authority);
        IPotatoToken(address(diamond)).setDistributor(treasury, true);
        vm.prank(authority);
        IBuyback(address(diamond)).setBuybackConfig(_defaultBuybackConfig());
        vm.prank(authority);
        ITreasuryRewards(address(diamond)).setRewardAllocator(treasury);
        if (_initialRewardFunding() != 0) {
            statics.mint(address(this), _initialRewardFunding());
            statics.approve(address(diamond), _initialRewardFunding());
            IPotatoToken(address(diamond)).fundRewardReserve(_initialRewardFunding());
        }
        if (initializePurchases_) {
            vm.prank(authority);
            IGovernance(address(diamond)).initializePurchases();
        }
    }

    function _underlyingForInit() internal view virtual returns (address) {
        return address(statics);
    }

    function _initialRewardFunding() internal pure virtual returns (uint256) {
        return 1_000_000 ether;
    }

    function _initialConfig() internal view virtual returns (ProtocolConfig memory config) {
        return _defaultConfig();
    }

    function _operatorRewardsRouterForInit() internal virtual returns (address) {
        return address(0);
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
            nextRoundWinnerBps: 200,
            recoveryBps: 4_000,
            treasuryBps: 2_300,
            buybackBps: 1_000,
            operatorPurchaseBps: 0,
            roundTimeoutDecay: 5 minutes,
            minimumRoundTimeout: 5 minutes
        });
    }

    function _configWithPrice(uint256 price, uint16 increaseBps) internal pure returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.startingPrice = price;
        config.priceIncreaseBps = increaseBps;
    }

    function _defaultBuybackConfig() internal pure returns (BuybackConfig memory config) {
        config = BuybackConfig({maxSpend: 1 ether, callerRewardBps: 50, delayBlocks: 1});
    }
}
