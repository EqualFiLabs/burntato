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

    function test_MaterializedRewardCannotMintTwice() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 120);
        vm.prank(keeper);
        assertEq(game.materializeMaturedEmission(), 10_000 ether);
        assertEq(potato.balanceOf(alice), 10_000 ether);

        _buy(bob, 0.011 ether);
        assertEq(potato.balanceOf(alice), 10_000 ether);
        assertEq(potato.totalSupply(), 10_000 ether);
    }

    function test_RewardNeverExceedsSnapshot() public {
        _buy(alice, 0.01 ether);
        vm.warp(block.timestamp + 10 days);
        assertEq(game.currentEarnedEmission(), 10_000 ether);
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
        assertEq(potato.totalSupply(), 10_000 ether);

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
        assertEq(potato.totalSupply(), 9_999 ether);
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
        assertEq(round.recoveryPool, 0.005 ether);
        assertEq(round.nextPrice, 0.011 ether);
        assertEq(round.deadline, block.timestamp + 1 hours);
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
        config.treasuryBps = 7_000;
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
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 0.007 ether);

        vm.warp(block.timestamp + 40);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 50_000 ether);
    }

    function test_ZeroEmissionBudgetStillHasExplicitRoundLifecycle() public {
        ProtocolConfig memory config = _defaultConfig();
        config.priceIncreaseBps = 0;
        config.roundTimeout = 10;
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
        assertEq(potato.totalSupply(), 0);
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
