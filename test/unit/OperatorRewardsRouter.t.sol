// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IOperatorRewards} from "../../src/interfaces/IOperatorRewards.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";

contract MockOperatorCollection {
    address public activationRegistry;
    bool public launchFinalized = true;
    mapping(uint256 operatorId => address owner) public ownerOf;

    function setActivationRegistry(address registry) external {
        activationRegistry = registry;
    }

    function setLaunchFinalized(bool finalized) external {
        launchFinalized = finalized;
    }

    function setOwner(uint256 operatorId, address owner) external {
        ownerOf[operatorId] = owner;
    }
}

contract MockActivationRegistry {
    address public genesisCollection;
    mapping(uint256 operatorId => uint16 weight) public multiplierBps;

    function setGenesisCollection(address collection) external {
        genesisCollection = collection;
    }

    function setWeight(uint256 operatorId, uint16 weight) external {
        multiplierBps[operatorId] = weight;
    }
}

contract MockBurntatoClaims {
    address public treasuryRecipient;

    constructor(address treasury) {
        treasuryRecipient = treasury;
    }

    function setTreasuryRecipient(address treasury) external {
        treasuryRecipient = treasury;
    }
}

contract ReentrantRewardReceiver {
    BurntatoOperatorRewardsRouter internal immutable router;
    uint256 internal immutable operatorId;
    bool public reentryBlocked;

    constructor(BurntatoOperatorRewardsRouter router_, uint256 operatorId_) {
        router = router_;
        operatorId = operatorId_;
    }

    receive() external payable {
        try router.claim(operatorId, address(this)) returns (uint256) {}
        catch {
            reentryBlocked = true;
        }
    }
}

contract RejectingRewardReceiver {
    receive() external payable {
        revert();
    }
}

contract ForceNative {
    constructor() payable {}

    function force(address payable receiver) external {
        selfdestruct(receiver);
    }
}

