// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

contract BurntatoActivationProperties is Test {
    address private constant FINAL_ADMIN = address(0xA11CE);
    address private constant TREASURY = address(0xBEEF);

    BurntatoDiamond private diamond;
    IGame private game;
    IGovernance private governance;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut({
            facetAddress: address(new GovernanceFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.governance()
        });
        cuts[1] = FacetCut({
            facetAddress: address(new GameFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.game()
        });

        FoundationInit foundation = new FoundationInit();
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(foundation),
            abi.encodeCall(FoundationInit.initialize, (_config(), TREASURY, address(0), 1 ether))
        );

        game = IGame(address(diamond));
        governance = IGovernance(address(diamond));
        governance.setAuthority(FINAL_ADMIN);
    }

    function check_everyPurchaseRevertsBeforeInitialization(uint96 payment, address buyer) public {
        vm.assume(buyer != address(0));
        vm.deal(buyer, payment);
        vm.prank(buyer);
        (bool success, bytes memory reason) = address(game).call{value: payment}(abi.encodeCall(IGame.buyPotato, ()));

        assertFalse(success);
        assertEq(_selector(reason), Errors.PurchasesNotInitialized.selector);
        assertFalse(governance.purchasesInitialized());
        assertEq(game.currentRoundId(), 0);
    }

    function check_onlyCurrentAuthorityCanInitialize(address caller) public {
        vm.assume(caller != address(0) && caller != FINAL_ADMIN);
        vm.prank(caller);
        (bool success, bytes memory reason) = address(governance).call(abi.encodeCall(IGovernance.initializePurchases, ()));

        assertFalse(success);
        assertEq(_selector(reason), Errors.NotAuthority.selector);
        assertFalse(governance.purchasesInitialized());
    }

    function check_successorAuthorityCanInitialize(address successor) public {
        vm.assume(successor != address(0) && successor != FINAL_ADMIN);

        vm.prank(FINAL_ADMIN);
        governance.setAuthority(successor);

        vm.prank(FINAL_ADMIN);
        (bool formerAdminSucceeded, bytes memory reason) =
            address(governance).call(abi.encodeCall(IGovernance.initializePurchases, ()));
        assertFalse(formerAdminSucceeded);
        assertEq(_selector(reason), Errors.NotAuthority.selector);

        vm.prank(successor);
        governance.initializePurchases();
        assertTrue(governance.purchasesInitialized());
    }

    function check_finalAdminActivationIsOneShot() public {
        vm.prank(FINAL_ADMIN);
        governance.initializePurchases();
        assertTrue(governance.purchasesInitialized());

        vm.prank(FINAL_ADMIN);
        (bool success, bytes memory reason) = address(governance).call(abi.encodeCall(IGovernance.initializePurchases, ()));
        assertFalse(success);
        assertEq(_selector(reason), Errors.AlreadyInitialized.selector);
        assertTrue(governance.purchasesInitialized());
    }

    function check_firstPurchaseSucceedsAfterActivation(address buyer) public {
        vm.assume(buyer != address(0) && buyer != address(diamond));
        vm.prank(FINAL_ADMIN);
        governance.initializePurchases();

        vm.deal(buyer, 1);
        vm.prank(buyer);
        game.buyPotato{value: 1}();

        assertEq(game.currentRoundId(), 1);
        assertEq(address(diamond).balance, 1);
    }

    function check_nonPurchaseViewsRemainAvailable() public view {
        assertTrue(governance.foundationConfigured());
        assertFalse(governance.purchasesInitialized());
        assertFalse(governance.purchasesPaused());
        assertFalse(governance.commitmentsPaused());
        assertEq(game.currentRoundId(), 0);
        assertEq(game.getRound(0).currentHolder, address(0));
        (uint256 baseEarned, uint256 treasuryEarned) = game.currentEarnedEmission();
        assertEq(baseEarned, 0);
        assertEq(treasuryEarned, 0);
        assertEq(game.purchaseOperatorRewardsRouter(), address(0));
    }

    function _config() private pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: 1,
            priceIncreaseBps: 0,
            roundTimeout: 1,
            roundEmissionBudget: 0,
            emissionStepBps: 0,
            emissionVestingDuration: 1,
            winnerBps: 10_000,
            recoveryBps: 0,
            treasuryBps: 0,
            buybackBps: 0,
            operatorPurchaseBps: 0,
            recoveryBurnBps: 10_000,
            recoveryTreasuryBps: 0,
            roundTimeoutDecay: 0,
            minimumRoundTimeout: 1
        });
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
