// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {VerifyBurntato} from "../../script/VerifyBurntato.s.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "../../script/libraries/StaticsOperatorDeploymentConfig.sol";
import {GenesisConfig, BurntatoDeployment, StaticsOperatorDependencies} from "../../script/DeploymentTypes.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {StaticsMarketDependencies} from "../../script/DeploymentTypes.sol";
import {StaticsMarketDeploymentConfig} from "../../script/libraries/StaticsMarketDeploymentConfig.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {ProtocolConfig} from "../../src/shared/Types.sol";

contract BackedStaticsForkTest is DiamondTestSetup {
    receive() external payable {}
    StaticsMarketDependencies internal market;
    bool internal enabled;

    function _initialRewardFunding() internal pure override returns (uint256) {
        return 0;
    }

    function _underlyingForInit() internal view override returns (address) {
        return market.statics;
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.roundEmissionBudget = 5_000 ether;
        config.emissionVestingDuration = 4 minutes;
    }

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) {
            require(!vm.envOr("BURNTATO_STRICT_FORK", false), "private mainnet RPC required");
            return;
        }
        vm.createSelectFork(rpc, 47_690_599);
        market = StaticsMarketDeploymentConfig.load();
        StaticsMarketDeploymentConfig.validateRuntime(market);
        _deployCore();
        vm.prank(authority);
        IBuyback(address(diamond)).setBuybackMarket(market.poolManager, market.weth, market.key);
        enabled = true;
    }

    function test_PinnedRealStaticsMarketFundsRewardsRedemptionRecoveryAndEthClaims() public {
        if (!enabled) {
            vm.skip(true);
            return;
        }
        IBuyback buybacks = IBuyback(address(diamond));
        IPotatoToken potato = IPotatoToken(address(diamond));
        IGame game = IGame(address(diamond));
        IERC20 underlyingToken = IERC20(market.statics);
        address alice = makeAddr("fork-alice");
        address bob = makeAddr("fork-bob");
        vm.deal(address(this), 100 ether);
        buybacks.fundBuybackReserve{value: 20 ether}();
        uint256 acquired;
        for (uint256 i; i < 20 && acquired < 15_000 ether; ++i) {
            vm.roll(vm.getBlockNumber() + 1);
            acquired += buybacks.buyback();
        }
        assertGe(acquired, 10_000 ether, "real market must fund complete round budgets");
        assertEq(potato.totalSupply(), acquired);
        assertEq(potato.rewardReserve(), acquired);
        assertEq(underlyingToken.balanceOf(address(diamond)), acquired);
        assertEq(potato.publicWrapOutstanding(), 0);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(vm.getBlockTimestamp() + 4 minutes);
        game.materializeMaturedEmission();
        vm.prank(alice);
        potato.unwrap(200 ether);
        assertEq(underlyingToken.balanceOf(alice), 200 ether);
        vm.startPrank(alice);
        underlyingToken.approve(address(diamond), 200 ether);
        potato.wrap(200 ether);
        IRecovery(address(diamond)).commitRecovery(500 ether);
        vm.stopPrank();
        assertEq(potato.publicWrapOutstanding(), 200 ether);
        vm.warp(game.getRound(1).deadline);
        ISettlement(address(diamond)).settleRound();
        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(vm.getBlockTimestamp() + 4 minutes);
        vm.prank(alice);
        game.buyPotato{value: 0.011 ether}();
        vm.warp(game.getRound(2).deadline);
        ISettlement(address(diamond)).settleRound();
        assertEq(underlyingToken.balanceOf(treasury), 500 ether);
        assertEq(potato.publicWrapOutstanding(), 0);
        uint256 beforeEth = alice.balance;
        vm.prank(alice);
        IClaims(address(diamond)).claimRecovery(2, alice);
        assertEq(alice.balance, beforeEth + game.getRound(2).recoveryPool);
        vm.prank(alice);
        IClaims(address(diamond)).claimWinner(2, alice);
        assertEq(underlyingToken.balanceOf(address(diamond)), potato.totalSupply());
        assertEq(potato.totalSupply(), acquired - 500 ether);
    }

    function test_PinnedFreshLaunchUsesRealDependenciesAndSourceVerifiedOperatorRouter() public {
        if (!enabled) {
            vm.skip(true);
            return;
        }
        DeployBurntato deployer = new DeployBurntato();
        GenesisConfig memory config = BurntatoDeploymentConfig.launchDefaults();
        config.deployer = address(deployer);
        config.finalAdmin = address(this);
        config.statics = market.statics;
        StaticsOperatorDependencies memory operators = StaticsOperatorDeploymentConfig.load();
        vm.deal(address(deployer), config.initialWinnerReserve);
        BurntatoDeployment memory fresh = deployer.deployWithDependencies(config, address(deployer), market, operators);
        VerifyBurntato verifier = new VerifyBurntato();
        verifier.verify(fresh, config, market, operators, 0);
        IBuyback fundedBuybacks = IBuyback(fresh.diamond);
        vm.deal(address(this), 2 ether);
        fundedBuybacks.fundBuybackReserve{value: 1 ether}();
        vm.roll(vm.getBlockNumber() + 1);
        fundedBuybacks.buyback();
        verifier.verify(fresh, config, market, operators, 1);
        IGovernance(fresh.diamond).initializePurchases();
        verifier.verify(fresh, config, market, operators, 2);
        assertEq(IGovernance(fresh.diamond).protocolConfig().operatorPurchaseBps, 1500);
        IGame(fresh.diamond).buyPotato{value: 0.01 ether}();
        vm.warp(vm.getBlockTimestamp() + 4 minutes);
        IGame(fresh.diamond).materializeMaturedEmission();
        assertEq(IPotatoToken(fresh.diamond).balanceOf(address(this)), 500 ether);
    }
}
