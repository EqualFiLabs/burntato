// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IOperatorRewards} from "../../src/interfaces/IOperatorRewards.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract PurchaseRevenueOperators {
    address public activationRegistry;
    bool public launchFinalized = true;
    mapping(uint256 operatorId => address owner) public ownerOf;

    function configure(address registry) external {
        activationRegistry = registry;
    }

    function setOwner(uint256 operatorId, address owner) external {
        ownerOf[operatorId] = owner;
    }
}

contract PurchaseRevenueRegistry {
    address public genesisCollection;
    mapping(uint256 operatorId => uint16 weight) public multiplierBps;

    function configure(address operators) external {
        genesisCollection = operators;
    }

    function setWeight(uint256 operatorId, uint16 weight) external {
        multiplierBps[operatorId] = weight;
    }
}

contract WrongBurntatoRouter {
    address public immutable burntato;

    constructor(address burntato_) {
        burntato = burntato_;
    }
}

contract OperatorPurchaseRevenueTest is DiamondTestSetup {
    uint256 private constant OPERATOR_ID = 1;

    address private operatorOwner = makeAddr("operator-owner");
    address private buyer = makeAddr("buyer");

    PurchaseRevenueOperators private operators;
    PurchaseRevenueRegistry private registry;
    BurntatoOperatorRewardsRouter private router;
    IGame private game;

    function setUp() public {
        operators = new PurchaseRevenueOperators();
        registry = new PurchaseRevenueRegistry();
        operators.configure(address(registry));
        registry.configure(address(operators));
        operators.setOwner(OPERATOR_ID, operatorOwner);
        registry.setWeight(OPERATOR_ID, 10_000);

        _deployCore();
        game = IGame(address(diamond));
        vm.deal(buyer, 10 ether);
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.recoveryBps = 3_000;
        config.treasuryBps = 2_000;
        config.operatorPurchaseBps = 1_500;
    }

    function _operatorRewardsRouterForInit() internal override returns (address) {
        router = new BurntatoOperatorRewardsRouter(address(diamond), address(operators), address(registry));
        return address(router);
    }

    function testPurchaseRoutesExactFiveWaySplitToSharedRouter() public {
        vm.prank(operatorOwner);
        router.register(OPERATOR_ID);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGame.OperatorPurchaseRevenueQueued(1, address(router), 0.0015 ether);
        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();

        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 0.0025 ether);
        assertEq(round.recoveryPool, 0.003 ether);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 0.002 ether);
        assertEq(IBuyback(address(diamond)).buybackReserveEth(), 0.001 ether);
        assertEq(router.pendingRevenue(), 0.0015 ether);
        assertEq(router.totalReceived(), 0.0015 ether);
        assertEq(address(diamond).balance, 0.0085 ether);
        assertEq(address(router).balance, 0.0015 ether);
        assertEq(game.purchaseOperatorRewardsRouter(), address(router));

        vm.prank(operatorOwner);
        assertEq(router.claim(OPERATOR_ID, operatorOwner), 0.0015 ether);
    }

    function testPurchaseAndHookRevenueAccrueThroughOneIndex() public {
        vm.prank(operatorOwner);
        router.register(OPERATOR_ID);

        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();
        vm.deal(address(this), 0.004 ether);
        (bool success,) = address(router).call{value: 0.004 ether}("");
        assertTrue(success);

        vm.prank(operatorOwner);
        assertEq(router.claim(OPERATOR_ID, operatorOwner), 0.0055 ether);
    }

    function testNoRegisteredWeightCreditsPurchaseRevenueToTreasury() public {
        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();
        router.accrue();

        assertEq(router.treasuryClaimable(), 0.0015 ether);

        vm.prank(operatorOwner);
        router.register(OPERATOR_ID);
        vm.prank(operatorOwner);
        assertEq(router.claim(OPERATOR_ID, operatorOwner), 0);
    }

    function testInitializationRejectsMissingOrMismatchedRouter() public {
        ProtocolConfig memory config = _initialConfig();
        _expectInitializationFailure(config, address(0));
        _expectInitializationFailure(config, address(new WrongBurntatoRouter(address(0xBEEF))));
    }

    function testTinyPurchaseAssignsAllFiveWayDustToTreasury() public {
        ProtocolConfig memory next = _initialConfig();
        next.startingPrice = 7;
        next.priceIncreaseBps = 0;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(next);

        vm.deal(buyer, 7);
        vm.prank(buyer);
        game.buyPotato{value: 7}();

        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 1);
        assertEq(round.recoveryPool, 2);
        assertEq(IBuyback(address(diamond)).buybackReserveEth(), 0);
        assertEq(router.pendingRevenue(), 1);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 3);
        assertEq(address(diamond).balance + address(router).balance, 7);
    }

    function testOperatorShareChangeAppliesOnlyToFutureRoundSnapshot() public {
        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();

        ProtocolConfig memory next = _defaultConfig();
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(next);

        vm.prank(buyer);
        game.buyPotato{value: 0.011 ether}();
        assertEq(router.totalReceived(), 0.00315 ether);

        vm.warp(game.getRound(1).deadline);
        ISettlement(address(diamond)).settleRound();
        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();
        assertEq(router.totalReceived(), 0.00465 ether);

        vm.warp(game.getRound(2).deadline);
        ISettlement(address(diamond)).settleRound();
        vm.prank(buyer);
        game.buyPotato{value: 0.01 ether}();

        assertEq(game.getRound(1).config.operatorPurchaseBps, 1_500);
        assertEq(game.getRound(2).config.operatorPurchaseBps, 1_500);
        assertEq(game.getRound(3).config.operatorPurchaseBps, 0);
        assertEq(router.totalReceived(), 0.00465 ether);
    }

    function testFuzzFiveWayPurchaseSplitConservesEveryWei(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000 ether);
        ProtocolConfig memory next = _initialConfig();
        next.startingPrice = amount;
        next.priceIncreaseBps = 0;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(next);

        vm.deal(buyer, amount);
        vm.prank(buyer);
        game.buyPotato{value: amount}();

        Round memory round = game.getRound(1);
        uint256 treasuryShare = IClaims(address(diamond)).treasuryEthAvailable();
        uint256 buybackShare = IBuyback(address(diamond)).buybackReserveEth();
        uint256 operatorShare = address(router).balance;
        assertEq(round.winnerPool, amount * 2_500 / 10_000);
        assertEq(round.recoveryPool, amount * 3_000 / 10_000);
        assertEq(buybackShare, amount * 1_000 / 10_000);
        assertEq(operatorShare, amount * 1_500 / 10_000);
        assertEq(round.winnerPool + round.recoveryPool + treasuryShare + buybackShare + operatorShare, amount);
    }

    function _expectInitializationFailure(ProtocolConfig memory config, address candidateRouter) private {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        BurntatoDiamond candidate = new BurntatoDiamond(authority, address(cutFacet));
        FoundationInit initializer = new FoundationInit();
        FacetCut[] memory noCuts = new FacetCut[](0);

        vm.prank(authority);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InitializationFailed.selector, abi.encodeWithSelector(Errors.InvalidProtocolConfig.selector)
            )
        );
        IDiamondCut(address(candidate))
            .diamondCut(
                noCuts,
                address(initializer),
                abi.encodeCall(FoundationInit.initialize, (config, treasury, candidateRouter, 1 ether))
            );
    }
}
