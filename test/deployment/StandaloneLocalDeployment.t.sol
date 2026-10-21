// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {DeployBurntatoLocal} from "../../script/DeployBurntatoLocal.s.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {
    GenesisConfig,
    BurntatoDeployment,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "../../script/DeploymentTypes.sol";
import {LocalStatics} from "../../script/helpers/LocalStatics.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {VerifyBurntato} from "../../script/VerifyBurntato.s.sol";

contract StandaloneDeploymentHarness is DeployBurntatoLocal {
    function localMarket() external returns (StaticsMarketDependencies memory) {
        return _localMarket(address(this));
    }
}

contract StandaloneLocalDeploymentTest is Test {
    function test_LocalFixturesSupportBackedBuybackAndFundedGameplay() public {
        vm.chainId(31337);
        StandaloneDeploymentHarness deployer = new StandaloneDeploymentHarness();
        GenesisConfig memory c = BurntatoDeploymentConfig.localDefaults();
        c.deployer = address(deployer);
        c.finalAdmin = address(this);
        vm.deal(address(deployer), 100 ether + c.initialWinnerReserve);
        StaticsMarketDependencies memory m = deployer.localMarket();
        c.statics = m.statics;
        StaticsOperatorDependencies memory o;
        BurntatoDeployment memory d = deployer.deployWithDependencies(c, address(deployer), m, o);
        new VerifyBurntato().verify(d, c, m, o, 0);
        assertEq(IPotatoToken(d.diamond).totalSupply(), 0);
        IBuyback(d.diamond).fundBuybackReserve{value: 1 ether}();
        IBuyback(d.diamond).buyback();
        uint256 acquired = IPotatoToken(d.diamond).rewardReserve();
        assertGt(acquired, 0);
        assertEq(IPotatoToken(d.diamond).backingBalance(), acquired);
        assertEq(IPotatoToken(d.diamond).publicWrapOutstanding(), 0);
        uint256 remaining = c.protocol.roundEmissionBudget - acquired;
        LocalStatics(m.statics).mint(address(this), remaining);
        LocalStatics(m.statics).approve(d.diamond, remaining);
        IPotatoToken(d.diamond).fundRewardReserve(remaining);
        IGovernance(d.diamond).initializePurchases();
        IGame(d.diamond).buyPotato{value: c.protocol.startingPrice}();
        assertEq(IGame(d.diamond).getRound(1).currentHolder, address(this));
    }

    function test_LocalFixturesRejectPublicChain() public {
        vm.chainId(4663);
        StandaloneDeploymentHarness deployer = new StandaloneDeploymentHarness();
        vm.expectRevert("standalone Anvil chain required");
        deployer.localMarket();
    }
    receive() external payable {}
}
