// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";
import {LibMath} from "../../src/libraries/LibMath.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";

contract StorageFacetV1 {
    function setCurrentRoundId(uint256 value) external {
        LibProtocolStorage.game().currentRoundId = value;
    }

    function currentRoundId() external view returns (uint256) {
        return LibProtocolStorage.game().currentRoundId;
    }
}

contract StorageFacetV2 {
    function currentRoundId() external view returns (uint256) {
        return LibProtocolStorage.game().currentRoundId + 1;
    }
}

contract MathHarness {
    function mulBpsDown(uint256 amount, uint256 bps) external pure returns (uint256) {
        return LibMath.mulBpsDown(amount, bps);
    }

    function mulBpsUp(uint256 amount, uint256 bps) external pure returns (uint256) {
        return LibMath.mulBpsUp(amount, bps);
    }

    function linearEarned(uint256 maxReward, uint256 heldSeconds) external pure returns (uint256) {
        return LibMath.linearEarned(maxReward, heldSeconds, 120);
    }

    function diminishingTimeout(uint256 initialTimeout, uint256 decay, uint256 minimumTimeout, uint256 priorPurchases)
        external
        pure
        returns (uint256)
    {
        return LibMath.diminishingTimeout(initialTimeout, decay, minimumTimeout, priorPurchases);
    }

    function splitRecovery(uint256 amount) external pure returns (uint256, uint256) {
        return LibMath.splitRecovery(amount, 1_000);
    }
}

contract DiamondFoundationTest is Test {
    address internal authority = makeAddr("authority");
    address internal treasury = makeAddr("treasury");

    BurntatoDiamond internal diamond;
    DiamondCutFacet internal cutFacet;
    DiamondLoupeFacet internal loupeFacet;
    StorageFacetV1 internal storageFacet;
    FoundationInit internal initializer;
    MathHarness internal math;

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(authority, address(cutFacet));
        loupeFacet = new DiamondLoupeFacet();
        storageFacet = new StorageFacetV1();
        initializer = new FoundationInit();
        math = new MathHarness();

        FacetCut[] memory cuts = new FacetCut[](2);
        bytes4[] memory loupeSelectors = new bytes4[](4);
        loupeSelectors[0] = IDiamondLoupe.facets.selector;
        loupeSelectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupe.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupe.facetAddress.selector;
        cuts[0] = FacetCut(address(loupeFacet), FacetCutAction.Add, loupeSelectors);

        bytes4[] memory storageSelectors = new bytes4[](2);
        storageSelectors[0] = StorageFacetV1.setCurrentRoundId.selector;
        storageSelectors[1] = StorageFacetV1.currentRoundId.selector;
        cuts[1] = FacetCut(address(storageFacet), FacetCutAction.Add, storageSelectors);

        vm.prank(authority);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts,
                address(initializer),
                abi.encodeCall(FoundationInit.initialize, (_config(), treasury, address(0), 1 ether))
            );
    }

    function _config() private pure returns (ProtocolConfig memory config) {
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
            operatorPurchaseBps: 0,
            recoveryBurnBps: 9_000,
            recoveryTreasuryBps: 1_000,
            roundTimeoutDecay: 5 minutes,
            minimumRoundTimeout: 5 minutes
        });
    }

    function test_RoutesAndEnumeratesInstalledSelectors() public view {
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(StorageFacetV1.currentRoundId.selector), address(storageFacet)
        );
        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, 3);
        assertEq(IDiamondLoupe(address(diamond)).facetFunctionSelectors(address(storageFacet)).length, 2);
    }

    function test_RejectsUnauthorizedDiamondCut() public {
        FacetCut[] memory cuts = new FacetCut[](0);
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function test_PreservesNamespacedStateAcrossFacetReplacement() public {
        StorageFacetV1(address(diamond)).setCurrentRoundId(41);
        assertEq(StorageFacetV1(address(diamond)).currentRoundId(), 41);

        StorageFacetV2 replacement = new StorageFacetV2();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = StorageFacetV1.currentRoundId.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        assertEq(StorageFacetV2(address(diamond)).currentRoundId(), 42);
    }

    function test_RemovesSelectorWithoutCorruptingOtherRouting() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = StorageFacetV1.setCurrentRoundId.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(0), FacetCutAction.Remove, selectors);

        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        assertEq(IDiamondLoupe(address(diamond)).facetAddress(selectors[0]), address(0));
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(StorageFacetV1.currentRoundId.selector), address(storageFacet)
        );
    }

    function test_MathUsesSpecifiedRoundingAndCapsVesting() public view {
        assertEq(math.mulBpsDown(101, 1_000), 10);
        assertEq(math.mulBpsUp(101, 1_000), 11);
        assertEq(math.linearEarned(10_000 ether, 30), 2_500 ether);
        assertEq(math.linearEarned(10_000 ether, 121), 10_000 ether);
        (uint256 burned, uint256 treasuryPotato) = math.splitRecovery(101);
        assertEq(burned, 91);
        assertEq(treasuryPotato, 10);
    }

    function test_DiminishingTimeoutSaturatesWithoutUnderflowOrOverflow() public view {
        assertEq(math.diminishingTimeout(1 hours, 5 minutes, 5 minutes, 0), 1 hours);
        assertEq(math.diminishingTimeout(1 hours, 5 minutes, 5 minutes, 10), 10 minutes);
        assertEq(math.diminishingTimeout(1 hours, 5 minutes, 5 minutes, 11), 5 minutes);
        assertEq(math.diminishingTimeout(1 hours, 5 minutes, 5 minutes, type(uint256).max), 5 minutes);
        assertEq(math.diminishingTimeout(1_000, 333, 100, 2), 334);
        assertEq(math.diminishingTimeout(1_000, 333, 100, 3), 100);
    }
}
