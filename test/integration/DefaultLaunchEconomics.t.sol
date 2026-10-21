// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {MockOperatorCollection, MockActivationRegistry} from "../unit/OperatorRewardsRouter.t.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract DefaultLaunchEconomicsTest is DiamondTestSetup {
    address internal router;

    function _initialConfig() internal pure override returns (ProtocolConfig memory) {
        return BurntatoDeploymentConfig.launchDefaults().protocol;
    }

    function _operatorRewardsRouterForInit() internal override returns (address) {
        MockOperatorCollection operators = new MockOperatorCollection();
        MockActivationRegistry registry = new MockActivationRegistry();
        operators.setActivationRegistry(address(registry));
        registry.setGenesisCollection(address(operators));
        router = address(new BurntatoOperatorRewardsRouter(address(diamond), address(operators), address(registry)));
        return router;
    }

    function setUp() public {
        _deployCore();
    }

    function test_FirstGrabSpecialCaseAndLaterApprovedSplitUseBackedRewards() public {
        IGame game = IGame(address(diamond));
        IPotatoToken token = IPotatoToken(address(diamond));
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        assertEq(game.winnerReserveEth(), 0.01 ether);
        assertEq(address(router).balance, 0);
        vm.warp(vm.getBlockTimestamp() + 4 minutes);
        vm.prank(bob);
        game.buyPotato{value: 0.011 ether}();
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 0.00275 ether);
        assertEq(round.recoveryPool, 0.0033 ether);
        assertEq(IClaims(address(diamond)).treasuryEthAvailable(), 0.00165 ether);
        assertEq(IBuyback(address(diamond)).buybackReserveEth(), 0.0011 ether);
        assertEq(address(router).balance, 0.00165 ether);
        assertEq(game.winnerReserveEth(), 0.01055 ether);
        assertEq(token.balanceOf(alice), 500 ether);
        assertEq(token.totalSupply(), INITIAL_REWARD_INVENTORY);
        assertEq(token.rewardReserve(), INITIAL_REWARD_INVENTORY - 500 ether);
        assertEq(round.config.roundEmissionBudget, 5_000 ether);
        assertEq(round.deadline, vm.getBlockTimestamp() + 55 minutes);
    }
}