contract OperatorRewardsRouterTest is Test {
    uint256 internal constant ALICE_OPERATOR = 1;
    uint256 internal constant BOB_OPERATOR = 2;

    address internal alice = makeAddr("operator-alice");
    address internal bob = makeAddr("operator-bob");
    address internal carol = makeAddr("operator-carol");
    address internal treasury = makeAddr("treasury");
    address internal nextTreasury = makeAddr("next-treasury");

    MockOperatorCollection internal operators;
    MockActivationRegistry internal registry;
    MockBurntatoClaims internal burntato;
    BurntatoOperatorRewardsRouter internal router;

    function setUp() public {
        operators = new MockOperatorCollection();
        registry = new MockActivationRegistry();
        burntato = new MockBurntatoClaims(treasury);
        operators.setActivationRegistry(address(registry));
        registry.setGenesisCollection(address(operators));
        operators.setOwner(ALICE_OPERATOR, alice);
        operators.setOwner(BOB_OPERATOR, bob);
        registry.setWeight(ALICE_OPERATOR, 10_000);
        registry.setWeight(BOB_OPERATOR, 10_000);
        router = new BurntatoOperatorRewardsRouter(address(burntato), address(operators), address(registry));
    }

    function test_ConstructorValidatesFinalizedCrossBindings() public {
        MockOperatorCollection candidateOperators = new MockOperatorCollection();
        MockActivationRegistry candidateRegistry = new MockActivationRegistry();
        candidateOperators.setActivationRegistry(address(candidateRegistry));
        candidateRegistry.setGenesisCollection(address(candidateOperators));
        candidateOperators.setLaunchFinalized(false);

        vm.expectRevert(BurntatoOperatorRewardsRouter.StaticsLaunchNotFinalized.selector);
        new BurntatoOperatorRewardsRouter(address(burntato), address(candidateOperators), address(candidateRegistry));

        candidateOperators.setLaunchFinalized(true);
        candidateRegistry.setGenesisCollection(address(operators));
        vm.expectRevert(BurntatoOperatorRewardsRouter.InvalidDependencyBinding.selector);
        new BurntatoOperatorRewardsRouter(address(burntato), address(candidateOperators), address(candidateRegistry));
    }

    function test_RegisterAccrueAndClaimCurrentOwner() public {
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(10 ether);

        (address currentOwner, uint16 currentWeight, bool transferred, uint256 claimable,,) =
            router.previewRewards(ALICE_OPERATOR);
        assertEq(currentOwner, alice);
        assertEq(currentWeight, 10_000);
        assertFalse(transferred);
        assertEq(claimable, 10 ether);

        uint256 beforeBalance = carol.balance;
        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, carol), 10 ether);
        assertEq(carol.balance - beforeBalance, 10 ether);
        assertEq(router.totalOperatorClaimed(), 10 ether);
        assertEq(address(router).balance, 0);
    }

    function test_BatchRegisterStartsOwnedOperatorsProspectively() public {
        operators.setOwner(BOB_OPERATOR, alice);
        registry.setWeight(BOB_OPERATOR, 12_500);
        _sendRevenue(3 ether);

        uint256[] memory operatorIds = _twoOperatorIds();
        vm.expectEmit(false, false, false, true, address(router));
        emit IOperatorRewards.RevenueAccrued(3 ether, 0, 0);
        vm.expectEmit(true, true, false, true, address(router));
        emit IOperatorRewards.OperatorRegistered(ALICE_OPERATOR, alice, 10_000);
        vm.expectEmit(true, true, false, true, address(router));
        emit IOperatorRewards.OperatorRegistered(BOB_OPERATOR, alice, 12_500);
        vm.prank(alice);
        router.registerBatch(operatorIds);

        assertEq(router.registrationOf(ALICE_OPERATOR).owner, alice);
        assertEq(router.registrationOf(BOB_OPERATOR).owner, alice);
        assertEq(router.totalRegisteredWeight(), 22_500);
        assertEq(router.treasuryClaimable(), 3 ether);
        _sendRevenue(22.5 ether);
        vm.prank(alice);
        assertEq(router.claimBatch(operatorIds, alice), 22.5 ether);
    }

    function test_BatchRegisterRequiresNonemptyStrictlyIncreasingIds() public {
        uint256[] memory empty = new uint256[](0);
        vm.prank(alice);
        vm.expectRevert(BurntatoOperatorRewardsRouter.EmptyOperatorBatch.selector);
        router.registerBatch(empty);

        operators.setOwner(BOB_OPERATOR, alice);
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = ALICE_OPERATOR;
        duplicate[1] = ALICE_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, ALICE_OPERATOR, ALICE_OPERATOR
            )
        );
        router.registerBatch(duplicate);
        assertEq(router.registrationOf(ALICE_OPERATOR).owner, address(0));

        uint256[] memory descending = new uint256[](2);
        descending[0] = BOB_OPERATOR;
        descending[1] = ALICE_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, BOB_OPERATOR, ALICE_OPERATOR
            )
        );
        router.registerBatch(descending);
        assertEq(router.registrationOf(BOB_OPERATOR).owner, address(0));
    }

    function test_BatchRegisterRevertsAtomicallyWhenAnyOperatorIsNotOwned() public {
        _sendRevenue(3 ether);
        uint256[] memory operatorIds = _twoOperatorIds();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOwner.selector, BOB_OPERATOR, alice, bob
            )
        );
        router.registerBatch(operatorIds);

        assertEq(router.registrationOf(ALICE_OPERATOR).owner, address(0));
        assertEq(router.registrationOf(BOB_OPERATOR).owner, address(0));
        assertEq(router.totalRegisteredWeight(), 0);
        assertEq(router.pendingRevenue(), 3 ether);
        assertEq(router.treasuryClaimable(), 0);
    }

    function test_BatchRegisterReplacesTransferredRegistration() public {
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(4 ether);
        operators.setOwner(ALICE_OPERATOR, carol);
        operators.setOwner(BOB_OPERATOR, carol);

        uint256[] memory operatorIds = _twoOperatorIds();
        vm.prank(carol);
        router.registerBatch(operatorIds);

        assertEq(router.registrationOf(ALICE_OPERATOR).owner, carol);
        assertEq(router.registrationOf(BOB_OPERATOR).owner, carol);
        assertEq(router.totalRegisteredWeight(), 20_000);
        assertEq(router.treasuryClaimable(), 4 ether);
    }

    function test_BatchSyncAppliesMixedCanonicalTransitions() public {
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(20 ether);
        registry.setWeight(ALICE_OPERATOR, 12_500);
        operators.setOwner(BOB_OPERATOR, carol);

        router.syncBatch(_twoOperatorIds());

        assertEq(router.registrationOf(ALICE_OPERATOR).weight, 12_500);
        assertEq(router.registrationOf(BOB_OPERATOR).owner, address(0));
        assertEq(router.totalRegisteredWeight(), 12_500);
        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, alice), 20 ether);
    }

    function test_BatchSyncRevertsAtomicallyWhenAnyOperatorIsUnregistered() public {
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(10 ether);
        registry.setWeight(ALICE_OPERATOR, 12_500);

        vm.expectRevert(
            abi.encodeWithSelector(BurntatoOperatorRewardsRouter.OperatorNotRegistered.selector, BOB_OPERATOR)
        );
        router.syncBatch(_twoOperatorIds());

        assertEq(router.registrationOf(ALICE_OPERATOR).weight, 10_000);
        assertEq(router.totalRegisteredWeight(), 10_000);
        assertEq(router.pendingRevenue(), 10 ether);
        (,,, uint256 claimable,,) = router.previewRewards(ALICE_OPERATOR);
        assertEq(claimable, 10 ether);
    }

    function test_BatchSyncRequiresNonemptyStrictlyIncreasingIds() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert(BurntatoOperatorRewardsRouter.EmptyOperatorBatch.selector);
        router.syncBatch(empty);

        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = ALICE_OPERATOR;
        duplicate[1] = ALICE_OPERATOR;
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, ALICE_OPERATOR, ALICE_OPERATOR
            )
        );
        router.syncBatch(duplicate);

        uint256[] memory descending = new uint256[](2);
        descending[0] = BOB_OPERATOR;
        descending[1] = ALICE_OPERATOR;
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, BOB_OPERATOR, ALICE_OPERATOR
            )
        );
        router.syncBatch(descending);
    }

    function test_BatchClaimPaysMultipleOperatorsThroughOneReceiver() public {
        operators.setOwner(BOB_OPERATOR, alice);
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, alice);
        _sendRevenue(20 ether);

        uint256[] memory operatorIds = new uint256[](2);
        operatorIds[0] = ALICE_OPERATOR;
        operatorIds[1] = BOB_OPERATOR;
        uint256 beforeBalance = carol.balance;
        vm.prank(alice);
        assertEq(router.claimBatch(operatorIds, carol), 20 ether);

        assertEq(carol.balance - beforeBalance, 20 ether);
        assertEq(router.totalOperatorClaimed(), 20 ether);
        assertEq(address(router).balance, 0);
        (,,, uint256 aliceClaimable,,) = router.previewRewards(ALICE_OPERATOR);
        (,,, uint256 bobClaimable,,) = router.previewRewards(BOB_OPERATOR);
        assertEq(aliceClaimable, 0);
        assertEq(bobClaimable, 0);
    }

    function test_BatchClaimRequiresNonemptyStrictlyIncreasingIds() public {
        uint256[] memory empty = new uint256[](0);
        vm.prank(alice);
        vm.expectRevert(BurntatoOperatorRewardsRouter.EmptyOperatorBatch.selector);
        router.claimBatch(empty, alice);

        operators.setOwner(BOB_OPERATOR, alice);
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, alice);

        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = ALICE_OPERATOR;
        duplicate[1] = ALICE_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, ALICE_OPERATOR, ALICE_OPERATOR
            )
        );
        router.claimBatch(duplicate, alice);

        uint256[] memory descending = new uint256[](2);
        descending[0] = BOB_OPERATOR;
        descending[1] = ALICE_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOrder.selector, BOB_OPERATOR, ALICE_OPERATOR
            )
        );
        router.claimBatch(descending, alice);
    }

    function test_BatchClaimRevertsAtomicallyWhenAnyOperatorIsNotOwned() public {
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(20 ether);

        uint256[] memory operatorIds = new uint256[](2);
        operatorIds[0] = ALICE_OPERATOR;
        operatorIds[1] = BOB_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOwner.selector, BOB_OPERATOR, alice, bob
            )
        );
        router.claimBatch(operatorIds, alice);

        assertEq(router.totalOperatorClaimed(), 0);
        assertEq(address(router).balance, 20 ether);
        (,,, uint256 aliceClaimable,,) = router.previewRewards(ALICE_OPERATOR);
        (,,, uint256 bobClaimable,,) = router.previewRewards(BOB_OPERATOR);
        assertEq(aliceClaimable, 10 ether);
        assertEq(bobClaimable, 10 ether);
    }

    function test_BatchClaimRollsBackWhenReceiverRejectsPayment() public {
        operators.setOwner(BOB_OPERATOR, alice);
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, alice);
        _sendRevenue(20 ether);
        RejectingRewardReceiver rejecting = new RejectingRewardReceiver();

        uint256[] memory operatorIds = new uint256[](2);
        operatorIds[0] = ALICE_OPERATOR;
        operatorIds[1] = BOB_OPERATOR;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.NativeTransferFailed.selector, address(rejecting), 20 ether
            )
        );
        router.claimBatch(operatorIds, address(rejecting));

        assertEq(router.totalOperatorClaimed(), 0);
        (,,, uint256 aliceClaimable,,) = router.previewRewards(ALICE_OPERATOR);
        (,,, uint256 bobClaimable,,) = router.previewRewards(BOB_OPERATOR);
        assertEq(aliceClaimable, 10 ether);
        assertEq(bobClaimable, 10 ether);
    }

    function test_RegistersEverySupportedActivationTier() public {
        uint16[5] memory weights = [uint16(10_000), 11_000, 11_500, 12_000, 12_500];
        for (uint256 i; i < weights.length; ++i) {
            uint256 operatorId = 10 + i;
            address owner = makeAddr(string.concat("tier-owner-", vm.toString(i)));
            operators.setOwner(operatorId, owner);
            registry.setWeight(operatorId, weights[i]);
            _register(operatorId, owner);
            assertEq(router.registrationOf(operatorId).weight, weights[i]);
        }
        assertEq(router.totalRegisteredWeight(), 57_000);
    }

    function test_RegistrationDoesNotReceiveHistoricalRevenue() public {
        _sendRevenue(3 ether);
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(2 ether);

        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, alice), 2 ether);
        assertEq(router.treasuryClaimable(), 3 ether);
    }

    function test_SyncAppliesActivationIncreaseProspectively() public {
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(20 ether);
        registry.setWeight(ALICE_OPERATOR, 12_500);
        _sendRevenue(20 ether);

        assertEq(uint256(router.sync(ALICE_OPERATOR)), uint256(IOperatorRewards.SyncResult.WeightIncreased));
        assertEq(router.totalRegisteredWeight(), 22_500);
        _sendRevenue(22.5 ether);

        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, alice), 32.5 ether);
        vm.prank(bob);
        assertEq(router.claim(BOB_OPERATOR, bob), 30 ether);
    }

    function test_TransferInvalidatesAndRedistributesToRemainingOperators() public {
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(20 ether);

        operators.setOwner(ALICE_OPERATOR, carol);
        registry.setWeight(ALICE_OPERATOR, 10_000);
        assertEq(uint256(router.sync(ALICE_OPERATOR)), uint256(IOperatorRewards.SyncResult.Invalidated));
        assertEq(router.totalRegisteredWeight(), 10_000);

        vm.prank(bob);
        assertEq(router.claim(BOB_OPERATOR, bob), 20 ether);

        _register(ALICE_OPERATOR, carol);
        _sendRevenue(20 ether);
        vm.prank(carol);
        assertEq(router.claim(ALICE_OPERATOR, carol), 10 ether);
        vm.prank(bob);
        assertEq(router.claim(BOB_OPERATOR, bob), 10 ether);
    }

    function test_NewOwnerClaimInvalidatesButMustRegisterExplicitly() public {
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(4 ether);
        operators.setOwner(ALICE_OPERATOR, carol);

        vm.prank(carol);
        assertEq(router.claim(ALICE_OPERATOR, carol), 0);
        assertEq(router.totalRegisteredWeight(), 0);
        assertEq(router.treasuryClaimable(), 4 ether);
        assertEq(router.registrationOf(ALICE_OPERATOR).owner, address(0));

        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(BurntatoOperatorRewardsRouter.OperatorNotRegistered.selector, ALICE_OPERATOR)
        );
        router.claim(ALICE_OPERATOR, carol);
        _register(ALICE_OPERATOR, carol);
    }

    function test_WeightDecreaseProvesTransferAndForfeits() public {
        registry.setWeight(ALICE_OPERATOR, 12_500);
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(5 ether);
        registry.setWeight(ALICE_OPERATOR, 10_000);

        assertEq(uint256(router.sync(ALICE_OPERATOR)), uint256(IOperatorRewards.SyncResult.Invalidated));
        assertEq(router.treasuryClaimable(), 5 ether);
        assertEq(router.totalRegisteredWeight(), 0);
    }

    function test_FractionalForfeitureConservesSingleWei() public {
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(1);
        operators.setOwner(ALICE_OPERATOR, carol);

        router.sync(ALICE_OPERATOR);
        vm.prank(bob);
        assertEq(router.claim(BOB_OPERATOR, bob), 1);
        assertEq(address(router).balance, 0);
    }

    function test_ZeroWeightRevenueAndSoleForfeitureFollowTreasuryRotation() public {
        _sendRevenue(2 ether);
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(3 ether);
        operators.setOwner(ALICE_OPERATOR, carol);
        router.sync(ALICE_OPERATOR);
        burntato.setTreasuryRecipient(nextTreasury);

        uint256 beforeBalance = nextTreasury.balance;
        assertEq(router.claimTreasury(), 5 ether);
        assertEq(nextTreasury.balance - beforeBalance, 5 ether);
        assertEq(router.totalTreasuryClaimed(), 5 ether);
    }

    function test_ForcedNativeIsReconciledAsOperatorRevenue() public {
        _register(ALICE_OPERATOR, alice);
        ForceNative forceNative = new ForceNative{value: 7 ether}();
        forceNative.force(payable(address(router)));
        assertEq(router.pendingRevenue(), 0);

        assertEq(router.accrue(), 7 ether);
        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, alice), 7 ether);
        assertEq(router.totalReceived(), 7 ether);
    }

    function test_ReceiveFitsHookTransferGasStipend() public {
        (bool success,) = address(router).call{value: 1 ether, gas: 100_000}("");
        assertTrue(success);
        assertEq(router.pendingRevenue(), 1 ether);
    }

    function test_ClaimUsesReentrancyGuardAndRollsBackRejectedPayment() public {
        _register(ALICE_OPERATOR, alice);
        _sendRevenue(2 ether);
        ReentrantRewardReceiver receiver = new ReentrantRewardReceiver(router, ALICE_OPERATOR);

        vm.prank(alice);
        assertEq(router.claim(ALICE_OPERATOR, address(receiver)), 2 ether);
        assertTrue(receiver.reentryBlocked());

        _sendRevenue(1 ether);
        RejectingRewardReceiver rejecting = new RejectingRewardReceiver();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.NativeTransferFailed.selector, address(rejecting), 1 ether
            )
        );
        router.claim(ALICE_OPERATOR, address(rejecting));
        assertEq(router.registrationOf(ALICE_OPERATOR).claimable, 0);
        (,,, uint256 claimable,,) = router.previewRewards(ALICE_OPERATOR);
        assertEq(claimable, 1 ether);
    }

    function test_RejectsUnauthorizedRegistrationAndClaim() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOwner.selector, ALICE_OPERATOR, bob, alice
            )
        );
        router.register(ALICE_OPERATOR);

        _register(ALICE_OPERATOR, alice);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoOperatorRewardsRouter.InvalidOperatorOwner.selector, ALICE_OPERATOR, bob, alice
            )
        );
        router.claim(ALICE_OPERATOR, bob);
    }

    function testFuzz_WeightedClaimsConserveRevenue(uint96 rawRevenue, uint16 aliceWeight, uint16 bobWeight) public {
        uint256 revenue = bound(uint256(rawRevenue), 1, 100 ether);
        aliceWeight = uint16(bound(uint256(aliceWeight), 1, 12_500));
        bobWeight = uint16(bound(uint256(bobWeight), 1, 12_500));
        registry.setWeight(ALICE_OPERATOR, aliceWeight);
        registry.setWeight(BOB_OPERATOR, bobWeight);
        _register(ALICE_OPERATOR, alice);
        _register(BOB_OPERATOR, bob);
        _sendRevenue(revenue);

        vm.prank(alice);
        uint256 aliceClaim = router.claim(ALICE_OPERATOR, alice);
        vm.prank(bob);
        uint256 bobClaim = router.claim(BOB_OPERATOR, bob);
        assertLe(aliceClaim + bobClaim, revenue);
        assertEq(router.totalReceived(), aliceClaim + bobClaim + address(router).balance);
    }

    function _register(uint256 operatorId, address owner) private {
        vm.prank(owner);
        router.register(operatorId);
    }

    function _twoOperatorIds() private pure returns (uint256[] memory operatorIds) {
        operatorIds = new uint256[](2);
        operatorIds[0] = ALICE_OPERATOR;
        operatorIds[1] = BOB_OPERATOR;
    }

    function _sendRevenue(uint256 amount) private {
        (bool success,) = address(router).call{value: amount}("");
        assertTrue(success);
    }
}
