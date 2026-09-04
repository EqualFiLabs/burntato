// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IOperatorRewards} from "../../src/interfaces/IOperatorRewards.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";

contract InvariantOperators {
    address public activationRegistry;
    bool public constant launchFinalized = true;
    mapping(uint256 operatorId => address owner) public ownerOf;

    function configure(address registry) external {
        activationRegistry = registry;
    }

    function setOwner(uint256 operatorId, address owner) external {
        ownerOf[operatorId] = owner;
    }
}

contract InvariantActivationRegistry {
    address public genesisCollection;
    mapping(uint256 operatorId => uint16 weight) public multiplierBps;

    function configure(address collection) external {
        genesisCollection = collection;
    }

    function setWeight(uint256 operatorId, uint16 weight) external {
        multiplierBps[operatorId] = weight;
    }
}

contract InvariantBurntatoClaims {
    address public treasuryRecipient;

    constructor(address treasury) {
        treasuryRecipient = treasury;
    }
}

contract OperatorRewardsHandler is Test {
    BurntatoOperatorRewardsRouter internal immutable router;
    InvariantOperators internal immutable operators;
    InvariantActivationRegistry internal immutable registry;
    address[3] internal owners;

    constructor(
        BurntatoOperatorRewardsRouter router_,
        InvariantOperators operators_,
        InvariantActivationRegistry registry_,
        address[3] memory owners_
    ) {
        router = router_;
        operators = operators_;
        registry = registry_;
        owners = owners_;
    }

    function queueRevenue(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 10 ether);
        vm.deal(address(this), address(this).balance + amount);
        (bool success,) = address(router).call{value: amount}("");
        assertTrue(success);
    }

    function accrue() external {
        router.accrue();
    }

    function increaseWeight(uint256 seed, uint16 rawWeight) external {
        uint256 operatorId = seed % 3 + 1;
        IOperatorRewards.Registration memory registration = router.registrationOf(operatorId);
        if (registration.owner == address(0)) return;
        uint16 weight = uint16(bound(uint256(rawWeight), registration.weight, 12_500));
        registry.setWeight(operatorId, weight);
        router.sync(operatorId);
    }

    function transferAndSync(uint256 seed) external {
        uint256 operatorId = seed % 3 + 1;
        IOperatorRewards.Registration memory registration = router.registrationOf(operatorId);
        if (registration.owner == address(0)) return;
        uint256 ownerIndex = seed % owners.length;
        address nextOwner = owners[(ownerIndex + 1) % owners.length];
        if (nextOwner == registration.owner) nextOwner = owners[(ownerIndex + 2) % owners.length];
        operators.setOwner(operatorId, nextOwner);
        registry.setWeight(operatorId, 10_000);
        router.sync(operatorId);
    }

    function register(uint256 seed) external {
        uint256 operatorId = seed % 3 + 1;
        if (router.registrationOf(operatorId).owner != address(0)) return;
        address owner = operators.ownerOf(operatorId);
        vm.prank(owner);
        router.register(operatorId);
    }

    function claim(uint256 seed) external {
        uint256 operatorId = seed % 3 + 1;
        IOperatorRewards.Registration memory registration = router.registrationOf(operatorId);
        if (registration.owner == address(0) || operators.ownerOf(operatorId) != registration.owner) return;
        vm.prank(registration.owner);
        router.claim(operatorId, registration.owner);
    }

    function claimTreasury() external {
        router.claimTreasury();
    }
}

contract OperatorRewardsInvariantTest is Test {
    BurntatoOperatorRewardsRouter internal router;

    function setUp() public {
        address[3] memory owners = [makeAddr("operator-one"), makeAddr("operator-two"), makeAddr("operator-three")];
        InvariantOperators operators = new InvariantOperators();
        InvariantActivationRegistry registry = new InvariantActivationRegistry();
        InvariantBurntatoClaims burntato = new InvariantBurntatoClaims(makeAddr("invariant-treasury"));
        operators.configure(address(registry));
        registry.configure(address(operators));
        for (uint256 i; i < owners.length; ++i) {
            operators.setOwner(i + 1, owners[i]);
            registry.setWeight(i + 1, 10_000);
        }
        router = new BurntatoOperatorRewardsRouter(address(burntato), address(operators), address(registry));
        for (uint256 i; i < owners.length; ++i) {
            vm.prank(owners[i]);
            router.register(i + 1);
        }

        OperatorRewardsHandler handler = new OperatorRewardsHandler(router, operators, registry, owners);
        targetContract(address(handler));
    }

    function invariant_NativeRevenueIsConserved() public view {
        assertEq(
            router.totalReceived(),
            router.totalOperatorClaimed() + router.totalTreasuryClaimed() + address(router).balance
        );
        assertEq(router.accountedBalance(), address(router).balance);
    }

    function invariant_RegisteredWeightMatchesRegistrations() public view {
        uint256 expectedWeight;
        for (uint256 operatorId = 1; operatorId <= 3; ++operatorId) {
            expectedWeight += router.registrationOf(operatorId).weight;
        }
        assertEq(router.totalRegisteredWeight(), expectedWeight);
    }

    function invariant_ClaimsNeverExceedRevenue() public view {
        assertLe(router.totalOperatorClaimed() + router.totalTreasuryClaimed(), router.totalReceived());
    }
}
