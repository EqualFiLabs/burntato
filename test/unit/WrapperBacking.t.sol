// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract WrapperBackingTest is DiamondTestSetup {
    IPotatoToken internal potato;
    IGame internal game;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function _initialRewardFunding() internal pure override returns (uint256) {
        return 0;
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.roundEmissionBudget = 5_000 ether;
        config.emissionVestingDuration = 4 minutes;
    }

    function setUp() public {
        _deployCore();
        potato = IPotatoToken(address(diamond));
        game = IGame(address(diamond));
        assertEq(potato.publicWrapCap(), 0);
        vm.prank(authority);
        potato.setPublicWrapCap(2_000_000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _wrap(address user, uint256 amount) internal {
        statics.mint(user, amount);
        vm.startPrank(user);
        statics.approve(address(diamond), amount);
        potato.wrap(amount);
        vm.stopPrank();
    }

    function _fund(uint256 amount) internal {
        statics.mint(address(this), amount);
        statics.approve(address(diamond), amount);
        potato.fundRewardReserve(amount);
    }

    function _buy(address user) internal {
        uint256 id = game.currentRoundId();
        uint256 price = id == 0 ? 0.01 ether : game.getRound(id).nextPrice;
        vm.prank(user);
        game.buyPotato{value: price}();
    }

    function test_FreshSupplyZeroAndUnfundedPaymentRollsBack() public {
        assertEq(potato.totalSupply(), 0);
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientRewardReserve.selector, 0, 5_000 ether));
        game.buyPotato{value: 0.01 ether}();
        assertEq(alice.balance, balanceBefore);
        assertEq(game.currentRoundId(), 0);
        assertEq(address(diamond).balance, 0);
    }

    function testFuzz_ExactRoundTrip(uint256 amount) public {
        amount = bound(amount, 1, 2_000_000 ether);
        _wrap(alice, amount);
        assertEq(potato.totalSupply(), amount);
        assertEq(potato.backingBalance(), amount);
        vm.prank(alice);
        potato.unwrap(amount);
        assertEq(statics.balanceOf(alice), amount);
        assertEq(potato.totalSupply(), 0);
        assertEq(potato.publicWrapOutstanding(), 0);
    }

    function test_CapBoundaryLoweringAndRedemption() public {
        _wrap(alice, 2_000_000 ether);
        statics.mint(bob, 1);
        vm.startPrank(bob);
        statics.approve(address(diamond), 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.PublicWrapCapacityExceeded.selector, 0, 1));
        potato.wrap(1);
        vm.stopPrank();
        vm.prank(authority);
        potato.setPublicWrapCap(1);
        vm.prank(alice);
        potato.unwrap(2_000_000 ether);
        assertEq(potato.availablePublicWrapCapacity(), 1);
        vm.prank(bob);
        potato.wrap(1);
        vm.prank(authority);
        potato.setPublicWrapCap(3_000_000 ether);
        assertEq(potato.availablePublicWrapCapacity(), 3_000_000 ether - 1);
    }

    function test_ZeroCapStaysClosedWhenOutstandingWrapsAreRedeemed() public {
        _wrap(alice, 10 ether);
        vm.prank(authority);
        potato.setPublicWrapCap(0);
        vm.prank(alice);
        potato.unwrap(10 ether);
        assertEq(potato.publicWrapOutstanding(), 0);
        assertEq(potato.publicWrapCap(), 0);
        assertEq(potato.availablePublicWrapCapacity(), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.PublicWrapCapacityExceeded.selector, 0, 1));
        potato.wrap(1);
    }

    function test_ReserveFundingAbovePublicCapAndRewardRedemptionReopensCapacity() public {
        _wrap(bob, 2_000_000 ether);
        _fund(3_000_000 ether);
        assertEq(potato.publicWrapOutstanding(), 2_000_000 ether);
        assertEq(potato.rewardReserve(), 3_000_000 ether);
        _buy(alice);
        vm.warp(block.timestamp + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 500 ether);
        vm.prank(alice);
        potato.unwrap(500 ether);
        assertEq(potato.availablePublicWrapCapacity(), 500 ether);
        assertEq(potato.backingBalance(), potato.totalSupply());
    }

    function test_DonationsDoNotIssueSupplyOrChangeRedemptionRate() public {
        _wrap(alice, 10 ether);
        statics.mint(address(diamond), 123 ether);
        assertEq(potato.totalSupply(), 10 ether);
        vm.prank(alice);
        potato.unwrap(10 ether);
        assertEq(statics.balanceOf(alice), 10 ether);
        assertEq(potato.backingBalance(), 123 ether);
        assertEq(potato.rewardReserve(), 0);
    }

    function test_RemovedSelectorsCannotIssueOrDestroySupply() public {
        _wrap(alice, 1 ether);
        bytes4[4] memory removed = [
            bytes4(keccak256("burn(uint256)")),
            bytes4(keccak256("protocolMint(address,uint256)")),
            bytes4(keccak256("protocolBurn(address,uint256)")),
            bytes4(keccak256("authorizePoolManagerTransfer(uint256)"))
        ];
        for (uint256 i; i < removed.length; ++i) {
            vm.prank(alice);
            (bool ok,) = address(diamond).call(abi.encodeWithSelector(removed[i], alice, 1 ether));
            assertFalse(ok);
        }
        assertEq(potato.totalSupply(), 1 ether);
    }

    function test_FailedDepositAndFeeTransferRollBack() public {
        statics.mint(alice, 10 ether);
        vm.startPrank(alice);
        statics.approve(address(diamond), 10 ether);
        statics.setFailure(true);
        vm.expectRevert();
        potato.wrap(10 ether);
        statics.setFailure(false);
        statics.setFee(1);
        vm.expectRevert(Errors.InvalidBacking.selector);
        potato.wrap(10 ether);
        vm.stopPrank();
        assertEq(statics.balanceOf(alice), 10 ether);
        assertEq(potato.totalSupply(), 0);
        assertEq(potato.publicWrapOutstanding(), 0);
    }

    function test_RedemptionFailureRollsBackBurnAndCapacity() public {
        _wrap(alice, 10 ether);
        statics.setFailure(true);
        vm.prank(alice);
        vm.expectRevert();
        potato.unwrap(10 ether);
        assertEq(potato.balanceOf(alice), 10 ether);
        assertEq(potato.publicWrapOutstanding(), 10 ether);
        assertEq(potato.backingBalance(), 10 ether);
    }

    function test_OutgoingFeeRollsBackRedemptionAccounting() public {
        _wrap(alice, 10 ether);
        _fund(5_000 ether);
        statics.setFee(1);
        vm.prank(alice);
        vm.expectRevert(Errors.InvalidBacking.selector);
        potato.unwrap(10 ether);
        assertEq(potato.balanceOf(alice), 10 ether);
        assertEq(potato.publicWrapOutstanding(), 10 ether);
        assertEq(potato.totalSupply(), 5_010 ether);
        assertEq(potato.backingBalance(), 5_010 ether);
        assertEq(potato.rewardReserve(), 5_000 ether);
        assertEq(statics.balanceOf(alice), 0);
    }

    function test_RemovingDiamondCutPreventsUpgradesAndPreservesGameplayAndRedemption() public {
        _wrap(alice, 10 ether);
        _fund(5_000 ether);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(0), FacetCutAction.Remove, selectors);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(Errors.FunctionNotFound.selector, IDiamondCut.diamondCut.selector));
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        _buy(alice);
        vm.warp(vm.getBlockTimestamp() + 4 minutes);
        game.materializeMaturedEmission();
        vm.prank(alice);
        potato.unwrap(510 ether);
        assertEq(statics.balanceOf(alice), 510 ether);
        assertEq(potato.totalSupply(), 4_500 ether);
        assertEq(potato.backingBalance(), 4_500 ether);
        assertEq(potato.publicWrapOutstanding(), 0);
    }

    function test_UnderlyingCannotReenterWrapOrRedemption() public {
        statics.setCallback(address(diamond), abi.encodeCall(IPotatoToken.wrap, (1)));
        _wrap(alice, 10 ether);
        assertFalse(statics.callbackSucceeded());
        statics.setCallback(address(diamond), abi.encodeCall(IPotatoToken.unwrap, (1)));
        vm.prank(alice);
        potato.unwrap(10 ether);
        assertFalse(statics.callbackSucceeded());
        assertEq(potato.totalSupply(), 0);
    }

    function test_PauseKeepsRedemptionAndFundingLiveButBlocksWrapping() public {
        _wrap(alice, 1 ether);
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        vm.prank(alice);
        potato.unwrap(1 ether);
        _fund(5_000 ether);
        vm.prank(alice);
        vm.expectRevert(Errors.ProtocolPaused.selector);
        potato.wrap(1);
        assertEq(potato.rewardReserve(), 5_000 ether);
    }

    function test_FundedRoundPaysOnceAndUnusedInventoryRemains() public {
        _fund(5_000 ether);
        vm.deal(address(this), 1 ether);
        game.fundWinnerReserve{value: 1 ether}(1);
        _buy(alice);
        vm.warp(block.timestamp + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(potato.rewardReserve(), 4_500 ether);
        assertEq(potato.availableRewardInventory(), 0);
        vm.expectRevert(Errors.AlreadyFinalized.selector);
        game.materializeMaturedEmission();
        vm.warp(game.getRound(1).deadline);
        ISettlement(address(diamond)).settleRound();
        assertEq(potato.rewardReserve(), 4_500 ether);
        (, uint256 required, uint256 available, bool funded) = potato.nextRoundFundingStatus();
        assertEq(required, 5_000 ether);
        assertEq(available, 4_500 ether);
        assertFalse(funded);
        vm.prank(alice);
        IClaims(address(diamond)).claimWinner(1, alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientRewardReserve.selector, 4_500 ether, 5_000 ether));
        game.buyPotato{value: 0.01 ether}();
        _fund(500 ether);
        _buy(bob);
        assertEq(game.getRound(2).currentHolder, bob);
    }

    function test_ReserveCannotUseRecoveryOrScheduledTreasuryTokens() public {
        _fund(5_000 ether);
        _buy(bob);
        _wrap(alice, 5_000 ether);
        vm.prank(alice);
        IRecovery(address(diamond)).commitRecovery(5_000 ether);
        _wrap(treasury, 5_000 ether);
        vm.prank(treasury);
        ITreasuryRewards(address(diamond)).allocateTreasuryRewards(5_000 ether, 2, 1);
        vm.warp(game.getRound(1).deadline);
        ISettlement(address(diamond)).settleRound();
        assertEq(potato.balanceOf(address(diamond)), 14_500 ether);
        assertEq(potato.rewardReserve(), 4_500 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientRewardReserve.selector, 4_500 ether, 5_000 ether));
        game.buyPotato{value: 0.01 ether}();
        _fund(500 ether);
        _buy(alice);
        vm.warp(block.timestamp + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(potato.balanceOf(alice), 1_000 ether);
        assertEq(potato.rewardReserve(), 4_500 ether);
        assertEq(ITreasuryRewards(address(diamond)).treasuryRewardsReserved(), 4_500 ether);
    }

    function test_OrdinaryTransferRestrictedAndDistributorExemptionRetained() public {
        _wrap(alice, 2 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.TransferRestricted.selector, alice, bob));
        potato.transfer(bob, 1 ether);
        vm.prank(authority);
        potato.setDistributor(bob, true);
        vm.prank(alice);
        potato.transfer(bob, 1 ether);
        assertEq(potato.balanceOf(bob), 1 ether);
        vm.prank(alice);
        potato.transfer(authority, 1 ether);
        assertEq(potato.balanceOf(authority), 1 ether);
    }
}
