// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {StaticsMarketDeploymentConfig} from "../../script/libraries/StaticsMarketDeploymentConfig.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {StaticsMarketDependencies, GenesisConfig} from "../../script/DeploymentTypes.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract RobinhoodMarketManifestTest is Test {
    function test_MainnetSourcePinnedMarket() public {
        vm.chainId(4663);
        _assertManifest();
        StaticsMarketDependencies memory d = StaticsMarketDeploymentConfig.load();
        assertEq(d.forkBlock, 47690599);
        assertEq(d.statics, 0x2d8d6F4A93AcD7a916A5a654ec8b690bA3B3EAdd);
    }

    function test_TestnetSourcePinnedMarket() public {
        vm.chainId(46630);
        _assertManifest();
        assertEq(StaticsMarketDeploymentConfig.load().forkBlock, 112319205);
    }

    function _assertManifest() private view {
        StaticsMarketDependencies memory d = StaticsMarketDeploymentConfig.load();
        assertEq(PoolId.unwrap(PoolIdLibrary.toId(d.key)), d.poolId);
        assertEq(d.chainId, block.chainid);
        assertNotEq(d.forkBlockHash, bytes32(0));
        assertNotEq(d.staticsCodeHash, bytes32(0));
        assertNotEq(d.wethCodeHash, bytes32(0));
        assertNotEq(d.poolManagerCodeHash, bytes32(0));
        assertNotEq(d.hookCodeHash, bytes32(0));
        assertTrue(Currency.unwrap(d.key.currency0) < Currency.unwrap(d.key.currency1));
        StaticsMarketDeploymentConfig.requireManifest(d);
    }

    function requireManifest(StaticsMarketDependencies memory d) external view {
        StaticsMarketDeploymentConfig.requireManifest(d);
    }

    function test_ManifestOverridesCannotSubstituteAnotherAsset() public {
        vm.chainId(4663);
        StaticsMarketDependencies memory d = StaticsMarketDeploymentConfig.load();
        d.statics = address(123);
        vm.expectRevert(StaticsMarketDeploymentConfig.InvalidMarketManifest.selector);
        this.requireManifest(d);
    }

    function test_ProductionDefaultsMatchApprovedEconomics() public pure {
        GenesisConfig memory c = BurntatoDeploymentConfig.launchDefaults();
        assertEq(c.protocol.roundEmissionBudget, 5_000 ether);
        assertEq(c.publicWrapCap, 2_000_000 ether);
        assertEq(c.protocol.winnerBps, 2500);
        assertEq(c.protocol.nextRoundWinnerBps, 500);
        assertEq(c.protocol.recoveryBps, 3000);
        assertEq(c.protocol.treasuryBps, 1500);
        assertEq(c.protocol.buybackBps, 1000);
        assertEq(c.protocol.operatorPurchaseBps, 1500);
        assertEq(c.protocol.emissionVestingDuration, 4 minutes);
        assertEq(c.initialWinnerReserve, 0.0105 ether);
        assertEq(c.buyback.maxSpend, 1 ether);
        assertEq(c.buyback.callerRewardBps, 50);
        assertEq(c.buyback.delayBlocks, 1);
    }
}
