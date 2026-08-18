// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IGame} from "../../src/interfaces/IGame.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract PotatoGameLifecycleTest is DiamondTestSetup {
    bytes32 internal constant BUYBACK_SLOT = keccak256("burntato.storage.buyback.v1");
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    IGame internal game;
    IPotatoToken internal potato;

    function setUp() public {
        _deployCore();
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_FullHoldReproducesGeometricStep() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 10_000 ether);
        assertEq(round.remainingEmission, 90_000 ether);
        assertEq(round.emittedPotato, 10_000 ether);
        assertEq(round.holderMaxReward, 9_000 ether);
    }

    function test_PartialHoldPreservesUnusedBudget() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 30);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 2_500 ether);
        assertEq(round.remainingEmission, 97_500 ether);
        assertEq(round.holderMaxReward, 9_750 ether);
    }

    function test_ZeroTimeCyclingDoesNotConsumeEmission() public {
        _buy(alice, 0.01 ether);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), 0);
        assertEq(round.remainingEmission, 100_000 ether);
        assertEq(round.holderMaxReward, 10_000 ether);
    }

    function test_DefaultTimerDiminishesToFiveMinuteFloorDuringAtomicCycling() public {
        uint256 expectedPrice = 0.01 ether;
        for (uint256 i; i < 14; ++i) {
            address buyer = address(uint160(1_000 + i));
            vm.deal(buyer, expectedPrice);
            _buy(buyer, expectedPrice);

            Round memory round = game.getRound(1);
            uint256 expectedDuration = i < 11 ? 1 hours - i * 5 minutes : 5 minutes;
            assertEq(round.deadline - round.holderSince, expectedDuration);
            assertEq(round.deadline, block.timestamp + expectedDuration);
            assertEq(round.purchaseIndex, i + 1);
            assertEq(round.remainingEmission, 100_000 ether);
            expectedPrice = round.nextPrice;
        }
    }

    function test_ElapsedTimeDoesNotReduceResetFromPurchaseTimestamp() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        _buy(bob, 0.011 ether);

        Round memory round = game.getRound(1);
        assertEq(round.deadline, block.timestamp + 55 minutes);
        assertEq(round.deadline - round.holderSince, 55 minutes);
    }

    function test_SelfAndContractPurchasesCountWhileRevertsDoNot() public {
        _buy(alice, 0.01 ether);
        _buy(alice, 0.011 ether);
        Round memory beforeRevert = game.getRound(1);
        assertEq(beforeRevert.deadline - beforeRevert.holderSince, 55 minutes);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.IncorrectPayment.selector, beforeRevert.nextPrice, 1));
        game.buyPotato{value: 1}();
        Round memory afterRevert = game.getRound(1);
        assertEq(afterRevert.purchaseIndex, beforeRevert.purchaseIndex);
        assertEq(afterRevert.deadline, beforeRevert.deadline);

        vm.deal(address(this), beforeRevert.nextPrice);
        game.buyPotato{value: beforeRevert.nextPrice}();
        Round memory afterContractPurchase = game.getRound(1);
        assertEq(afterContractPurchase.purchaseIndex, 3);
        assertEq(afterContractPurchase.deadline - afterContractPurchase.holderSince, 50 minutes);
    }

    function test_NonEvenDecayClampsAtConfiguredFloor() public {
        ProtocolConfig memory config = _defaultConfig();
        config.priceIncreaseBps = 0;
        config.roundTimeout = 1_000;
        config.roundTimeoutDecay = 333;
        config.minimumRoundTimeout = 100;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);

        uint256[5] memory expected = [uint256(1_000), 667, 334, 100, 100];
        for (uint256 i; i < expected.length; ++i) {
            address buyer = address(uint160(2_000 + i));
            vm.deal(buyer, 0.01 ether);
            _buy(buyer, 0.01 ether);
            Round memory round = game.getRound(1);
            assertEq(round.deadline - round.holderSince, expected[i]);
        }
    }

    function test_ZeroDecayRestoresFixedResets() public {
        ProtocolConfig memory config = _defaultConfig();
        config.roundTimeoutDecay = 0;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);
        _buy(alice, 0.01 ether);
        _buy(bob, 0.011 ether);
        assertEq(game.getRound(1).deadline - block.timestamp, 1 hours);
    }

    function test_MinimumEqualToInitialRestoresFixedResets() public {
        ProtocolConfig memory config = _defaultConfig();
        config.minimumRoundTimeout = config.roundTimeout;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);
        _buy(alice, 0.01 ether);
        _buy(bob, 0.011 ether);
        assertEq(game.getRound(1).deadline - block.timestamp, 1 hours);
    }

    function test_NewRoundRestartsAtInitialTimeout() public {
        _buy(alice, 0.01 ether);
        _buy(bob, 0.011 ether);
        Round memory roundOne = game.getRound(1);
        assertEq(roundOne.deadline - roundOne.holderSince, 55 minutes);

        vm.warp(roundOne.deadline);
        ISettlement(address(diamond)).settleRound();
        _buy(alice, 0.01 ether);

        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.purchaseIndex, 1);
        assertEq(roundTwo.deadline - roundTwo.holderSince, 1 hours);
    }

    function test_MaterializedRewardCannotMintTwice() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        (uint256 baseEarned, uint256 treasuryEarned) = game.materializeMaturedEmission();
        assertEq(baseEarned, 10_000 ether);
        assertEq(treasuryEarned, 0);
        assertEq(potato.balanceOf(alice), 10_000 ether);

        _buy(bob, 0.011 ether);
        assertEq(potato.balanceOf(alice), 10_000 ether);
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY + 10_000 ether);
    }

    function test_RewardNeverExceedsSnapshot() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 10 days);
        (uint256 baseEarned, uint256 treasuryEarned) = game.currentEarnedEmission();
        assertEq(baseEarned, 10_000 ether);
        assertEq(treasuryEarned, 0);
        vm.prank(keeper);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 10_000 ether);
    }

    function test_ApprovalDoesNotBypassTransferRestrictionAndSelfBurnWorks() public {
        _earnForAlice();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, address(0)));
        potato.transfer(address(0), 1 ether);
        assertEq(potato.balanceOf(address(0)), 0);
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY + 10_000 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transfer(bob, 1 ether);

        vm.prank(alice);
        potato.approve(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transferFrom(alice, bob, 1 ether);
        assertEq(potato.allowance(alice, bob), 1 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, address(0)));
        potato.transferFrom(alice, address(0), 1 ether);
        assertEq(potato.allowance(alice, bob), 1 ether);

        vm.prank(alice);
        potato.burn(1 ether);
        assertEq(potato.balanceOf(alice), 9_999 ether);
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY + 9_999 ether);
    }

    function test_PermitSetsAllowanceButDoesNotBypassTransferRestriction() public {
        uint256 signerKey = 0xA11CE;
        address signer = vm.addr(signerKey);
        vm.deal(signer, 1 ether);
        _buy(signer, 0.01 ether);
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();

        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, signer, bob, 1 ether, 0, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", potato.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        potato.permit(signer, bob, 1 ether, deadline, v, r, s);
        assertEq(potato.nonces(signer), 1);
        assertEq(potato.allowance(signer, bob), 1 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, signer, bob));
        potato.transferFrom(signer, bob, 1 ether);
        assertEq(potato.allowance(signer, bob), 1 ether);
    }

    function test_DistributorEndpointAllowsTransfersUntilRevoked() public {
        _earnForAlice();

        vm.prank(authority);
        potato.setDistributor(bob, true);
        assertTrue(potato.isDistributor(bob));

        vm.prank(alice);
        potato.transfer(bob, 2 ether);
        vm.prank(bob);
        potato.transfer(alice, 1 ether);
        assertEq(potato.balanceOf(bob), 1 ether);

        vm.prank(authority);
        potato.setDistributor(bob, false);
        assertFalse(potato.isDistributor(bob));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transfer(bob, 1 ether);
    }

    function test_CurrentAuthorityIsAlwaysAValidTransferEndpoint() public {
        _earnForAlice();

        vm.prank(alice);
        potato.transfer(authority, 2 ether);
        vm.prank(authority);
        potato.transfer(bob, 1 ether);

        address nextAuthority = makeAddr("nextAuthority");
        vm.prank(authority);
        IGovernance(address(diamond)).setAuthority(nextAuthority);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, authority));
        potato.transfer(authority, 1 ether);
        vm.prank(alice);
        potato.transfer(nextAuthority, 1 ether);
    }

    function test_OnlyAuthorityCanAdministerDistributors() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, guardian));
        potato.setDistributor(bob, true);

        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        potato.setDistributor(address(0), true);
    }

    function test_TreasuryChangeDoesNotMutateDistributorRegistry() public {
        address nextTreasury = makeAddr("nextTreasury");
        assertTrue(potato.isDistributor(treasury));
        assertFalse(potato.isDistributor(nextTreasury));

        vm.prank(authority);
        IGovernance(address(diamond)).setTreasuryRecipient(nextTreasury);

        assertTrue(potato.isDistributor(treasury));
        assertFalse(potato.isDistributor(nextTreasury));
    }

    function test_FinalizationDoesNotDisableDistributorAdministration() public {
        vm.prank(authority);
        IGovernance(address(diamond)).finalizeProtocol();

        vm.prank(authority);
        potato.setDistributor(bob, true);
        assertTrue(potato.isDistributor(bob));
    }

    function test_ProtocolTokenEndpointsRejectExternalCallers() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotProtocol.selector, address(this)));
        potato.protocolMint(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotProtocol.selector, address(this)));
        potato.protocolBurn(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotProtocol.selector, address(this)));
        potato.protocolTransfer(alice, bob, 1 ether);
    }

    function test_PurchaseConservesNativeAllocationAndRaisesPrice() public {
        _buy(alice, 0.01 ether);
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 0.0025 ether);
        assertEq(round.recoveryPool, 0.004 ether);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 0.0025 ether);
        assertEq(uint256(vm.load(address(diamond), BUYBACK_SLOT)), 0.001 ether);
        assertEq(
            round.winnerPool + round.recoveryPool + IClaims(address(diamond)).treasuryEthAvailable()
                + uint256(vm.load(address(diamond), BUYBACK_SLOT)),
            0.01 ether
        );
        assertEq(round.nextPrice, 0.011 ether);
        assertEq(round.deadline, block.timestamp + 1 hours);
    }

    function test_PurchaseSplitAssignsAllRoundingDustToTreasury() public {
        ProtocolConfig memory config = _defaultConfig();
        config.startingPrice = 10_003;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);

        _buy(alice, 10_003);
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 2_500);
        assertEq(round.recoveryPool, 4_001);
        assertEq(uint256(vm.load(address(diamond), BUYBACK_SLOT)), 1_000);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 2_502);
    }

    function test_ConfiguredEconomicsDriveRoundPurchasesAndEmission() public {
        ProtocolConfig memory config = _defaultConfig();
        config.priceIncreaseBps = 0;
        config.roundTimeout = 300;
        config.roundEmissionBudget = 200_000 ether;
        config.emissionStepBps = 2_500;
        config.emissionVestingDuration = 40;
        config.winnerBps = 1_000;
        config.recoveryBps = 2_000;
        config.treasuryBps = 6_000;
        config.buybackBps = 1_000;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);

        _buy(alice, 0.01 ether);
        Round memory round = game.getRound(1);
        assertEq(round.nextPrice, 0.01 ether);
        assertEq(round.deadline, block.timestamp + 300);
        assertEq(round.remainingEmission, 200_000 ether);
        assertEq(round.holderMaxReward, 50_000 ether);
        assertEq(round.winnerPool, 0.001 ether);
        assertEq(round.recoveryPool, 0.002 ether);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 0.006 ether);

        vm.warp(block.timestamp + 40);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 50_000 ether);
    }

    function test_ZeroEmissionBudgetStillHasExplicitRoundLifecycle() public {
        ProtocolConfig memory config = _defaultConfig();
        config.priceIncreaseBps = 0;
        config.roundTimeout = 10;
        config.roundTimeoutDecay = 5;
        config.minimumRoundTimeout = 5;
        config.roundEmissionBudget = 0;
        config.emissionStepBps = 0;
        config.emissionVestingDuration = 5;
        vm.prank(authority);
        IGovernance(address(diamond)).setProtocolConfig(config);

        _buy(alice, 0.01 ether);
        Round memory roundOne = game.getRound(1);
        assertTrue(roundOne.activated);
        assertEq(roundOne.remainingEmission, 0);
        assertEq(roundOne.holderMaxReward, 0);

        vm.warp(roundOne.deadline);
        ISettlement(address(diamond)).settleRound();
        Round memory roundTwo = game.getRound(2);
        assertTrue(roundTwo.activated);
        assertEq(roundTwo.remainingEmission, 0);

        _buy(bob, 0.01 ether);
        vm.warp(block.timestamp + 5);
        game.materializeMaturedEmission();
        assertEq(potato.totalSupply(), GENESIS_MARKET_SUPPLY);
    }

    function _earnForAlice() internal {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        game.materializeMaturedEmission();
    }

    function _buy(address buyer, uint256 price) internal {
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }
}
