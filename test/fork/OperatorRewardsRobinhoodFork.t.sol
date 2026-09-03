// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {StaticsOperatorDependencies} from "../../script/DeploymentTypes.sol";
import {StaticsOperatorDeploymentConfig} from "../../script/libraries/StaticsOperatorDeploymentConfig.sol";
import {IGenesisActivationRegistryView, IStaticsOperators} from "../../src/interfaces/IOperatorRewards.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";

interface ITransferableOperators is IStaticsOperators {
    function transferFrom(address from, address to, uint256 operatorId) external;
}

contract ForkBurntatoClaims {
    address public treasuryRecipient;

    constructor(address treasury) {
        treasuryRecipient = treasury;
    }
}

contract OperatorRewardsRobinhoodForkTest is Test {
    uint256 internal constant FIRST_OPERATOR = 1;
    uint256 internal constant SECOND_OPERATOR = 2;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        bool requireFork = vm.envOr("REQUIRE_ROBINHOOD_FORK", false);
        if (bytes(rpc).length == 0) {
            if (requireFork) revert("ROBINHOOD_MAINNET is required");
            vm.skip(true, "ROBINHOOD_MAINNET is not configured");
        }
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        uint256 overrideBlock = vm.envOr("ROBINHOOD_OPERATOR_FORK_BLOCK", uint256(0));
        if (overrideBlock != 0) {
            assertEq(overrideBlock, dependencies.finalizedBlock, "ROBINHOOD_OPERATOR_FORK_BLOCK drift");
        }
        vm.createSelectFork(rpc, dependencies.finalizedBlock);
        StaticsOperatorDeploymentConfig.validate(dependencies);
    }

    function test_RealStaticsOwnershipWeightAndTransferDriveRedistribution() public {
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        ITransferableOperators operators = ITransferableOperators(dependencies.operatorsNft);
        IGenesisActivationRegistryView registry = IGenesisActivationRegistryView(dependencies.activationRegistry);
        address treasury = makeAddr("fork-operator-treasury");
        ForkBurntatoClaims burntato = new ForkBurntatoClaims(treasury);
        BurntatoOperatorRewardsRouter router =
            new BurntatoOperatorRewardsRouter(address(burntato), address(operators), address(registry));

        address firstOwner = operators.ownerOf(FIRST_OPERATOR);
        address secondOwner = operators.ownerOf(SECOND_OPERATOR);
        uint16 firstWeight = registry.multiplierBps(FIRST_OPERATOR);
        uint16 secondWeight = registry.multiplierBps(SECOND_OPERATOR);
        assertGt(firstWeight, 0);
        assertGt(secondWeight, 0);

        vm.prank(firstOwner);
        router.register(FIRST_OPERATOR);
        vm.prank(secondOwner);
        router.register(SECOND_OPERATOR);
        (bool funded,) = address(router).call{value: 1 ether}("");
        assertTrue(funded);

        address nextOwner = makeAddr("fork-next-operator-owner");
        vm.prank(firstOwner);
        operators.transferFrom(firstOwner, nextOwner, FIRST_OPERATOR);
        assertEq(operators.ownerOf(FIRST_OPERATOR), nextOwner);
        assertEq(registry.multiplierBps(FIRST_OPERATOR), 10_000);

        router.sync(FIRST_OPERATOR);
        vm.prank(secondOwner);
        uint256 secondClaim = router.claim(SECOND_OPERATOR, secondOwner);
        assertEq(secondClaim, 1 ether);
        assertEq(router.totalRegisteredWeight(), secondWeight);

        vm.prank(nextOwner);
        router.register(FIRST_OPERATOR);
        assertEq(router.totalRegisteredWeight(), uint256(secondWeight) + 10_000);
    }
}
