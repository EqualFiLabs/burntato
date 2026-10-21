// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {DeployBurntatoLocalFork} from "../../script/DeployBurntatoLocalFork.s.sol";
import {DeployBurntatoRobinhoodMainnet} from "../../script/DeployBurntatoRobinhoodMainnet.s.sol";
import {DeployBurntatoRobinhoodTestnet} from "../../script/DeployBurntatoRobinhoodTestnet.s.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {GenesisConfig} from "../../script/DeploymentTypes.sol";
import {Errors} from "../../src/shared/Errors.sol";

contract LocalForkConfigHarness is DeployBurntatoLocalFork {
    function readConfig() external view returns (GenesisConfig memory) {
        return _environmentConfig();
    }
}

contract MainnetConfigHarness is DeployBurntatoRobinhoodMainnet {
    function readConfig() external view returns (GenesisConfig memory) {
        return _environmentConfig();
    }
}

contract TestnetConfigHarness is DeployBurntatoRobinhoodTestnet {
    function readConfig() external view returns (GenesisConfig memory) {
        return _environmentConfig();
    }
}

contract LocalDeploymentConfigurationTest is Test {
    LocalForkConfigHarness internal local;

    function setUp() public {
        vm.chainId(4663);
        local = new LocalForkConfigHarness();
        _resetEnvironment();
    }

    function _resetEnvironment() private {
        vm.chainId(4663);
        _setEconomics();
        vm.setEnv("PRIVATE_KEY", "1");
        vm.setEnv("BURNTATO_DEPLOYER", "0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316");
        vm.setEnv("BURNTATO_FINAL_ADMIN", "0x0000000000000000000000000000000000000011");
        vm.setEnv("BURNTATO_GUARDIAN", "0x0000000000000000000000000000000000000012");
        vm.setEnv("BURNTATO_TREASURY", "0x0000000000000000000000000000000000000013");
        vm.setEnv("BURNTATO_REWARD_ALLOCATOR", "0x0000000000000000000000000000000000000014");
    }

    // Environment cheatcodes are process-global, so run these cases serially in one
    // test rather than racing different environment values across Foundry workers.
    function test_LocalOverridesAndPublicConfigurationBoundaries() public {
        _resetEnvironment();
        _LocalForkReadsAllEconomicOverrides();
        _resetEnvironment();
        _InitialWinnerReserveFollowsOverriddenPriceUnlessExplicit();
        _resetEnvironment();
        _PublicNetworksIgnoreEconomicEnvironmentOverrides();
        _resetEnvironment();
        _TestnetRoleDefaultsUseCanonicalDeployer();
        _resetEnvironment();
        _LocalForkRejectsOtherChains();
        _resetEnvironment();
        _LocalForkRejectsTruncatedBps();
        _resetEnvironment();
        _LocalForkRejectsInvalidSplit();
        _resetEnvironment();
        _LocalForkRejectsInvalidTimeout();
        _resetEnvironment();
        _LocalForkRejectsTipAboveProtocolCeiling();
    }

    function _setEconomics() private {
        vm.setEnv("BURNTATO_STARTING_PRICE", "20000000000000000");
        vm.setEnv("BURNTATO_PRICE_INCREASE_BPS", "2000");
        vm.setEnv("BURNTATO_ROUND_TIMEOUT", "600");
        vm.setEnv("BURNTATO_ROUND_TIMEOUT_DECAY", "30");
        vm.setEnv("BURNTATO_MINIMUM_ROUND_TIMEOUT", "60");
        vm.setEnv("BURNTATO_ROUND_EMISSION_BUDGET", "7000000000000000000000");
        vm.setEnv("BURNTATO_EMISSION_STEP_BPS", "2000");
        vm.setEnv("BURNTATO_EMISSION_VESTING_DURATION", "120");
        vm.setEnv("BURNTATO_WINNER_BPS", "3000");
        vm.setEnv("BURNTATO_NEXT_ROUND_WINNER_BPS", "1000");
        vm.setEnv("BURNTATO_RECOVERY_BPS", "2000");
        vm.setEnv("BURNTATO_TREASURY_BPS", "2000");
        vm.setEnv("BURNTATO_BUYBACK_BPS", "1500");
        vm.setEnv("BURNTATO_OPERATOR_PURCHASE_BPS", "500");
        vm.setEnv("BURNTATO_INITIAL_WINNER_RESERVE", "30000000000000000");
        vm.setEnv("BURNTATO_BUYBACK_MAX_SPEND", "200000000000000000");
        vm.setEnv("BURNTATO_BUYBACK_CALLER_REWARD_BPS", "75");
        vm.setEnv("BURNTATO_BUYBACK_DELAY_BLOCKS", "3");
    }

    function _LocalForkReadsAllEconomicOverrides() private view {
        GenesisConfig memory c = local.readConfig();
        assertEq(c.protocol.startingPrice, 0.02 ether);
        assertEq(c.protocol.priceIncreaseBps, 2000);
        assertEq(c.protocol.roundTimeout, 600);
        assertEq(c.protocol.roundTimeoutDecay, 30);
        assertEq(c.protocol.minimumRoundTimeout, 60);
        assertEq(c.protocol.roundEmissionBudget, 7000 ether);
        assertEq(c.protocol.emissionStepBps, 2000);
        assertEq(c.protocol.emissionVestingDuration, 120);
        assertEq(c.protocol.winnerBps, 3000);
        assertEq(c.protocol.nextRoundWinnerBps, 1000);
        assertEq(c.protocol.recoveryBps, 2000);
        assertEq(c.protocol.treasuryBps, 2000);
        assertEq(c.protocol.buybackBps, 1500);
        assertEq(c.protocol.operatorPurchaseBps, 500);
        assertEq(c.initialWinnerReserve, 0.03 ether);
        assertEq(c.buyback.maxSpend, 0.2 ether);
        assertEq(c.buyback.callerRewardBps, 75);
        assertEq(c.buyback.delayBlocks, 3);
        assertEq(c.publicWrapCap, 2_000_000 ether);
        assertEq(c.finalAdmin, address(0x11));
        assertEq(c.guardian, address(0x12));
        assertEq(c.treasuryRecipient, address(0x13));
        assertEq(c.rewardAllocator, address(0x14));
    }

    function _InitialWinnerReserveFollowsOverriddenPriceUnlessExplicit() private {
        vm.setEnv("BURNTATO_INITIAL_WINNER_RESERVE", "");
        assertEq(local.readConfig().initialWinnerReserve, 0.021 ether);
        vm.setEnv("BURNTATO_STARTING_PRICE", "101");
        assertEq(local.readConfig().initialWinnerReserve, 107);
    }

    function _PublicNetworksIgnoreEconomicEnvironmentOverrides() private {
        GenesisConfig memory expected = BurntatoDeploymentConfig.launchDefaults();
        GenesisConfig memory c = new MainnetConfigHarness().readConfig();
        _assertEconomics(c, expected);
        vm.chainId(46630);
        c = new TestnetConfigHarness().readConfig();
        _assertEconomics(c, expected);
        assertEq(c.finalAdmin, address(0x11));
    }

    function _assertEconomics(GenesisConfig memory c, GenesisConfig memory expected) private pure {
        assertEq(keccak256(abi.encode(c.protocol)), keccak256(abi.encode(expected.protocol)));
        assertEq(keccak256(abi.encode(c.buyback)), keccak256(abi.encode(expected.buyback)));
        assertEq(c.initialWinnerReserve, expected.initialWinnerReserve);
    }

    function _TestnetRoleDefaultsUseCanonicalDeployer() private {
        vm.chainId(46630);
        vm.setEnv("BURNTATO_FINAL_ADMIN", "");
        vm.setEnv("BURNTATO_GUARDIAN", "");
        vm.setEnv("BURNTATO_TREASURY", "");
        vm.setEnv("BURNTATO_REWARD_ALLOCATOR", "");
        GenesisConfig memory c = new TestnetConfigHarness().readConfig();
        assertEq(c.finalAdmin, c.deployer);
        assertEq(c.guardian, c.deployer);
        assertEq(c.treasuryRecipient, c.deployer);
        assertEq(c.rewardAllocator, c.deployer);
    }

    function _LocalForkRejectsOtherChains() private {
        vm.chainId(46630);
        vm.expectRevert("mainnet fork required");
        local.readConfig();
        vm.expectRevert("mainnet fork required");
        local.run();
    }

    function _LocalForkRejectsTruncatedBps() private {
        vm.setEnv("BURNTATO_WINNER_BPS", "65536");
        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        local.readConfig();
    }

    function _LocalForkRejectsInvalidSplit() private {
        vm.setEnv("BURNTATO_WINNER_BPS", "3001");
        vm.expectRevert(Errors.InvalidProtocolConfig.selector);
        local.readConfig();
    }

    function _LocalForkRejectsInvalidTimeout() private {
        vm.setEnv("BURNTATO_MINIMUM_ROUND_TIMEOUT", "601");
        vm.expectRevert(Errors.InvalidProtocolConfig.selector);
        local.readConfig();
    }

    function _LocalForkRejectsTipAboveProtocolCeiling() private {
        vm.setEnv("BURNTATO_BUYBACK_CALLER_REWARD_BPS", "101");
        vm.expectRevert(bytes4(keccak256("InvalidGenesisConfiguration()")));
        local.readConfig();
    }
}
